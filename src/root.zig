const std = @import("std");

// native type for an ItfTrace
pub const Trace = struct {
    meta: ?TraceMetadata = null,
    vars: ?[]const []const u8 = null,
    states: std.ArrayList(State),
    loop_index: ?usize = null,
};

pub const ItfTrace = struct {
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
            try s.variables.put(entry.key_ptr.*, v);
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

                    // TODO: set, map, etc

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
                        try vo.Record.put(k, try Parser.parseValue(gpa, obj.get(k) orelse unreachable));
                    } else {
                        var record = std.StringHashMap(Values).init(gpa);
                        try record.put(k, try Parser.parseValue(gpa, obj.get(k) orelse unreachable));
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

test "parse comprehensive_trace.itf.json" {
    const gpa = std.testing.allocator;

    const parsed = try Parser.parse(gpa, "/Users/amoghyermalkar/projects/quizz/comprehensive_trace.itf.json");
    defer parsed.deinit();

    var itf = Trace{
        .states = .{},
    };
    defer {
        for (itf.states.items) |*state| {
            state.deinit(gpa);
        }
        itf.states.deinit(gpa);
    }

    for (parsed.value.states) |state| {
        const st = try Parser.parseState(gpa, state);
        try itf.states.append(gpa, st);
    }

    // Verify state count
    try std.testing.expectEqual(@as(usize, 6), itf.states.items.len);

    // State 0: verify index, all variable types
    const state0 = itf.states.items[0];
    try std.testing.expectEqual(@as(usize, 0), state0.index);
    try std.testing.expectEqual(@as(usize, 6), state0.variables.count());
    try std.testing.expectEqualStrings("0", state0.variables.get("counter").?.BigInt);
    try std.testing.expect(state0.variables.get("flag").?.Boolean == true);
    try std.testing.expectEqualStrings("initial", state0.variables.get("label").?.String);
    try std.testing.expectEqualStrings("init", state0.variables.get("mbt::actionTaken").?.String);

    // Verify Variant: status = { tag: "Active", value: { #tup: [] } }
    const status0 = state0.variables.get("status").?;
    try std.testing.expectEqual(ValueTypes.Variant, std.meta.activeTag(status0));
    try std.testing.expectEqualStrings("Active", status0.Variant.tag);
    try std.testing.expectEqual(ValueTypes.Tuple, std.meta.activeTag(status0.Variant.value.*));
    try std.testing.expectEqual(@as(usize, 0), status0.Variant.value.Tuple.items.len);

    // Verify nested Record: mbt::nondetPicks contains delta and newStatus
    const nondetPicks0 = state0.variables.get("mbt::nondetPicks").?;
    try std.testing.expectEqual(ValueTypes.Record, std.meta.activeTag(nondetPicks0));
    const delta0 = nondetPicks0.Record.get("delta").?;
    try std.testing.expectEqual(ValueTypes.Variant, std.meta.activeTag(delta0));
    try std.testing.expectEqualStrings("None", delta0.Variant.tag);

    // State 1: verify flag toggled
    const state1 = itf.states.items[1];
    try std.testing.expectEqual(@as(usize, 1), state1.index);
    try std.testing.expect(state1.variables.get("flag").?.Boolean == false);
    try std.testing.expectEqualStrings("toggled", state1.variables.get("label").?.String);
    try std.testing.expectEqualStrings("toggleFlag", state1.variables.get("mbt::actionTaken").?.String);

    // State 2: verify counter updated
    const state2 = itf.states.items[2];
    try std.testing.expectEqual(@as(usize, 2), state2.index);
    try std.testing.expectEqualStrings("100", state2.variables.get("counter").?.BigInt);
    try std.testing.expectEqualStrings("updateCounter", state2.variables.get("mbt::actionTaken").?.String);

    // Verify nested Variant in nondetPicks: delta = { tag: "Some", value: { #bigint: "100" } }
    const nondetPicks2 = state2.variables.get("mbt::nondetPicks").?;
    const delta2 = nondetPicks2.Record.get("delta").?;
    try std.testing.expectEqualStrings("Some", delta2.Variant.tag);
    try std.testing.expectEqual(ValueTypes.BigInt, std.meta.activeTag(delta2.Variant.value.*));
    try std.testing.expectEqualStrings("100", delta2.Variant.value.BigInt);

    // State 3: verify status changed to Pending
    const state3 = itf.states.items[3];
    try std.testing.expectEqual(@as(usize, 3), state3.index);
    try std.testing.expectEqualStrings("changeStatus", state3.variables.get("mbt::actionTaken").?.String);
    const status3 = state3.variables.get("status").?;
    try std.testing.expectEqualStrings("Pending", status3.Variant.tag);

    // Verify deeply nested Variant: newStatus = { tag: "Some", value: { tag: "Pending", value: { #tup: [] } } }
    const nondetPicks3 = state3.variables.get("mbt::nondetPicks").?;
    const newStatus3 = nondetPicks3.Record.get("newStatus").?;
    try std.testing.expectEqualStrings("Some", newStatus3.Variant.tag);
    try std.testing.expectEqual(ValueTypes.Variant, std.meta.activeTag(newStatus3.Variant.value.*));
    try std.testing.expectEqualStrings("Pending", newStatus3.Variant.value.Variant.tag);

    // State 5: verify final state
    const state5 = itf.states.items[5];
    try std.testing.expectEqual(@as(usize, 5), state5.index);
    const status5 = state5.variables.get("status").?;
    try std.testing.expectEqualStrings("Inactive", status5.Variant.tag);
}

test "parse two_phase_commit_trace.itf.json" {
    const gpa = std.testing.allocator;

    const parsed = try Parser.parse(gpa, "/Users/amoghyermalkar/projects/quizz/two_phase_commit_trace.itf.json");
    defer parsed.deinit();

    var itf = Trace{
        .states = .{},
    };
    defer {
        for (itf.states.items) |*state| {
            state.deinit(gpa);
        }
        itf.states.deinit(gpa);
    }

    for (parsed.value.states) |state| {
        const st = try Parser.parseState(gpa, state);
        try itf.states.append(gpa, st);
    }

    // Verify state count (9 states: 0-8)
    try std.testing.expectEqual(@as(usize, 9), itf.states.items.len);

    // State 0: Initial state - all processes Working
    const state0 = itf.states.items[0];
    try std.testing.expectEqual(@as(usize, 0), state0.index);

    const s0 = state0.variables.get("two_phase_commit::choreo::s").?;
    try std.testing.expectEqual(ValueTypes.Record, std.meta.activeTag(s0));

    // Verify extensions.actionTaken = { tag: "Init", value: { #tup: [] } }
    const extensions0 = s0.Record.get("extensions").?;
    try std.testing.expectEqual(ValueTypes.Record, std.meta.activeTag(extensions0));
    const actionTaken0 = extensions0.Record.get("actionTaken").?;
    try std.testing.expectEqual(ValueTypes.Variant, std.meta.activeTag(actionTaken0));
    try std.testing.expectEqualStrings("Init", actionTaken0.Variant.tag);
    try std.testing.expectEqual(ValueTypes.Tuple, std.meta.activeTag(actionTaken0.Variant.value.*));

    // Verify system map has 4 entries (c, p1, p2, p3)
    const system0 = s0.Record.get("system").?;
    try std.testing.expectEqual(ValueTypes.Map, std.meta.activeTag(system0));
    try std.testing.expectEqual(@as(usize, 4), system0.Map.items.len);

    // Find coordinator entry in system map and verify its structure
    var found_coordinator = false;
    for (system0.Map.items) |entry| {
        if (std.meta.activeTag(entry.key.*) == .String and
            std.mem.eql(u8, entry.key.String, "c"))
        {
            found_coordinator = true;
            const coord_record = entry.value.*;
            try std.testing.expectEqual(ValueTypes.Record, std.meta.activeTag(coord_record));

            const role = coord_record.Record.get("role").?;
            try std.testing.expectEqualStrings("Coordinator", role.Variant.tag);

            const stage = coord_record.Record.get("stage").?;
            try std.testing.expectEqualStrings("Working", stage.Variant.tag);
            break;
        }
    }
    try std.testing.expect(found_coordinator);

    // Verify events map has 4 entries with empty sets
    const events0 = s0.Record.get("events").?;
    try std.testing.expectEqual(ValueTypes.Map, std.meta.activeTag(events0));
    try std.testing.expectEqual(@as(usize, 4), events0.Map.items.len);

    // State 1: p1 spontaneously aborts
    const state1 = itf.states.items[1];
    try std.testing.expectEqual(@as(usize, 1), state1.index);

    const s1 = state1.variables.get("two_phase_commit::choreo::s").?;
    const extensions1 = s1.Record.get("extensions").?;
    const actionTaken1 = extensions1.Record.get("actionTaken").?;
    try std.testing.expectEqualStrings("SpontaneouslyAborts", actionTaken1.Variant.tag);

    // Verify actionTaken1.value is a record with node = "p1"
    const action_value1 = actionTaken1.Variant.value.*;
    try std.testing.expectEqual(ValueTypes.Record, std.meta.activeTag(action_value1));
    const node1 = action_value1.Record.get("node").?;
    try std.testing.expectEqualStrings("p1", node1.String);

    // Verify p1's stage changed to Aborted in state 1
    const system1 = s1.Record.get("system").?;
    for (system1.Map.items) |entry| {
        if (std.meta.activeTag(entry.key.*) == .String and
            std.mem.eql(u8, entry.key.String, "p1"))
        {
            const p1_record = entry.value.*;
            const stage = p1_record.Record.get("stage").?;
            try std.testing.expectEqualStrings("Aborted", stage.Variant.tag);
            break;
        }
    }

    // State 2: p3 prepares - verify messages contain ParticipantPrepared
    const state2 = itf.states.items[2];
    const s2 = state2.variables.get("two_phase_commit::choreo::s").?;
    const extensions2 = s2.Record.get("extensions").?;
    const actionTaken2 = extensions2.Record.get("actionTaken").?;
    try std.testing.expectEqualStrings("SpontaneouslyPrepares", actionTaken2.Variant.tag);

    // Verify messages map now has non-empty sets
    const messages2 = s2.Record.get("messages").?;
    try std.testing.expectEqual(ValueTypes.Map, std.meta.activeTag(messages2));
    for (messages2.Map.items) |entry| {
        const msg_set = entry.value.*;
        try std.testing.expectEqual(ValueTypes.Set, std.meta.activeTag(msg_set));
        // Each process should have received ParticipantPrepared message
        try std.testing.expectEqual(@as(usize, 1), msg_set.Set.items.len);
        const msg = msg_set.Set.items[0];
        try std.testing.expectEqual(ValueTypes.Variant, std.meta.activeTag(msg));
        try std.testing.expectEqualStrings("ParticipantPrepared", msg.Variant.tag);
    }

    // State 3: Coordinator decides to abort
    const state3 = itf.states.items[3];
    const s3 = state3.variables.get("two_phase_commit::choreo::s").?;
    const extensions3 = s3.Record.get("extensions").?;
    const actionTaken3 = extensions3.Record.get("actionTaken").?;
    try std.testing.expectEqualStrings("DecidesOnAbort", actionTaken3.Variant.tag);

    // Verify coordinator's stage changed to Aborted
    const system3 = s3.Record.get("system").?;
    for (system3.Map.items) |entry| {
        if (std.meta.activeTag(entry.key.*) == .String and
            std.mem.eql(u8, entry.key.String, "c"))
        {
            const coord_record = entry.value.*;
            const stage = coord_record.Record.get("stage").?;
            try std.testing.expectEqualStrings("Aborted", stage.Variant.tag);
            break;
        }
    }

    // State 8: Final state - verify all processes are Aborted
    const state8 = itf.states.items[8];
    try std.testing.expectEqual(@as(usize, 8), state8.index);

    const s8 = state8.variables.get("two_phase_commit::choreo::s").?;
    const system8 = s8.Record.get("system").?;

    var aborted_count: usize = 0;
    for (system8.Map.items) |entry| {
        const process_record = entry.value.*;
        const stage = process_record.Record.get("stage").?;
        if (std.mem.eql(u8, stage.Variant.tag, "Aborted")) {
            aborted_count += 1;
        }
    }
    // All 4 processes should be Aborted in final state
    try std.testing.expectEqual(@as(usize, 4), aborted_count);
}
