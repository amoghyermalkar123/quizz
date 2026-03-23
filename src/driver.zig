const st = @import("state.zig");
const std = @import("std");
const quizz = @import("root.zig");
const State = quizz.State;
const Values = quizz.Values;
const ValueTypes = quizz.ValueTypes;

// A step is an object in an array of state.
// logically array of states are just states in transition
// so each object in said array is a step and the next step
// is what the current step will transition to which in state machine
// terminoloy is a state transition
pub const Step = struct {
    action_taken: []const u8, // Action name from spec
    nondet_picks: Values, // Nondeterministic choices (Record)
    state: Values, // Expected state after step

    // state should be a record
    pub fn from(allocator: std.mem.Allocator, state: State) !Step {
        const action = state.variables.get("mbt::actionTaken") orelse
            return error.MissingAction;

        const nondet = state.variables.get("mbt::nondetPicks") orelse
            Values{ .Record = std.StringHashMap(Values).init(allocator) };

        return Step{
            .action_taken = switch (action) {
                .String => |s| s,
                else => return error.InvalidActionType,
            },
            .nondet_picks = nondet,
            .state = Values{ .Record = state.variables },
        };
    }
};

pub fn case(comptime arg_names: anytype, comptime handler: anytype) struct {
    arg_names: @TypeOf(arg_names),
    handler: @TypeOf(handler),
} {
    const Handler = @TypeOf(handler);
    const fn_info = switch (@typeInfo(Handler)) {
        .@"fn" => |info| info,
        else => @compileError("quizz.case handler must be a function"),
    };

    comptime {
        if (fn_info.params.len == 0) {
            @compileError("quizz.case handler must take self as its first parameter");
        }

        if (fn_info.params.len - 1 != arg_names.len) {
            @compileError(std.fmt.comptimePrint(
                "quizz.case expected {d} action args but handler takes {d}",
                .{ arg_names.len, fn_info.params.len - 1 },
            ));
        }
    }

    return .{
        .arg_names = arg_names,
        .handler = handler,
    };
}

pub fn dispatch(gpa: std.mem.Allocator, self: anytype, step: Step, comptime cases: anytype) !void {
    inline for (@typeInfo(@TypeOf(cases)).@"struct".fields) |field| {
        if (std.mem.eql(u8, step.action_taken, field.name)) {
            return invokeCase(gpa, self, step.nondet_picks, @field(cases, field.name));
        }
    }

    return error.UnknownAction;
}

fn invokeCase(gpa: std.mem.Allocator, self: anytype, args_value: Values, comptime selected: anytype) !void {
    const handler = selected.handler;
    const Handler = @TypeOf(handler);
    const fn_info = @typeInfo(Handler).@"fn";

    var call_args: std.meta.ArgsTuple(Handler) = undefined;
    call_args[0] = self;

    inline for (selected.arg_names, 0..) |arg_name, i| {
        const param = fn_info.params[i + 1];
        const ParamType = param.type orelse
            @compileError("quizz.case handler parameters must have concrete types");

        const raw = try getNamedArg(args_value, arg_name);
        call_args[i + 1] = try decodeValue(gpa, ParamType, raw);
    }

    return @call(.auto, handler, call_args);
}

fn getNamedArg(args_value: Values, comptime name: []const u8) !Values {
    return switch (args_value) {
        .Record => |record| record.get(name) orelse error.MissingActionArgument,
        else => error.ExpectedRecordActionArgs,
    };
}

pub fn decodeValue(
    gpa: std.mem.Allocator,
    comptime T: type,
    value: Values,
) !T {
    return st.convertValue(gpa, T, value);
}

test "Step.from extracts action, nondet picks, and state record" {
    const gpa = std.testing.allocator;

    var nondet = std.StringHashMap(Values).init(gpa);
    defer nondet.deinit();
    try nondet.put("candidate", Values{ .String = "n2" });

    var variables = std.StringHashMap(Values).init(gpa);
    defer variables.deinit();
    try variables.put("mbt::actionTaken", Values{ .String = "becomeCandidate" });
    try variables.put("mbt::nondetPicks", Values{ .Record = nondet });
    try variables.put("term", Values{ .BigInt = "1" });

    const state = State{
        .index = 1,
        .variables = variables,
    };

    const step = try Step.from(gpa, state);

    try std.testing.expectEqualStrings("becomeCandidate", step.action_taken);
    try std.testing.expectEqual(ValueTypes.Record, std.meta.activeTag(step.nondet_picks));
    try std.testing.expectEqualStrings("n2", step.nondet_picks.Record.get("candidate").?.String);
    try std.testing.expectEqual(ValueTypes.Record, std.meta.activeTag(step.state));
    try std.testing.expectEqualStrings("1", step.state.Record.get("term").?.BigInt);
}

test "dispatch decodes named arguments and calls matching handler" {
    const gpa = std.testing.allocator;

    const Recorder = struct {
        seen: ?[]const u8 = null,

        fn handle(self: *@This(), candidate: []const u8) !void {
            self.seen = candidate;
        }
    };

    var recorder = Recorder{};

    var nondet = std.StringHashMap(Values).init(gpa);
    defer nondet.deinit();
    try nondet.put("candidate", Values{ .String = "n3" });

    var state_record = std.StringHashMap(Values).init(gpa);
    defer state_record.deinit();

    const step = Step{
        .action_taken = "becomeCandidate",
        .nondet_picks = Values{ .Record = nondet },
        .state = Values{ .Record = state_record },
    };

    try dispatch(gpa, &recorder, step, .{
        .becomeCandidate = case(.{"candidate"}, Recorder.handle),
    });

    try std.testing.expectEqualStrings("n3", recorder.seen.?);
}
