// runs the itf traces against the provided driver
const quizz = @import("root.zig");
const driver_mod = @import("driver.zig");
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
    for (traces) |trace| {
        for (trace.states.items) |trace_state| {
            const step = try driver_mod.Step.from(gpa, trace_state);

            try driver.step(step);

            // TODO: if we do this entirely at comptime we can do @compileError
            // meaning your entire spec will be checked as part of compiling the
            // program itself.
            //
            // comptime formal verification
            //
            // for now it runs on runtime and returns an error
            if (try check_state(gpa, driver, step, state_suffix)) continue else {
                std.debug.print("trace failed, states don't match", .{});
                return error.TraceFailed;
            }
        }
    }

    return;
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

pub fn check_state(gpa: std.mem.Allocator, driver: anytype, step: driver_mod.Step, state_suffix: ?[]const u8) !bool {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    const Driver = switch (@typeInfo(@TypeOf(driver))) {
        .pointer => |ptr| ptr.child,
        else => @TypeOf(driver),
    };

    const scratch = arena.allocator();
    const spec_state = try state.from_spec(scratch, Driver.State, step.state, state_suffix);
    const driver_state = try driver.from_driver(scratch);

    return eqlValue(Driver.State, spec_state, driver_state);
}

fn eqlValue(comptime T: type, lhs: T, rhs: T) bool {
    return switch (@typeInfo(T)) {
        .optional => |opt| if (lhs == null or rhs == null) lhs == null and rhs == null else eqlValue(opt.child, lhs.?, rhs.?),
        .pointer => |ptr| switch (ptr.size) {
            .slice => eqlSlice(ptr.child, lhs, rhs),
            .one => eqlValue(ptr.child, lhs.*, rhs.*),
            else => @compileError("check_state does not support this pointer type"),
        },
        .@"struct" => eqlStruct(T, lhs, rhs),
        else => std.meta.eql(lhs, rhs),
    };
}

fn eqlSlice(comptime Child: type, lhs: []const Child, rhs: []const Child) bool {
    if (Child == u8) return std.mem.eql(u8, lhs, rhs);
    if (lhs.len != rhs.len) return false;

    for (lhs, rhs) |left, right| {
        if (!eqlValue(Child, left, right)) return false;
    }

    return true;
}

fn eqlStruct(comptime T: type, lhs: T, rhs: T) bool {
    if (@hasDecl(T, "KV")) return eqlHashMap(T, lhs, rhs);
    if (@hasField(T, "items")) return eqlSlice(std.meta.Elem(@TypeOf(lhs.items)), lhs.items, rhs.items);
    if (!hasIgnoredFields(T)) return std.meta.eql(lhs, rhs);

    inline for (@typeInfo(T).@"struct".fields) |field| {
        if (field.type == std.mem.Allocator) continue;
        if (!eqlValue(field.type, @field(lhs, field.name), @field(rhs, field.name))) return false;
    }

    return true;
}

fn eqlHashMap(comptime Map: type, lhs: Map, rhs: Map) bool {
    if (lhs.count() != rhs.count()) return false;

    const value_type = hashMapValueType(Map);
    var it = lhs.iterator();
    while (it.next()) |entry| {
        const right_value = rhs.get(entry.key_ptr.*) orelse return false;
        if (!eqlValue(value_type, entry.value_ptr.*, right_value)) return false;
    }

    return true;
}

fn hashMapValueType(comptime Map: type) type {
    inline for (@typeInfo(Map.KV).@"struct".fields) |field| {
        if (std.mem.eql(u8, field.name, "value")) return field.type;
    }

    @compileError("Unsupported hash map type");
}

fn hasIgnoredFields(comptime T: type) bool {
    inline for (@typeInfo(T).@"struct".fields) |field| {
        if (field.type == std.mem.Allocator) return true;
    }

    return false;
}

test "check_state returns true when spec and driver states match" {
    const gpa = std.testing.allocator;

    const Role = enum { Follower, Candidate, Leader };
    const SpecState = struct {
        term: i64,
        role: Role,
        votedFor: ?[]const u8,
    };

    const DummyDriver = struct {
        pub const State = SpecState;

        term: i64,
        role: Role,
        voted_for: ?[]const u8,

        fn from_driver(self: *@This(), gpa_inner: std.mem.Allocator) !State {
            _ = gpa_inner;
            return .{
                .term = self.term,
                .role = self.role,
                .votedFor = self.voted_for,
            };
        }
    };

    var nondet = std.StringHashMap(quizz.Values).init(gpa);
    defer nondet.deinit();

    var step_state = std.StringHashMap(quizz.Values).init(gpa);
    defer step_state.deinit();
    try step_state.put("term", .{ .BigInt = "3" });

    const role_inner = try gpa.create(quizz.Values);
    defer gpa.destroy(role_inner);
    role_inner.* = .{ .Tuple = .{} };
    try step_state.put("role", .{
        .Variant = .{ .tag = "Candidate", .value = role_inner },
    });

    const voted_for_inner = try gpa.create(quizz.Values);
    defer gpa.destroy(voted_for_inner);
    voted_for_inner.* = .{ .String = "n2" };
    try step_state.put("votedFor", .{
        .Variant = .{ .tag = "Some", .value = voted_for_inner },
    });

    const step = driver_mod.Step{
        .action_taken = "noop",
        .nondet_picks = .{ .Record = nondet },
        .state = .{ .Record = step_state },
    };

    var driver = DummyDriver{
        .term = 3,
        .role = .Candidate,
        .voted_for = "n2",
    };

    try std.testing.expect(try check_state(gpa, &driver, step, null));
}

test "check_state returns false when spec and driver states differ" {
    const gpa = std.testing.allocator;

    const SpecState = struct {
        term: i64,
    };

    const DummyDriver = struct {
        pub const State = SpecState;

        term: i64,

        fn from_driver(self: *@This(), gpa_inner: std.mem.Allocator) !State {
            _ = gpa_inner;
            return .{ .term = self.term };
        }
    };

    var nondet = std.StringHashMap(quizz.Values).init(gpa);
    defer nondet.deinit();

    var step_state = std.StringHashMap(quizz.Values).init(gpa);
    defer step_state.deinit();
    try step_state.put("term", .{ .BigInt = "4" });

    const step = driver_mod.Step{
        .action_taken = "noop",
        .nondet_picks = .{ .Record = nondet },
        .state = .{ .Record = step_state },
    };

    var driver = DummyDriver{ .term = 5 };

    try std.testing.expect(!(try check_state(gpa, &driver, step, null)));
}
