// exports
pub const QuizDriver = @import("driver.zig");
pub const run_test = @import("runner.zig").run_test;

const std = @import("std");

// native type for an ItfTrace
pub const Trace = struct {
    meta: ?TraceMetadata = null,
    vars: ?[]const []const u8 = null,
    states: std.ArrayList(State),
    loop_index: ?usize = null,
};

const ItfTrace = struct {
    @"#meta": TraceMetadata,
    vars: []const []const u8,
    states: []const std.json.Value,
    loop_index: ?usize = null,
};

pub const TraceMetadata = struct {
    format: []const u8,
    @"format-description": []const u8,
    source: []const u8,
    status: []const u8,
    description: []const u8,
    timestamp: i64,
};

pub const State = struct {
    index: usize,
    meta: ?std.StringHashMap(Values) = null,
    variables: std.StringHashMap(Values),

    pub fn deinit(self: *State, gpa: std.mem.Allocator) void {
        var it = self.variables.iterator();
        defer self.variables.deinit();

        while (it.next()) |entry| {
            gpa.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit(gpa);
        }
    }
};

// ITF value (sum type / tagged union)
pub const ValueTypes = enum {
    Boolean,
    String,
    BigInt,
    List,
    Tuple,
    Set,
    Map,
    Record,
    Variant,
    Unserializable,
};

pub const VariantType = struct {
    tag: []const u8,
    value: *Values,
};

pub const Values = union(ValueTypes) {
    Boolean: bool,
    String: []const u8,
    BigInt: []const u8,
    List: std.ArrayList(Values),
    Tuple: std.ArrayList(Values),
    Set: std.ArrayList(Values),
    Map: std.ArrayList(MapEntry),
    Record: std.StringHashMap(Values),
    Variant: VariantType,
    Unserializable: []const u8,

    pub fn deinit(self: *Values, gpa: std.mem.Allocator) void {
        switch (self.*) {
            .List, .Tuple, .Set => |*ar| {
                for (ar.items) |*value| {
                    value.deinit(gpa);
                }
                ar.deinit(gpa);
            },

            .Record => |*ar| {
                var it = ar.iterator();
                while (it.next()) |*entry| {
                    gpa.free(entry.key_ptr.*);
                    entry.value_ptr.deinit(gpa);
                }
                ar.deinit();
            },

            .BigInt, .String => |it| {
                gpa.free(it);
            },

            .Map => |*mp| {
                for (mp.items) |entry| {
                    entry.key.deinit(gpa);
                    gpa.destroy(entry.key);
                    entry.value.deinit(gpa);
                    gpa.destroy(entry.value);
                }
                mp.deinit(gpa);
            },

            .Variant => |*vr| {
                gpa.free(vr.tag);
                vr.value.deinit(gpa);
                gpa.destroy(vr.value);
            },

            else => return,
        }
    }
};

pub const MapEntry = struct {
    key: *Values,
    value: *Values,
};

pub const Parser = struct {
    const Self = @This();
    const ParsedTrace = std.json.Parsed(ItfTrace);

    pub fn parseState(gpa: std.mem.Allocator, value: std.json.Value) !State {
        const variables = std.StringHashMap(Values).init(gpa);
        var state_obj = value.object;

        var s = State{
            .variables = variables,
            .index = 0,
        };

        var state_iter = state_obj.iterator();

        // std.debug.print("-----\n", .{});

        while (state_iter.next()) |entry| {
            // std.debug.print("state iter: {s}\n", .{entry.key_ptr.*});

            if (std.mem.eql(u8, entry.key_ptr.*, "#meta")) {
                s.index = @intCast(entry.value_ptr.object.get("index").?.integer);
                continue;
            }

            const v = try Parser.parseValue(gpa, entry.value_ptr.*);
            try s.variables.put(try gpa.dupe(u8, entry.key_ptr.*), v);
        }

        return s;
    }

    fn parseValue(gpa: std.mem.Allocator, value: std.json.Value) !Values {
        var vo: Values = undefined;

        switch (value) {
            .bool => {
                vo = Values{ .Boolean = value.bool };
            },
            .integer => {
                vo = Values{ .BigInt = try std.fmt.allocPrint(gpa, "{d}", .{value.integer}) };
            },
            .number_string => {
                vo = Values{ .BigInt = try gpa.dupe(u8, value.number_string) };
            },
            .string => {
                vo = Values{ .String = try gpa.dupe(u8, value.string) };
            },
            .array => |*ar| {
                var list = try std.ArrayList(Values).initCapacity(gpa, ar.items.len);
                for (ar.items) |it| {
                    try list.append(gpa, try Parser.parseValue(gpa, it));
                }

                vo = Values{ .List = list };
            },
            .object => |obj| {
                for (obj.keys()) |k| {
                    const v = obj.get(k) orelse continue;

                    if (std.mem.eql(u8, k, "#bigint")) {
                        return Values{ .BigInt = try gpa.dupe(u8, v.string) };
                    }

                    if (std.mem.eql(u8, k, "#tup")) {
                        var tup = try std.ArrayList(Values).initCapacity(gpa, v.array.items.len);
                        for (v.array.items) |it| {
                            try tup.append(gpa, try Parser.parseValue(gpa, it));
                        }

                        return Values{ .Tuple = tup };
                    }

                    if (std.mem.eql(u8, k, "#set")) {
                        var set = try std.ArrayList(Values).initCapacity(gpa, v.array.items.len);
                        for (v.array.items) |it| {
                            try set.append(gpa, try Parser.parseValue(gpa, it));
                        }

                        return Values{ .Set = set };
                    }

                    if (std.mem.eql(u8, k, "#map")) {
                        var map = try std.ArrayList(MapEntry).initCapacity(gpa, v.array.items.len);
                        for (v.array.items) |twoElArray| {
                            const el_key = try gpa.create(Values);
                            const el_value = try gpa.create(Values);
                            el_key.* = try Parser.parseValue(gpa, twoElArray.array.items[0]);
                            el_value.* = try Parser.parseValue(gpa, twoElArray.array.items[1]);
                            try map.append(gpa, MapEntry{
                                .key = el_key,
                                .value = el_value,
                            });
                        }

                        return Values{
                            .Map = map,
                        };
                    }

                    if (obj.count() == 2) {
                        const tag = obj.get("tag");
                        const vl = obj.get("value");
                        if (tag != null and vl != null) {
                            const inner = try gpa.create(Values);
                            inner.* = try Parser.parseValue(gpa, vl orelse unreachable);

                            return Values{
                                .Variant = VariantType{
                                    .tag = try gpa.dupe(u8, tag.?.string),
                                    .value = inner,
                                },
                            };
                        }
                    }

                    // else it is a record
                    if (std.meta.activeTag(vo) == .Record) {
                        try vo.Record.put(try gpa.dupe(u8, k), try Parser.parseValue(gpa, obj.get(k) orelse unreachable));
                    } else {
                        var record = std.StringHashMap(Values).init(gpa);
                        try record.put(try gpa.dupe(u8, k), try Parser.parseValue(gpa, obj.get(k) orelse unreachable));
                        vo = Values{ .Record = record };
                    }
                }
            },

            else => {
                vo = Values{ .Unserializable = try std.fmt.allocPrint(gpa, "encountered unknown value: {any}", .{value}) };
            },
        }

        return vo;
    }

    pub fn parse(gpa: std.mem.Allocator, filepath: []const u8) !ParsedTrace {
        const f = try std.fs.cwd().openFile(filepath, .{ .mode = .read_only });
        defer f.close();

        const content = try f.readToEndAlloc(gpa, std.math.maxInt(usize));
        defer gpa.free(content);

        const parsed = try std.json.parseFromSlice(ItfTrace, gpa, content, .{ .allocate = .alloc_always });

        return parsed;
    }
};
