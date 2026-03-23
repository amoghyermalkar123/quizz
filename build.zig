const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("quizz", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // test module
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);

    // adding the raft driver as an executable example
    const raft_mod = b.addModule("raft", .{
        .root_source_file = b.path("examples/raft/raftdriver.zig"),
        .target = target,
        .optimize = optimize,
    });

    raft_mod.addImport("quizz", mod);

    const raft_exe = b.addExecutable(.{
        .root_module = raft_mod,
        .name = "raft",
    });

    b.installArtifact(raft_exe);

    // adding a runnable artifact
    const run_raft = b.addRunArtifact(raft_exe);
    run_raft.step.dependOn(b.getInstallStep());

    // pass CLI arguments: zig build run -- trace.itf.json
    if (b.args) |args| {
        run_raft.addArgs(args);
    }

    const run_step = b.step("run", "Run the raft example");
    run_step.dependOn(&run_raft.step);

    // add raft tests to test step
    const raft_tests = b.addTest(.{
        .root_module = raft_mod,
    });
    const run_raft_tests = b.addRunArtifact(raft_tests);
    test_step.dependOn(&run_raft_tests.step);
}
