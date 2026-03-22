// runs the itf traces against the provided driver

const quizz = @import("root.zig");
const state = @import("state.zig");
const std = @import("std");

pub fn run_test(comptime driver: type) !void {
    // TODO: use quint generate trace files, parse and generate traces
    const traces = [_]quizz.Trace{};
    try replay_traces(driver, traces);
}

pub fn replay_traces(gpa: std.mem.Allocator, comptime driver: type, traces: []quizz.Trace) !void {
    for (traces) |trace| {
        for (trace.states) |trace_state| {
            const step = try quizz.Step.from(trace_state);

            driver.step(step);

            // TODO: if we do this entirely at comptime we can do @compileError
            // meaning your entire spec will be checked as part of compiling the
            // program itself.
            //
            // comptime formal verification
            //
            // for now it returns an error
            if (check_state(gpa, driver, step)) continue else {
                std.debug.print("trace failed, states don't match", .{});
                return error.TraceFailed;
            }
        }
    }

    return;
}

pub fn check_state(gpa: std.mem.Allocator, comptime driver: type, step: quizz.Step) !bool {
    const IntermediateType = driver.State;

    var spec_state = try state.from_spec(gpa, IntermediateType, step.state);
    var driver_state = try driver.from_driver(gpa, IntermediateType, step.state);

    // TODO: check for equality and return true/ false
    return true;
}
