const std = @import("std");

pub fn eqlValue(comptime T: type, lhs: T, rhs: T) bool {
    const ti = @typeInfo(T);
    switch (ti) {
        .int, .bool, .float, .@"enum" => return lhs == rhs,
        .void => return true,
        .optional => |opt| {
            if (lhs == null and rhs == null) return true;
            if (lhs == null or rhs == null) return false;
            return eqlValue(opt.child, lhs.?, rhs.?);
        },
        .pointer => |p| {
            switch (p.size) {
                .one => return eqlValue(p.child, lhs.*, rhs.*),
                .slice => return eqlSlice(p.child, lhs, rhs),
                // currently many and c pointers are not supported
                else => unreachable,
            }
        },
        .@"struct" => return eqlStruct(T, lhs, rhs),
        else => @compileError("only int,bool,float,enum,optionals,pointer and struct supported got: \n" ++ @typeName(T)),
    }
    return false;
}

fn eqlStruct(comptime T: type, lhs: T, rhs: T) bool {
    if (@hasDecl(T, "KV")) return eqlHashMap(T, lhs, rhs);
    if (@hasField(T, "items")) return eqlSlice(std.meta.Elem(@TypeOf(lhs.items)), lhs.items, rhs.items);
    inline for (@typeInfo(T).@"struct".fields) |field| {
        if (field.type == std.mem.Allocator) continue;
        if (!eqlValue(field.type, @field(lhs, field.name), @field(rhs, field.name))) return false;
    }

    return true;
}

fn eqlHashMap(comptime T: type, lhs: T, rhs: T) bool {
    if (lhs.count() != rhs.count()) return false;
    var it = lhs.iterator();
    while (it.next()) |entry| {
        const value_type = comptime blk: {
            for (@typeInfo(T.KV).@"struct".fields) |f| {
                if (std.mem.eql(u8, f.name, "value")) break :blk f.type;
            }

            @compileError("KV type of the hasmap should have a value field");
        };

        const rv = rhs.get(entry.key_ptr.*) orelse return false;
        if (!eqlValue(value_type, entry.value_ptr.*, rv)) return false;
    }
    return true;
}

fn eqlSlice(comptime T: type, lhs: []const T, rhs: []const T) bool {
    if (T == u8) return std.mem.eql(T, lhs, rhs);
    if (lhs.len != rhs.len) return false;
    for (lhs, rhs) |l, r| {
        if (!eqlValue(T, l, r)) return false;
    }
    return true;
}
