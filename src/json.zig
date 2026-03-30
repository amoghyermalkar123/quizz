const std = @import("std");

const Allocator = std.mem.Allocator;
const Stringify = std.json.Stringify;
const Writer = std.Io.Writer;

pub fn value(v: anytype, options: Stringify.Options, writer: *Writer) Writer.Error!void {
    var jws: Stringify = .{
        .writer = writer,
        .options = options,
    };
    try writeValue(&jws, @TypeOf(v), v);
}

pub fn valueAlloc(gpa: Allocator, v: anytype, options: Stringify.Options) error{OutOfMemory}![]u8 {
    var out: Writer.Allocating = .init(gpa);
    defer out.deinit();

    value(v, options, &out.writer) catch return error.OutOfMemory;
    return out.toOwnedSlice();
}

fn writeValue(jws: *Stringify, comptime T: type, v: T) Writer.Error!void {
    switch (@typeInfo(T)) {
        .bool,
        .int,
        .comptime_int,
        .float,
        .comptime_float,
        .null,
        .@"enum" => {
            if (std.meta.hasFn(T, "jsonStringify")) return v.jsonStringify(jws);
            return jws.write(v);
        },
        .enum_literal,
        .error_set,
        => return jws.write(v),

        .optional => |opt| {
            if (v) |inner| {
                return writeValue(jws, opt.child, inner);
            }
            return jws.write(null);
        },

        .pointer => |ptr| switch (ptr.size) {
            .one => switch (@typeInfo(ptr.child)) {
                .array => {
                    const Slice = []const std.meta.Elem(ptr.child);
                    return writeValue(jws, Slice, @as(Slice, v));
                },
                else => return writeValue(jws, ptr.child, v.*),
            },
            .many, .slice => {
                if (ptr.size == .many and ptr.sentinel() == null) {
                    @compileError("Unable to stringify many-pointer without sentinel: " ++ @typeName(T));
                }

                const slice = if (ptr.size == .many) std.mem.span(v) else v;
                if (ptr.child == u8) return jws.write(slice);

                try jws.beginArray();
                for (slice) |item| {
                    try writeValue(jws, ptr.child, item);
                }
                return jws.endArray();
            },
            else => @compileError("Unsupported pointer type in custom JSON serializer: " ++ @typeName(T)),
        },

        .array => |arr| {
            try jws.beginArray();
            for (v) |item| {
                try writeValue(jws, arr.child, item);
            }
            return jws.endArray();
        },

        .vector => |vec| {
            const array: [vec.len]vec.child = v;
            return writeValue(jws, @TypeOf(array), array);
        },

        .@"struct" => |info| {
            if (std.meta.hasFn(T, "jsonStringify")) return v.jsonStringify(jws);
            if (@hasDecl(T, "KV")) return writeHashMap(jws, T, v);
            if (@hasField(T, "items")) return writeValue(jws, @TypeOf(v.items), v.items);

            try jws.beginObject();
            inline for (info.fields) |field| {
                if (field.type == void) continue;
                if (field.type == std.mem.Allocator) continue;

                var emit_field = true;
                if (@typeInfo(field.type) == .optional and !jws.options.emit_null_optional_fields) {
                    if (@field(v, field.name) == null) emit_field = false;
                }
                if (emit_field) {
                    try jws.objectField(field.name);
                    try writeValue(jws, field.type, @field(v, field.name));
                }
            }
            return jws.endObject();
        },

        .@"union" => |union_info| {
            if (std.meta.hasFn(T, "jsonStringify")) return v.jsonStringify(jws);
            if (union_info.tag_type) |Tag| {
                try jws.beginObject();
                inline for (union_info.fields) |field| {
                    if (v == @field(Tag, field.name)) {
                        try jws.objectField(field.name);
                        if (field.type == void) {
                            try jws.beginObject();
                            try jws.endObject();
                        } else {
                            try writeValue(jws, field.type, @field(v, field.name));
                        }
                        break;
                    }
                } else unreachable;
                return jws.endObject();
            }

            @compileError("Unable to stringify untagged union: " ++ @typeName(T));
        },

        else => @compileError("Unsupported type in custom JSON serializer: " ++ @typeName(T)),
    }
}

fn writeHashMap(jws: *Stringify, comptime MapType: type, map: MapType) Writer.Error!void {
    const key_type, const value_type = comptime hashMapTypes(MapType);

    if (value_type == void) {
        try jws.beginArray();
        var set_it = map.iterator();
        while (set_it.next()) |entry| {
            try writeMapKeyAsValue(jws, key_type, entry.key_ptr.*);
        }
        return jws.endArray();
    }

    try jws.beginObject();
    var it = map.iterator();
    while (it.next()) |entry| {
        try objectFieldFromKey(jws, key_type, entry.key_ptr.*);
        try writeValue(jws, value_type, entry.value_ptr.*);
    }
    return jws.endObject();
}

fn objectFieldFromKey(jws: *Stringify, comptime KeyType: type, key: KeyType) Writer.Error!void {
    switch (@typeInfo(KeyType)) {
        .pointer => return jws.objectField(key),
        .@"enum" => return jws.objectField(@tagName(key)),
        .int => {
            var buf: [64]u8 = undefined;
            const field_name = std.fmt.bufPrint(&buf, "{}", .{key}) catch unreachable;
            return jws.objectField(field_name);
        },
        else => @compileError("Unsupported map key type in custom JSON serializer: " ++ @typeName(KeyType)),
    }
}

fn writeMapKeyAsValue(jws: *Stringify, comptime KeyType: type, key: KeyType) Writer.Error!void {
    switch (@typeInfo(KeyType)) {
        .pointer, .@"enum", .int => return writeValue(jws, KeyType, key),
        else => @compileError("Unsupported set key type in custom JSON serializer: " ++ @typeName(KeyType)),
    }
}

fn hashMapTypes(comptime MapType: type) struct { type, type } {
    const kv_info = @typeInfo(MapType.KV).@"struct".fields;
    var key_type: ?type = null;
    var value_type: ?type = null;

    inline for (kv_info) |field| {
        if (std.mem.eql(u8, field.name, "key")) key_type = field.type;
        if (std.mem.eql(u8, field.name, "value")) value_type = field.type;
    }

    return .{
        key_type orelse @compileError("No key field found in hashmap type: " ++ @typeName(MapType)),
        value_type orelse @compileError("No value field found in hashmap type: " ++ @typeName(MapType)),
    };
}

test "valueAlloc stringifies nested custom structs, array lists, and maps" {
    const Role = enum { Follower, Candidate, Leader };
    const Log = struct {
        index: i64,
        term: i64,
    };
    const Snapshot = struct {
        currentTerm: std.StringHashMap(i64),
        role: Role,
        logs: std.ArrayList(Log),
        votedFor: ?[]const u8,
        allocator: std.mem.Allocator,
    };

    const gpa = std.testing.allocator;

    var current_term = std.StringHashMap(i64).init(gpa);
    defer current_term.deinit();
    try current_term.put("n1", 1);
    try current_term.put("n2", 2);

    var logs: std.ArrayList(Log) = .empty;
    defer logs.deinit(gpa);
    try logs.append(gpa, .{ .index = 1, .term = 1 });
    try logs.append(gpa, .{ .index = 2, .term = 2 });

    const snapshot = Snapshot{
        .currentTerm = current_term,
        .role = .Leader,
        .logs = logs,
        .votedFor = "n1",
        .allocator = gpa,
    };

    const actual = try valueAlloc(gpa, snapshot, .{});
    defer gpa.free(actual);

    try std.testing.expect(std.mem.indexOf(u8, actual, "\"role\":\"Leader\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, actual, "\"logs\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, actual, "\"votedFor\":\"n1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, actual, "\"currentTerm\":{") != null);
    try std.testing.expect(std.mem.indexOf(u8, actual, "\"n1\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, actual, "\"n2\":2") != null);
}

test "valueAlloc stringifies string hash map of void as array" {
    const gpa = std.testing.allocator;

    var set = std.StringHashMap(void).init(gpa);
    defer set.deinit();
    try set.put("n1", {});
    try set.put("n2", {});

    const actual = try valueAlloc(gpa, set, .{});
    defer gpa.free(actual);

    try std.testing.expect(actual[0] == '[');
    try std.testing.expect(actual[actual.len - 1] == ']');
    try std.testing.expect(std.mem.indexOf(u8, actual, "\"n1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, actual, "\"n2\"") != null);
}

test "valueAlloc stringifies tagged unions recursively" {
    const Payload = union(enum) {
        none,
        some: std.ArrayList(i64),
    };

    const gpa = std.testing.allocator;
    var list: std.ArrayList(i64) = .empty;
    defer list.deinit(gpa);
    try list.append(gpa, 1);
    try list.append(gpa, 2);

    const actual = try valueAlloc(gpa, Payload{ .some = list }, .{});
    defer gpa.free(actual);

    try std.testing.expectEqualStrings("{\"some\":[1,2]}", actual);
}
