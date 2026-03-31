// runs the itf traces against the provided driver
const quizz = @import("root.zig");
const driver_mod = @import("driver.zig");
const quizz_json = @import("json.zig");
const std = @import("std");
const state = @import("state.zig");

pub fn run_test(gpa: std.mem.Allocator, driver: anytype, spec_path: []const u8, state_suffix: ?[]const u8) !void {
    const abs_spec_path = try std.fs.realpathAlloc(gpa, spec_path);
    defer gpa.free(abs_spec_path);

    const tmp_root = "tmp";
    try std.fs.cwd().makePath(tmp_root);

    const tmp_dir_name = try std.fmt.allocPrint(gpa, "{s}/quizz-{d}", .{ tmp_root, std.time.microTimestamp() });
    defer gpa.free(tmp_dir_name);
    try std.fs.cwd().makeDir(tmp_dir_name);
    defer std.fs.cwd().deleteTree(tmp_dir_name) catch {};

    const out_prefix = try std.fmt.allocPrint(gpa, "{s}/trace.itf.json", .{tmp_dir_name});
    defer gpa.free(out_prefix);

    try generate_traces(gpa, abs_spec_path, out_prefix);

    var traces = std.ArrayList(quizz.Trace).empty;
    defer {
        for (traces.items) |*trace| {
            deinitTrace(gpa, trace);
        }
        traces.deinit(gpa);
    }

    try load_traces(gpa, tmp_dir_name, &traces);

    if (traces.items.len == 0) return error.NoTracesGenerated;
    try replay_traces(gpa, driver, traces.items, state_suffix);
}

pub fn replay_traces(gpa: std.mem.Allocator, driver: anytype, traces: []quizz.Trace, state_suffix: ?[]const u8) !void {
    const Driver = switch (@typeInfo(@TypeOf(driver))) {
        .pointer => |ptr| ptr.child,
        else => @TypeOf(driver),
    };

    const StepReport = struct {
        state_index: usize,
        action: []const u8,
        matched: bool,
        spec_state_json: []const u8,
        driver_state_json: []const u8,

        pub fn jsonStringify(self: @This(), jws: anytype) !void {
            try jws.beginObject();

            try jws.objectField("state_index");
            try jws.write(self.state_index);

            try jws.objectField("action");
            try jws.write(self.action);

            try jws.objectField("matched");
            try jws.write(self.matched);

            try jws.objectField("spec_state");
            try jws.beginWriteRaw();
            try jws.writer.writeAll(self.spec_state_json);
            jws.endWriteRaw();

            try jws.objectField("driver_state");
            try jws.beginWriteRaw();
            try jws.writer.writeAll(self.driver_state_json);
            jws.endWriteRaw();

            try jws.endObject();
        }
    };

    var report = std.StringHashMap(std.ArrayList(StepReport)).init(gpa);
    defer {
        var trace_it = report.iterator();
        while (trace_it.next()) |entry| {
            gpa.free(entry.key_ptr.*);
            for (entry.value_ptr.items) |step_report| {
                gpa.free(step_report.action);
                gpa.free(step_report.spec_state_json);
                gpa.free(step_report.driver_state_json);
            }
            entry.value_ptr.deinit(gpa);
        }
        report.deinit();
    }

    for (traces, 0..) |trace, trace_idx| {
        const trace_key = try std.fmt.allocPrint(gpa, "trace_{d}", .{trace_idx});
        // commented this because this causes double free: errdefer gpa.free(trace_key);

        const gop = try report.getOrPut(trace_key);
        if (!gop.found_existing) {
            gop.value_ptr.* = .empty;
        } else {
            gpa.free(trace_key);
        }

        for (trace.states.items) |trace_state| {
            const step = try driver_mod.Step.from(gpa, trace_state);

            try driver.step(step);

            var arena = std.heap.ArenaAllocator.init(gpa);
            defer arena.deinit();

            const scratch = arena.allocator();
            const spec_state = try state.from_spec(scratch, Driver.State, step.state, state_suffix);
            const driver_state = try driver.from_driver(scratch);
            const matched = @import("eql.zig").eqlValue(Driver.State, spec_state, driver_state);

            const report_entry = StepReport{
                .state_index = trace_state.index,
                .action = try gpa.dupe(u8, step.action_taken),
                .matched = matched,
                .spec_state_json = try quizz_json.valueAlloc(gpa, spec_state, .{}),
                .driver_state_json = try quizz_json.valueAlloc(gpa, driver_state, .{}),
            };
            try gop.value_ptr.append(gpa, report_entry);

            // TODO: if we do this entirely at comptime we can do @compileError
            // meaning your entire spec will be checked as part of compiling the
            // program itself.
            //
            // comptime formal verification
            //
            // for now it runs on runtime and returns an error
            if (matched) continue else {
                try writeReplayReport(gpa, report);
                std.debug.print("trace failed, states don't match\n", .{});
                // TODO: print artifact location
                return error.TraceFailed;
            }

            continue;
        }
    }

    try writeReplayReport(gpa, report);

    return;
}

fn writeReplayReport(gpa: std.mem.Allocator, report: anytype) !void {
    const json_report = try quizz_json.valueAlloc(gpa, report, .{ .whitespace = .indent_2 });
    defer gpa.free(json_report);

    try std.fs.cwd().writeFile(.{
        .sub_path = "quizz_run.json",
        .data = json_report,
    });
}

fn generate_traces(gpa: std.mem.Allocator, spec_path: []const u8, out_prefix: []const u8) !void {
    const main_module = try deriveMainModuleName(gpa, spec_path);
    defer gpa.free(main_module);

    const out_arg = try std.fmt.allocPrint(gpa, "--out-itf={s}", .{out_prefix});
    defer gpa.free(out_arg);

    const result = try std.process.Child.run(.{
        .allocator = gpa,
        .argv = &.{
            "quint",
            "run",
            spec_path,
            "--main",
            main_module,
            "--mbt",
            "--n-traces=16",
            out_arg,
        },
        .max_output_bytes = 1024 * 1024,
    });
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print(
                    "quint run failed with exit code {d}\nstdout:\n{s}\nstderr:\n{s}\n",
                    .{ code, result.stdout, result.stderr },
                );
                return error.QuintRunFailed;
            }
        },
        else => return error.QuintRunFailed,
    }
}

fn deriveMainModuleName(gpa: std.mem.Allocator, spec_path: []const u8) ![]u8 {
    const stem = std.fs.path.stem(spec_path);
    if (std.mem.endsWith(u8, stem, "_test")) return try gpa.dupe(u8, stem);
    return try std.fmt.allocPrint(gpa, "{s}_test", .{stem});
}

fn load_traces(gpa: std.mem.Allocator, trace_dir_path: []const u8, traces: *std.ArrayList(quizz.Trace)) !void {
    var trace_dir = try std.fs.cwd().openDir(trace_dir_path, .{ .iterate = true });
    defer trace_dir.close();

    var filenames = std.ArrayList([]u8).empty;
    defer {
        for (filenames.items) |name| gpa.free(name);
        filenames.deinit(gpa);
    }

    var it = trace_dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".itf.json")) continue;
        try filenames.append(gpa, try gpa.dupe(u8, entry.name));
    }

    std.sort.pdq([]u8, filenames.items, {}, struct {
        fn lessThan(_: void, lhs: []u8, rhs: []u8) bool {
            return std.mem.lessThan(u8, lhs, rhs);
        }
    }.lessThan);

    for (filenames.items) |filename| {
        const full_path = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ trace_dir_path, filename });
        defer gpa.free(full_path);
        try traces.append(gpa, try parse_trace_file(gpa, full_path));
    }
}

fn parse_trace_file(gpa: std.mem.Allocator, filepath: []const u8) !quizz.Trace {
    const parsed = try quizz.Parser.parse(gpa, filepath);
    defer parsed.deinit();

    var trace = quizz.Trace{
        .meta = null,
        .vars = null,
        .states = .empty,
        .loop_index = parsed.value.loop_index,
    };

    for (parsed.value.states) |json_state| {
        try trace.states.append(gpa, try quizz.Parser.parseState(gpa, json_state));
    }

    return trace;
}

fn deinitTrace(gpa: std.mem.Allocator, trace: *quizz.Trace) void {
    for (trace.states.items) |*step_state| {
        step_state.deinit(gpa);
    }
    trace.states.deinit(gpa);
}
