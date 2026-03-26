/// Provides helpers for converting to native State type
/// from the driver's state and the spec's state generally
/// used for cross-checking spec and impl states when running
/// traces against an implementation
///
/// Spec (JSON/ quizz.State) ──→ [Intermediate State] ←── Driver (Memory, Your representation)
///                                      ↓
///                                   Compare
const quizz = @import("root.zig");
const std = @import("std");

// from_spec converts a spec's state i.e. `state` into an intermediate state represented as
// `InterState`. It is advised to have field names equivalent to the ones you write in your
// spec.qnt file.
// NOTE: We only care about the state of a spec not other things such as pure vals, defs or actions
// the goal here is to have state equality when the implementations are divergent/ different languages
// i.e. quint and zig/ quint and rust but the FSM is intact and always results in correct state transitions
// while maintaining invariants at each step/ state
pub fn from_spec(
    gpa: std.mem.Allocator,
    comptime InterState: type,
    step_state: quizz.Values,
    state_suffix: ?[]const u8,
) !InterState {
    const state_info = @typeInfo(InterState);
    var spec_state: InterState = undefined;

    inline for (state_info.@"struct".fields) |field| {
        if (field.type == std.mem.Allocator) {
            @field(spec_state, field.name) = gpa;
            continue;
        }

        const field_key = if (state_suffix) |suffix|
            try std.fmt.allocPrint(gpa, "{s}::{s}", .{ suffix, field.name })
        else
            field.name;

        const vari = step_state.Record.get(field_key) orelse return error.MissingFieldValue;
        @field(spec_state, field.name) = try convertValue(gpa, field.type, vari);
    }

    return spec_state;
}

test "from_spec" {
    const gpa = std.testing.allocator;

    const Role = enum { Follower, Candidate, Leader };

    const RaftState = struct {
        term: i64,
        active: bool,
        name: []const u8,
        role: Role,
        votedFor: ?[]const u8,
        currentTerm: std.StringHashMap(i64),
    };

    var variables = std.StringHashMap(quizz.Values).init(gpa);
    defer variables.deinit();

    try variables.put("term", quizz.Values{ .BigInt = "5" });
    try variables.put("active", quizz.Values{ .Boolean = true });
    try variables.put("name", quizz.Values{ .String = "node1" });

    const role_inner = try gpa.create(quizz.Values);
    defer gpa.destroy(role_inner);
    role_inner.* = quizz.Values{ .Tuple = .{} };
    try variables.put("role", quizz.Values{
        .Variant = quizz.VariantType{ .tag = "Leader", .value = role_inner },
    });

    const voted_inner = try gpa.create(quizz.Values);
    defer gpa.destroy(voted_inner);
    voted_inner.* = quizz.Values{ .String = "node2" };
    try variables.put("votedFor", quizz.Values{
        .Variant = quizz.VariantType{ .tag = "Some", .value = voted_inner },
    });

    var term_record = std.StringHashMap(quizz.Values).init(gpa);
    defer term_record.deinit();
    try term_record.put("n1", quizz.Values{ .BigInt = "1" });
    try term_record.put("n2", quizz.Values{ .BigInt = "2" });
    try variables.put("currentTerm", quizz.Values{ .Record = term_record });

    const state = quizz.Values{ .Record = variables };

    var result = try from_spec(gpa, RaftState, state, null);
    defer deinitOwnedStringHashMap(gpa, &result.currentTerm);

    try std.testing.expectEqual(@as(i64, 5), result.term);
    try std.testing.expect(result.active == true);
    try std.testing.expectEqualStrings("node1", result.name);
    try std.testing.expectEqual(Role.Leader, result.role);
    try std.testing.expectEqualStrings("node2", result.votedFor.?);
    try std.testing.expectEqual(@as(i64, 1), result.currentTerm.get("n1").?);
    try std.testing.expectEqual(@as(i64, 2), result.currentTerm.get("n2").?);
}

// converts `value` to field_type
pub fn convertValue(gpa: std.mem.Allocator, comptime field_type: type, value: quizz.Values) !field_type {
    const t = @typeInfo(field_type);

    switch (t) {
        .int => {
            return switch (value) {
                .BigInt => |s| try std.fmt.parseInt(field_type, s, 10),
                else => return error.ValueTypeMismatch,
            };
        },
        .pointer => {
            return switch (value) {
                .String => |s| s,
                else => return error.ValueTypeMismatch,
            };
        },
        .bool => {
            return switch (value) {
                .Boolean => |b| b,
                else => error.ValueTypeMismatch,
            };
        },
        .@"enum" => {
            return switch (value) {
                .Variant => |v| std.meta.stringToEnum(field_type, v.tag) orelse error.UnknownVariant,
                .String => |s| std.meta.stringToEnum(field_type, s) orelse error.UnknownVariant,
                else => error.ValueTypeMismatch,
            };
        },
        .optional => |opt| {
            return switch (value) {
                .Variant => |v| {
                    if (std.mem.eql(u8, v.tag, "None")) return null;
                    if (std.mem.eql(u8, v.tag, "Some")) {
                        return try convertValue(gpa, opt.child, v.value.*);
                    }
                    return error.InvalidOptionVariant;
                },
                else => error.ValueTypeMismatch,
            };
        },
        .@"struct" => |_| {
            // this is a hashmap
            if (@hasDecl(field_type, "KV")) {
                return try convertHashMap(gpa, field_type, value);
            }

            if (@hasField(field_type, "items")) {
                return try convertArrayList(gpa, field_type, value);
            }

            return try convertStruct(gpa, field_type, value);
        },

        else => unreachable,
    }
}

fn convertHashMap(gpa: std.mem.Allocator, comptime MapType: type, value: quizz.Values) !MapType {
    const key_type, const value_type = comptime hashMapTypes(MapType);
    var cp_hm = MapType.init(gpa);

    switch (value) {
        .Record => |r| {
            var it = r.iterator();
            while (it.next()) |entry| {
                try cp_hm.put(
                    try convertMapKey(gpa, key_type, quizz.Values{ .String = entry.key_ptr.* }),
                    try convertValue(gpa, value_type, entry.value_ptr.*),
                );
            }
        },
        .Map => |entries| {
            for (entries.items) |entry| {
                try cp_hm.put(
                    try convertMapKey(gpa, key_type, entry.key.*),
                    try convertValue(gpa, value_type, entry.value.*),
                );
            }
        },
        .Set => |set_values| {
            if (value_type != void) return error.ValueTypeMismatch;
            for (set_values.items) |entry| {
                try cp_hm.put(try convertMapKey(gpa, key_type, entry), {});
            }
        },
        else => return error.ValueTypeMismatch,
    }

    return cp_hm;
}

fn convertArrayList(gpa: std.mem.Allocator, comptime ListType: type, value: quizz.Values) !ListType {
    const Child = std.meta.Elem(@TypeOf(ListType.empty.items));
    var list: ListType = .empty;

    switch (value) {
        .List => |items| {
            for (items.items) |item| {
                try list.append(gpa, try convertValue(gpa, Child, item));
            }
        },
        .Tuple => |items| {
            for (items.items) |item| {
                try list.append(gpa, try convertValue(gpa, Child, item));
            }
        },
        .Set => |items| {
            for (items.items) |item| {
                try list.append(gpa, try convertValue(gpa, Child, item));
            }
        },
        else => return error.ValueTypeMismatch,
    }

    return list;
}

fn convertStruct(gpa: std.mem.Allocator, comptime StructType: type, value: quizz.Values) !StructType {
    const record = switch (value) {
        .Record => |r| r,
        else => return error.ValueTypeMismatch,
    };

    var converted: StructType = undefined;
    inline for (@typeInfo(StructType).@"struct".fields) |field| {
        if (field.type == std.mem.Allocator) {
            @field(converted, field.name) = gpa;
            continue;
        }

        const field_value = record.get(field.name) orelse return error.MissingFieldValue;
        @field(converted, field.name) = try convertValue(gpa, field.type, field_value);
    }

    return converted;
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
        key_type orelse @compileError("no key found in a hashmap container"),
        value_type orelse @compileError("no value found in a hashmap container"),
    };
}

fn convertMapKey(gpa: std.mem.Allocator, comptime KeyType: type, value: quizz.Values) !KeyType {
    const key = try convertValue(gpa, KeyType, value);
    if (KeyType == []const u8) return try gpa.dupe(u8, key);
    return key;
}

fn deinitOwnedStringHashMap(gpa: std.mem.Allocator, map: anytype) void {
    var it = map.iterator();
    while (it.next()) |entry| {
        gpa.free(entry.key_ptr.*);
    }
    map.deinit();
}

test "convertValue int from BigInt" {
    const gpa = std.testing.allocator;
    const value = quizz.Values{ .BigInt = "42" };

    const result = try convertValue(gpa, i64, value);
    try std.testing.expectEqual(@as(i64, 42), result);
}

test "convertValue StringHashMap" {
    const gpa = std.testing.allocator;

    var rec = std.StringHashMap(quizz.Values).init(gpa);
    defer rec.deinit();
    try rec.put("a", quizz.Values{ .BigInt = "1" });
    try rec.put("b", quizz.Values{ .BigInt = "2" });

    const value = quizz.Values{ .Record = rec };

    var result = try convertValue(gpa, std.StringHashMap(i64), value);
    defer deinitOwnedStringHashMap(gpa, &result);

    try std.testing.expectEqual(@as(i64, 1), result.get("a").?);
    try std.testing.expectEqual(@as(i64, 2), result.get("b").?);
}

test "convertValue bool" {
    const gpa = std.testing.allocator;

    const true_val = quizz.Values{ .Boolean = true };
    const false_val = quizz.Values{ .Boolean = false };

    try std.testing.expect(try convertValue(gpa, bool, true_val) == true);
    try std.testing.expect(try convertValue(gpa, bool, false_val) == false);
}

test "convertValue string" {
    const gpa = std.testing.allocator;
    const value = quizz.Values{ .String = "hello" };

    const result = try convertValue(gpa, []const u8, value);
    try std.testing.expectEqualStrings("hello", result);
}

test "convertValue enum from Variant" {
    const gpa = std.testing.allocator;

    const Status = enum { Active, Pending, Inactive };

    const inner = try gpa.create(quizz.Values);
    defer gpa.destroy(inner);
    inner.* = quizz.Values{ .Tuple = .{} };

    const value = quizz.Values{
        .Variant = quizz.VariantType{
            .tag = "Pending",
            .value = inner,
        },
    };

    const result = try convertValue(gpa, Status, value);
    try std.testing.expectEqual(Status.Pending, result);
}

test "convertValue optional Some" {
    const gpa = std.testing.allocator;

    const inner = try gpa.create(quizz.Values);
    defer gpa.destroy(inner);
    inner.* = quizz.Values{ .BigInt = "123" };

    const value = quizz.Values{
        .Variant = quizz.VariantType{
            .tag = "Some",
            .value = inner,
        },
    };

    const result = try convertValue(gpa, ?i64, value);
    try std.testing.expectEqual(@as(?i64, 123), result);
}

test "convertValue optional None" {
    const gpa = std.testing.allocator;

    const inner = try gpa.create(quizz.Values);
    defer gpa.destroy(inner);
    inner.* = quizz.Values{ .Tuple = .{} };

    const value = quizz.Values{
        .Variant = quizz.VariantType{
            .tag = "None",
            .value = inner,
        },
    };

    const result = try convertValue(gpa, ?i64, value);
    try std.testing.expectEqual(@as(?i64, null), result);
}
