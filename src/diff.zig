const std = @import("std");

pub const DiffKind = enum {
    missing,
    extra,
    value_mismatch,
    type_mismatch,
    len_mismatch,
    variant_mismatch,
};

pub const PathSegment = union(enum) {
    field: []const u8,
    index: usize,
    key: []const u8,
};

pub const DiffEntry = struct {
    path: []PathSegment,
    kind: DiffKind,
    expected_display: ?[]const u8 = null,
    actual_display: ?[]const u8 = null,

    pub fn push(
        gpa: std.mem.Allocator,
        path_stack: []const PathSegment,
        kind: DiffKind,
        expected_display: ?[]const u8,
        actual_display: ?[]const u8,
    ) !DiffEntry {
        var path = try gpa.alloc(PathSegment, path_stack.len);

        for (path_stack, 0..) |segment, i| {
            path[i] = switch (segment) {
                .field => |name| .{ .field = try gpa.dupe(u8, name) },
                .index => |index| .{ .index = index },
                .key => |key| .{ .key = try gpa.dupe(u8, key) },
            };
        }

        return .{
            .path = path,
            .kind = kind,
            .expected_display = if (expected_display) |value| try gpa.dupe(u8, value) else null,
            .actual_display = if (actual_display) |value| try gpa.dupe(u8, value) else null,
        };
    }

    pub fn deinit(self: *DiffEntry, gpa: std.mem.Allocator) void {
        for (self.path) |segment| {
            switch (segment) {
                .field => |name| gpa.free(name),
                .index => {},
                .key => |key| gpa.free(key),
            }
        }

        gpa.free(self.path);

        if (self.expected_display) |value| gpa.free(value);
        if (self.actual_display) |value| gpa.free(value);
    }
};

pub const CompareResult = struct {
    diffs: std.ArrayList(DiffEntry),

    pub fn isEqual(self: @This()) bool {
        return self.diffs.items.len == 0;
    }

    pub fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
        for (self.diffs.items) |*entry| {
            entry.deinit(gpa);
        }
        self.diffs.deinit(gpa);
    }
};

pub const DiffContext = struct {
    arena: std.mem.Allocator,
    path_stack: std.ArrayList(PathSegment),
    diffs: std.ArrayList(DiffEntry),
    max_diffs: usize = 128,
};

pub fn formatPath(gpa: std.mem.Allocator, path: []const PathSegment) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(gpa);

    for (path, 0..) |segment, i| {
        switch (segment) {
            .field => |name| {
                if (i != 0) try out.append(gpa, '.');
                try out.appendSlice(gpa, name);
            },
            .index => |index| try out.writer(gpa).print("[{}]", .{index}),
            .key => |key| try out.writer(gpa).print("[\"{s}\"]", .{key}),
        }
    }

    return try out.toOwnedSlice(gpa);
}

pub fn formatEntry(gpa: std.mem.Allocator, entry: DiffEntry) ![]u8 {
    const path = try formatPath(gpa, entry.path);
    defer gpa.free(path);

    return switch (entry.kind) {
        .missing => std.fmt.allocPrint(gpa, "- {s}: missing", .{path}),
        .extra => std.fmt.allocPrint(gpa, "+ {s}: extra", .{path}),
        .len_mismatch => std.fmt.allocPrint(gpa, "~ {s}: length differs", .{path}),
        .type_mismatch => std.fmt.allocPrint(gpa, "~ {s}: type differs", .{path}),
        .variant_mismatch => std.fmt.allocPrint(gpa, "~ {s}: variant differs", .{path}),
        .value_mismatch => std.fmt.allocPrint(
            gpa,
            "~ {s}: expected={s} actual={s}",
            .{
                path,
                entry.expected_display orelse "<null>",
                entry.actual_display orelse "<null>",
            },
        ),
    };
}
