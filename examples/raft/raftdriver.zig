const std = @import("std");
const raft = @import("raft.zig");
const NodeRole = raft.NodeRole;
const Log = raft.Log;
const quizz = @import("quizz");
const State = quizz.State;

// represents the state as similarly mentioned in the quint spec
pub const SpecState = struct {
    currentTerm: std.StringHashMap(i64),
    role: std.StringHashMap(NodeRole),
    logs: std.StringHashMap(std.ArrayList(Log)),
    votedFor: std.StringHashMap(?[]const u8),
    votesReceived: std.StringHashMap(std.StringHashMap(void)),
    allocator: std.mem.Allocator,

    pub fn from_driver(driver: *RaftDriver) !void {
        _ = driver;
    }
};

pub const RaftDriver = struct {
    processes: std.AutoHashMap([]const u8, raft.RaftSM),
    messages: []const []const u8,

    pub fn step(self: *@This(), st: quizz.Step) !void {}
};
