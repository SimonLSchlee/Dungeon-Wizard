const std = @import("std");
const Self = @This();
const u = @import("util.zig");
const V2f = @import("V2f.zig");

x: i32 = 0,
y: i32 = 0,

pub fn v2i(x: i32, y: i32) Self {
    return .{
        .x = x,
        .y = y,
    };
}

pub fn iToV2i(comptime T: type, x: T, y: T) Self {
    return .{ .x = @intCast(x), .y = @intCast(y) };
}

pub fn toV2f(self: @This()) V2f {
    return .{ .x = @as(f32, @floatFromInt(self.x)), .y = @as(f32, @floatFromInt(self.y)) };
}

pub fn eql(self: Self, other: Self) bool {
    return self.x == other.x and self.y == other.y;
}

pub fn add(self: Self, other: Self) Self {
    return .{
        .x = self.x + other.x,
        .y = self.y + other.y,
    };
}

pub fn sub(self: Self, other: Self) Self {
    return .{
        .x = self.x - other.x,
        .y = self.y - other.y,
    };
}

pub fn neg(self: Self) Self {
    return .{
        .x = -self.x,
        .y = -self.y,
    };
}

pub fn scale(self: Self, s: i32) Self {
    return .{
        .x = self.x * s,
        .y = self.y * s,
    };
}

pub fn divFloor(self: Self, d: i32) Self {
    return v2i(@divFloor(self.x, d), @divFloor(self.y, d));
}

pub fn abs(self: Self) Self {
    return .{
        .x = u.as(i32, @abs(self.x)),
        .y = u.as(i32, @abs(self.y)),
    };
}

pub fn mLen(self: Self) i32 {
    return u.as(i32, @abs(self.x) + @abs(self.y));
}

pub fn mDist(self: Self, other: Self) i32 {
    return other.sub(self).mLen();
}

pub fn splat(val: i32) Self {
    return v2i(val, val);
}

pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = options;
    const vec_fmt = "({" ++ fmt ++ "}, {" ++ fmt ++ "})";
    try writer.print(vec_fmt, .{ self.x, self.y });
}

pub const Error = error{
    ParseFail,
};

pub fn parse(buf: []const u8, val: *Self) Error![]const u8 {
    if (buf.len < 2) return Error.ParseFail;
    if (buf[0] != '(') return Error.ParseFail;
    var end_idx: usize = 1;
    for (buf[1..], 1..) |c, i| {
        if (c == ')') {
            end_idx = i;
            break;
        }
    } else return Error.ParseFail;
    const inner = buf[1..end_idx];

    var comma_idx: usize = 0;
    for (inner, 0..) |c, i| {
        if (c == ',') {
            comma_idx = i;
            break;
        }
    } else return Error.ParseFail; // TODO single element splat?
    const x_trimmed = std.mem.trim(u8, inner[0..comma_idx], &std.ascii.whitespace);
    const x = std.fmt.parseInt(i32, x_trimmed, 0) catch return Error.ParseFail;
    const y_trimmed = std.mem.trim(u8, inner[comma_idx + 1 ..], &std.ascii.whitespace);
    const y = std.fmt.parseInt(i32, y_trimmed, 0) catch return Error.ParseFail;
    val.* = v2i(x, y);

    return buf[end_idx..];
}
