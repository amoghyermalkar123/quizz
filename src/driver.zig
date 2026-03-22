const st = @import("state.zig");
const Values = @import("quizz").Values;
const ValueTypes = @import("quizz").ValueTypes;
const std = @import("std");

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
    pub fn from(allocator: std.mem.Allocator, state: Values) !Step {
        if (std.meta.activeTag(state) != ValueTypes.Record) return error.ExpectedRecordValue;

        const action = state.Record.get("mbt::actionTaken") orelse
            return error.MissingAction;

        const nondet = state.Record.get("mbt::nondetPicks") orelse
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

// The driver interface which is passed to the quizz runner
// the developer implements the actual step function and then
// wraps that type in DriverType to satify the interface
// TODO: driver design is not final yet
pub fn DriverType(comptime Impl: type) type {
    return struct {
        const Self = @This();

        comptime {
            if (!@hasDecl(Impl, "step")) @compileError("the type must implement the step function");
        }

        impl: *Impl,

        pub fn step(self: Self, stp: Step) !void {
            return Impl.step(self.impl, stp);
        }
    };
}

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
    inline for (@typeInfo(cases).@"struct".fields) |field| {
        if (!std.mem.eql(u8, step.action_taken, field.name)) continue;

        return invokeCase(gpa, self, step.args, @field(cases, field.name));
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
