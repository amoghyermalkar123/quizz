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

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .currentTerm = 0,
            .role = .Follower,
            .logs = .empty,
            .votedFor = null,
            .votesReceived = std.StringHashMap(void).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.logs.deinit(self.allocator);
        self.votesReceived.deinit();
    }

    pub fn reset(self: *Self) void {
        self.currentTerm = 0;
        self.role = .Follower;
        self.logs.clearRetainingCapacity();
        self.votedFor = null;
        self.votesReceived.clearRetainingCapacity();
    }

    pub fn become_candidate(self: *Self, node_id: []const u8) !void {
        self.currentTerm += 1;
        self.role = .Candidate;
        self.votedFor = node_id;
        self.votesReceived.clearRetainingCapacity();
        try self.votesReceived.put(node_id, {});
    }

    pub fn become_leader(self: *Self, processes: *std.StringHashMap(Self)) !void {
        self.role = .Leader;

        var it = processes.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr == self) continue;
            if (entry.value_ptr.role == .Leader and entry.value_ptr.currentTerm < self.currentTerm) {
                entry.value_ptr.role = .Follower;
            }
        }
    }

    pub fn grant_vote(
        self: *Self,
        voter_id: []const u8,
        candidate_id: []const u8,
        processes: *std.StringHashMap(Self),
    ) !void {
        const candidate = processes.getPtr(candidate_id) orelse return error.UnknownNode;

        self.currentTerm = candidate.currentTerm;
        self.votedFor = candidate_id;
        try candidate.votesReceived.put(voter_id, {});
    }
};
