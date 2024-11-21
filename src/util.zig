const std = @import("std");
const Self = @This();

pub const pi: f32 = std.math.pi;
pub const tau: f32 = 2 * std.math.pi;

pub inline fn swap(T: type, a: *T, b: *T) void {
    const tmp = a.*;
    a.* = b.*;
    b.* = tmp;
}

pub fn degreesToRadians(degrees: f32) f32 {
    const sign = std.math.sign(degrees);
    const abs = @abs(degrees);
    const abs_norm = @mod(abs, 360.0) * (1.0 / 360.0);
    const abs_ret = abs_norm * tau;

    return sign * abs_ret;
}

pub fn radiansToDegrees(radians: f32) f32 {
    const sign = std.math.sign(radians);
    const abs = @abs(radians);
    const abs_norm: f32 = @mod(abs, tau) * (1.0 / tau);
    const abs_ret = abs_norm * 360;

    return sign * abs_ret;
}

// normalize radians to range [0, tau]
pub fn normalizeRadians0_Tau(radians: f32) f32 {
    const sign = std.math.sign(radians);
    const abs = @abs(radians);
    const abs_mod = @mod(abs, tau);
    if (sign == -1) {
        return -abs_mod + tau;
    }
    return abs_mod;
}

pub fn strEq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

var __str_fmt_local_buf: [2048]u8 = undefined;
pub fn bufPrintLocal(comptime fmt: []const u8, args: anytype) ![]u8 {
    return try std.fmt.bufPrint(__str_fmt_local_buf[0..], fmt, args);
}
pub fn bufPrintLocalZ(comptime fmt: []const u8, args: anytype) ![:0]u8 {
    return try std.fmt.bufPrintZ(__str_fmt_local_buf[0..], fmt, args);
}

/// Converts between numeric types: .Enum, .Int and .Float.
/// https://ziggit.dev/t/as-f32-value-expects-f32/2422/6
pub inline fn as(comptime T: type, from: anytype) T {
    switch (@typeInfo(@TypeOf(from))) {
        .@"enum" => {
            switch (@typeInfo(T)) {
                .int => return @intFromEnum(from),
                else => @compileError(@typeName(@TypeOf(from)) ++ " can't be converted to " ++ @typeName(T)),
            }
        },
        .int => {
            switch (@typeInfo(T)) {
                .@"enum" => return @enumFromInt(from),
                .int => return @intCast(from),
                .float => return @floatFromInt(from),
                else => @compileError(@typeName(@TypeOf(from)) ++ " can't be converted to " ++ @typeName(T)),
            }
        },
        .float => {
            switch (@typeInfo(T)) {
                .float => return @floatCast(from),
                .int => return @intFromFloat(from),
                else => @compileError(@typeName(@TypeOf(from)) ++ " can't be converted to " ++ @typeName(T)),
            }
        },
        else => @compileError(@typeName(@TypeOf(from) ++ " is not supported.")),
    }
}

pub inline fn clamp(comptime T: type, x: T, lo: T, hi: T) T {
    return @min(@max(x, lo), hi);
}

pub inline fn clampf(x: f32, lo: f32, hi: f32) f32 {
    return clamp(f32, x, lo, hi);
}

pub inline fn lerpf(a: f32, b: f32, t: f32) f32 {
    return (1 - t) * a + b * t;
}

pub fn lerpClampf(a: f32, b: f32, t: f32) f32 {
    if (t > 1) return b;
    if (t < 0) return a;
    return lerpf(a, b, t);
}

pub inline fn invLerpf(a: f32, b: f32, v: f32) f32 {
    return (v - a) / (b - a);
}

pub fn invLerpClampf(a: f32, b: f32, v: f32) f32 {
    if (v > b) return 1;
    if (v < a) return 0;
    return invLerpf(a, b, v);
}

pub fn remapClampf(orig_a: f32, orig_b: f32, target_a: f32, target_b: f32, v: f32) f32 {
    const t = invLerpClampf(orig_a, orig_b, v);
    return lerpf(target_a, target_b, t);
}

pub fn expectTypeInfo(T: type, comptime kind: std.builtin.TypeId) std.meta.TagPayload(std.builtin.Type, kind) {
    const info = @typeInfo(T);
    if (info != kind) @compileError("Expected typeinfo " ++ @tagName(kind) ++ ", got " ++ @tagName(info));
    return @field(info, @tagName(kind));
}

// combine fields of structs together
pub fn MixStructFields(Structs: []const type) type {
    var total_fields = 0;
    const layout = expectTypeInfo(Structs[0], .@"struct").layout;
    const backing_integer = expectTypeInfo(Structs[0], .@"struct").backing_integer;

    for (Structs) |S| {
        const s = expectTypeInfo(S, .@"struct");
        if (s.layout != layout) @compileError("Super and extend struct layouts must be the same");
        if (s.backing_integer != backing_integer) @compileError("Super and extend struct backing integers must be the same");
        total_fields += s.fields.len;
    }
    const EmptyField = std.builtin.Type.StructField{
        .name = "",
        .type = undefined,
        .default_value = null,
        .is_comptime = false,
        .alignment = 0,
    };
    var fields: [total_fields]std.builtin.Type.StructField = [_]std.builtin.Type.StructField{EmptyField} ** total_fields;
    var i = 0;
    for (Structs) |S| {
        const s = expectTypeInfo(S, .@"struct");
        for (s.fields) |f| {
            fields[i] = f;
            i += 1;
        }
    }

    return @Type(.{
        .@"struct" = .{
            .layout = layout,
            .backing_integer = backing_integer,
            .fields = &fields,
            .decls = &.{},
            .is_tuple = false,
        },
    });
}

pub fn EnumFromTypes(Types: []const type, enum_name_field: []const u8) type {
    const EnumField = std.builtin.Type.EnumField;
    const empty = EnumField{
        .name = "",
        .value = 0,
    };
    var fields: [Types.len]EnumField = [_]EnumField{empty} ** Types.len;
    for (Types, 0..) |M, i| {
        const enum_name = @field(M, enum_name_field);
        fields[i] = .{
            .name = enum_name,
            .value = i,
        };
    }
    return @Type(.{
        .@"enum" = .{
            .tag_type = std.math.IntFittingRange(0, fields.len),
            .fields = &fields,
            .decls = &.{},
            .is_exhaustive = true,
        },
    });
}

pub fn TaggedUnionFromTypes(Types: []const type, enum_name_field: []const u8, TagType: type) type {
    const UnionField = std.builtin.Type.UnionField;
    const empty = UnionField{
        .name = "",
        .type = void,
        .alignment = 1,
    };
    var fields: [Types.len]UnionField = [_]UnionField{empty} ** Types.len;
    for (Types, 0..) |M, i| {
        const enum_name = @field(M, enum_name_field);
        fields[i] = .{
            .name = enum_name,
            .type = M,
            .alignment = @alignOf(M),
        };
    }
    return @Type(.{
        .@"union" = .{
            .layout = .auto,
            .tag_type = TagType,
            .fields = &fields,
            .decls = &.{},
        },
    });
}

pub const TickCounter = struct {
    num_ticks: i64 = 0,
    curr_tick: i64 = 0,
    running: bool = false,

    pub fn init(num: i64) TickCounter {
        return .{
            .num_ticks = num,
        };
    }

    // timer won't run until restart()
    pub fn initStopped(num: i64) TickCounter {
        return .{
            .num_ticks = num,
            .curr_tick = num,
        };
    }

    pub fn restart(self: *TickCounter) void {
        self.curr_tick = 0;
        self.running = true;
    }

    pub fn tick(self: *TickCounter, restart_on_done: bool) bool {
        self.curr_tick = @min(self.curr_tick + 1, self.num_ticks);
        const done = self.curr_tick >= self.num_ticks;

        if (done) {
            self.running = false;
            if (restart_on_done) {
                self.restart();
            }
        } else {
            self.running = true;
        }
        return done;
    }

    pub fn remapTo0_1(self: *const TickCounter) f32 {
        return remapClampf(0, as(f32, self.num_ticks), 0, 1, as(f32, self.curr_tick));
    }

    pub fn ticksLeft(self: *const TickCounter) i64 {
        return self.num_ticks - self.curr_tick;
    }

    pub fn stop(self: *TickCounter) void {
        self.curr_tick = self.num_ticks;
        self.running = false;
    }
};

pub fn BoundedString(max_len: usize) type {
    return std.BoundedArray(u8, max_len);
}

pub fn enumToString(E: type, m: E) []const u8 {
    const e_info = expectTypeInfo(E, .@"enum");
    inline for (e_info.fields) |f| {
        const k: E = @enumFromInt(f.value);
        if (k == m) {
            return f.name;
        }
    }
    unreachable;
}
