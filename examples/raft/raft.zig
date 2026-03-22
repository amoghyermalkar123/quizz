const std = @import("std");

pub const NodeRole = enum {
    Follower,
    Candidate,
    Leader,
};

pub const Data = struct {
    command: []const u8,
    key: []const u8,
    value: []const u8,
};

pub const Log = struct {
    index: i64,
    term: i64,
    data: Data,
};

// RaftSM holds the actual logic for the raft protocol exists
// dev writes this
pub const RaftSM = struct {
    currentTerm: i64,
    role: NodeRole,
    logs: std.ArrayList(Log),
    votedFor: ?[]const u8,
    votesReceived: std.StringHashMap(void),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init() !Self {}

    pub fn become_candidate(self: Self) !void {
        _ = self;
    }

    pub fn become_leader(self: Self) !void {
        _ = self;
    }

    pub fn grant_vote(self: Self) !void {
        _ = self;
    }
};
