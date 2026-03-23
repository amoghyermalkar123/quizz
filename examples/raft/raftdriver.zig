const std = @import("std");
const raft = @import("raft.zig");
const NodeRole = raft.NodeRole;
const Log = raft.Log;
const quizz = @import("quizz");

const state_suffix = "raft_test::raft";

// represents the state as similarly mentioned in the quint spec
pub const SpecState = struct {
    currentTerm: std.StringHashMap(i64),
    role: std.StringHashMap(NodeRole),
    logs: std.StringHashMap(std.ArrayList(Log)),
    votedFor: std.StringHashMap(?[]const u8),
    votesReceived: std.StringHashMap(std.StringHashMap(void)),
    allocator: std.mem.Allocator,

    pub fn from_driver(gpa: std.mem.Allocator, driver: *RaftDriver) !SpecState {
        var currentTerm = std.StringHashMap(i64).init(gpa);
        var role = std.StringHashMap(NodeRole).init(gpa);
        var logs = std.StringHashMap(std.ArrayList(Log)).init(gpa);
        var votedFor = std.StringHashMap(?[]const u8).init(gpa);
        var votesReceived = std.StringHashMap(std.StringHashMap(void)).init(gpa);

        var it = driver.processes.iterator();
        while (it.next()) |entry| {
            try currentTerm.put(entry.key_ptr.*, entry.value_ptr.currentTerm);
            try role.put(entry.key_ptr.*, entry.value_ptr.role);
            try votedFor.put(entry.key_ptr.*, entry.value_ptr.votedFor);

            var copied_logs: std.ArrayList(Log) = .empty;
            for (entry.value_ptr.logs.items) |log| {
                try copied_logs.append(gpa, log);
            }
            try logs.put(entry.key_ptr.*, copied_logs);

            var copied_votes = std.StringHashMap(void).init(gpa);
            var votes_it = entry.value_ptr.votesReceived.iterator();
            while (votes_it.next()) |vote| {
                try copied_votes.put(vote.key_ptr.*, {});
            }
            try votesReceived.put(entry.key_ptr.*, copied_votes);
        }

        return .{
            .currentTerm = currentTerm,
            .role = role,
            .logs = logs,
            .votedFor = votedFor,
            .votesReceived = votesReceived,
            .allocator = gpa,
        };
    }
};

// Your driver should have 3 important things
// A State declaration which also has a function called from_driver
// The goal of the State declaration is for it to be easily be extracted
// into from this Driver's cluster state
// A step function
pub const RaftDriver = struct {
    // This type tells the quizz library
    // what to parse an itf state into
    pub const State = SpecState;

    allocator: std.mem.Allocator,
    processes: std.StringHashMap(raft.RaftSM),
    messages: []const []const u8,

    pub fn create(gpa: std.mem.Allocator) !@This() {
        var processes = std.StringHashMap(raft.RaftSM).init(gpa);
        errdefer processes.deinit();

        try processes.put("n1", raft.RaftSM.init(gpa));
        try processes.put("n2", raft.RaftSM.init(gpa));
        try processes.put("n3", raft.RaftSM.init(gpa));

        return .{
            .allocator = gpa,
            .processes = processes,
            .messages = &.{},
        };
    }

    pub fn deinit(self: *@This()) void {
        var it = self.processes.valueIterator();
        while (it.next()) |node| {
            node.deinit();
        }
        self.processes.deinit();
    }

    // The step function matches the respective action names
    // given to us by the trace file and advances the state machine
    pub fn step(self: *@This(), st: quizz.QuizDriver.Step) !void {
        try quizz.QuizDriver.dispatch(self.allocator, self, st, .{
            .init = quizz.QuizDriver.case(.{}, RaftDriver.init),
            .stutter = quizz.QuizDriver.case(.{}, RaftDriver.stutter),
            .becomeCandidate = quizz.QuizDriver.case(.{"candidate"}, RaftDriver.becomeCandidate),
            .becomeLeader = quizz.QuizDriver.case(.{"node"}, RaftDriver.becomeLeader),
            .grantVote = quizz.QuizDriver.case(.{ "voter", "candidate" }, RaftDriver.grantVote),
        });
    }

    pub fn init(self: *@This()) !void {
        var it = self.processes.valueIterator();
        while (it.next()) |node| {
            node.reset();
        }
    }

    pub fn stutter(self: *@This()) !void {
        _ = self;
    }

    pub fn becomeCandidate(self: *@This(), candidate: ?[]const u8) !void {
        const node_id = candidate orelse return error.MissingCandidate;
        try (self.processes.getPtr(node_id) orelse return error.UnknownNode).become_candidate(node_id);
    }

    pub fn becomeLeader(self: *@This(), node: ?[]const u8) !void {
        const node_id = node orelse return error.MissingNode;
        try (self.processes.getPtr(node_id) orelse return error.UnknownNode).become_leader(&self.processes);
    }

    pub fn grantVote(self: *@This(), voter: ?[]const u8, candidate: ?[]const u8) !void {
        const voter_id = voter orelse return error.MissingVoter;
        const candidate_id = candidate orelse return error.MissingCandidate;
        try (self.processes.getPtr(voter_id) orelse return error.UnknownNode).grant_vote(voter_id, candidate_id, &self.processes);
    }

    // The from_driver function should also return the `State`
    // variable you declare at the top of your driver container
    // Essentially, quizz will compare your driver's State
    // with that of the quint generated ITF's State
    pub fn from_driver(self: *@This(), gpa: std.mem.Allocator) !State {
        return try State.from_driver(gpa, self);
    }
};

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();

    const gpa = gpa_state.allocator();
    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    const spec_path = if (args.len > 1) args[1] else "examples/raft/spec/raft.qnt";

    var driver = try RaftDriver.create(gpa);
    defer driver.deinit();

    try quizz.run_test(gpa, &driver, spec_path, state_suffix);
}
