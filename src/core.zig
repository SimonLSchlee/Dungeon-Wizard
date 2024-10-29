const std = @import("std");
const Self = @This();
const utl = @import("util.zig");
const V2f = @import("V2f.zig");
const v2f = V2f.v2f;
const V2i = @import("V2i.zig");
const v2i = V2i.v2i;
const Platform = @import("main.zig").Platform;

pub const Error = error{
    OutOfMemory,
    Overflow,
    NoSpaceLeft,
    OutOfRange,
    LookupFail,
    RecompileFail,
    FileSystemFail,
    ParseFail,
};

pub const Key = enum(u32) {
    const numbers = [_]Key{ .zero, .one, .two, .three, .four, .five, .six, .seven, .eight, .nine };

    backtick,
    space,
    apostrophe,
    comma,
    minus,
    period,
    a,
    b,
    c,
    d,
    e,
    f,
    g,
    h,
    i,
    j,
    k,
    l,
    m,
    n,
    o,
    p,
    q,
    r,
    s,
    t,
    u,
    v,
    w,
    x,
    y,
    z,
    zero,
    one,
    two,
    three,
    four,
    five,
    six,
    seven,
    eight,
    nine,
    semicolon,
    equals,
    slash,
    backslash,
    left,
    right,
    up,
    down,
    escape,
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,
};

pub const MouseButton = enum {
    left,
    right,
};

pub const InputState = struct {
    keys: std.EnumSet(Key) = std.EnumSet(Key).initEmpty(),
    mouse_buttons: std.EnumSet(MouseButton) = std.EnumSet(MouseButton).initEmpty(),
    mouse_screen_pos: V2f = .{},
};

pub const InputBuffer = struct {
    const buf_sz = 3;

    arr: [buf_sz]InputState = .{.{}} ** buf_sz,
    curr_idx: usize = 0,

    pub fn advance_one(self: *InputBuffer) void {
        self.curr_idx = (self.curr_idx + 1) % buf_sz;
        const state = self.getCurrPtr();
        state.* = .{};
    }

    pub fn getCurrPtr(self: *InputBuffer) *InputState {
        return &self.arr[self.curr_idx];
    }

    pub fn getCurr(self: *const InputBuffer) InputState {
        return self.arr[self.curr_idx];
    }

    pub fn getPrev(self: *const InputBuffer) InputState {
        return self.arr[(self.curr_idx + buf_sz - 1) % buf_sz];
    }

    pub fn keyIsDown(self: *const InputBuffer, key: Key) bool {
        return self.getCurr().keys.contains(key);
    }

    pub fn getNumberKeyDown(self: *const InputBuffer) ?u4 {
        for (Key.numbers, 0..) |k, i| {
            if (self.keyIsDown(k)) {
                return utl.as(u4, i);
            }
        }
        return null;
    }
    pub fn getNumberKeyJustPressed(self: *const InputBuffer) ?u4 {
        for (Key.numbers, 0..) |k, i| {
            if (self.keyIsJustPressed(k)) {
                return utl.as(u4, i);
            }
        }
        return null;
    }

    pub fn keyIsJustPressed(self: *const InputBuffer, key: Key) bool {
        return self.getCurr().keys.contains(key) and !self.getPrev().keys.contains(key);
    }

    pub fn mouseBtnIsDown(self: *const InputBuffer, btn: MouseButton) bool {
        return self.getCurr().mouse_buttons.contains(btn);
    }

    pub fn mouseBtnIsJustPressed(self: *const InputBuffer, btn: MouseButton) bool {
        return self.getCurr().mouse_buttons.contains(btn) and !self.getPrev().mouse_buttons.contains(btn);
    }

    pub fn getCurrMousePos(self: *const InputBuffer) V2f {
        return self.getCurr().mouse_screen_pos;
    }
};

pub const rt_safe_blocks: bool = true;

pub const ms_per_sec: i64 = 1000;
pub const us_per_sec: i64 = 1000 * ms_per_sec;
pub const ns_per_sec: i64 = 1000 * us_per_sec;

pub fn nsToSecs(ns: i64) f64 {
    return utl.as(f64, ns) / utl.as(f64, ns_per_sec);
}

pub const native_dims: V2i = v2i(1280, 800);
pub const native_dims_f: V2f = native_dims.toV2f();
pub const native_dims_xy_ratio: f32 = native_dims_f.x / native_dims_f.y;
pub const supported_resolutions = [_]V2i{
    native_dims,
    v2i(1366, 768),
    v2i(1600, 900),
    v2i(1920, 1200),
    v2i(1920, 1080),
    v2i(2560, 1440),
    v2i(3440, 1440),
    v2i(3840, 2160),
};
pub const pixel_art_scaling: f32 = 4;

pub const fixed_updates_per_sec: i64 = 60;
pub const fups_per_sec = fixed_updates_per_sec;
pub const fups_per_sec_f = utl.as(f32, fups_per_sec);
pub const fixed_ns_per_update: i64 = ns_per_sec / fixed_updates_per_sec;
pub const fixed_ns_per_update_upper: i64 = ns_per_sec / fixed_updates_per_sec + 1;
pub const fixed_ns_per_update_lower: i64 = ns_per_sec / fixed_updates_per_sec - 1;
pub const fixed_update_fuzziness_ns: i64 = 500 * ns_per_sec / us_per_sec;
pub const fixed_max_updates_per_frame: i64 = 8;
pub const fixed_max_accumulated_update_ns: i64 = fixed_max_updates_per_frame * fixed_ns_per_update;

pub inline fn fups_to_secsf(fups: i64) f32 {
    return utl.as(f32, fups) / fups_per_sec_f;
}

pub inline fn secsToTicks(secs: f32) i64 {
    return utl.as(i64, @round(secs * fups_per_sec_f));
}

pub inline fn ms_to_ticks(ms: i64) i64 {
    return @divFloor((fups_per_sec * ms), ms_per_sec);
}
