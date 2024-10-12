const std = @import("std");
const u = @import("util.zig");
const core = @import("core.zig");
const Error = core.Error;
const Platform = @import("main.zig").Platform;
const assert = std.debug.assert;

const util = @import("util.zig");
const V2f = @import("V2f.zig");
const V2i = @import("V2i.zig");
const iToV2f = V2f.iToV2f;
const iToV2i = V2i.iToV2i;

pub const Coloru = struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: u8 = 255,

    pub const blank: Coloru = .{ .a = 0 };
    pub const black: Coloru = .{};
    pub const white: Coloru = .{ .r = 255, .g = 255, .b = 255 };
    pub const red: Coloru = .{ .r = 255 };
    pub const green: Coloru = .{ .g = 255 };
    pub const blue: Coloru = .{ .b = 255 };
    pub const yellow: Coloru = .{ .r = 255, .g = 255 };
    pub const magenta: Coloru = .{ .r = 255, .b = 255 };
    pub const cyan: Coloru = .{ .b = 255, .g = 255 };
    pub const orange: Coloru = .{ .r = 255, .g = 128 };
    pub const purple: Coloru = .{ .r = 128, .b = 255 };
    pub const lightgray: Coloru = makeGray(128 + 64);
    pub const gray: Coloru = makeGray(128);
    pub const darkgray: Coloru = makeGray(128 - 64);

    pub fn rgb(r: u8, g: u8, b: u8) Coloru {
        return .{
            .r = r,
            .g = g,
            .b = b,
        };
    }

    pub fn rgba(r: u8, g: u8, b: u8, a: u8) Coloru {
        return .{
            .r = r,
            .g = g,
            .b = b,
            .a = a,
        };
    }

    pub fn makeGray(v: u8) Coloru {
        return rgb(v, v, v);
    }

    pub fn toColorf(self: Coloru) Colorf {
        return Colorf.rgba(
            u.as(f32, self.r) / 255,
            u.as(f32, self.g) / 255,
            u.as(f32, self.b) / 255,
            u.as(f32, self.a) / 255,
        );
    }
};

pub const Colorf = struct {
    r: f32 = 0,
    g: f32 = 0,
    b: f32 = 0,
    a: f32 = 1,

    pub const blank: Colorf = .{ .a = 0 };
    pub const black: Colorf = .{};
    pub const white: Colorf = Coloru.white.toColorf();
    pub const red: Colorf = Coloru.red.toColorf();
    pub const green: Colorf = Coloru.green.toColorf();
    pub const blue: Colorf = Coloru.blue.toColorf();
    pub const yellow: Colorf = Coloru.yellow.toColorf();
    pub const magenta: Colorf = Coloru.magenta.toColorf();
    pub const cyan: Colorf = Coloru.cyan.toColorf();
    pub const orange: Colorf = Coloru.orange.toColorf();
    pub const purple: Colorf = Coloru.purple.toColorf();
    pub const lightgray: Colorf = Coloru.lightgray.toColorf();
    pub const gray: Colorf = Coloru.gray.toColorf();
    pub const darkgray: Colorf = Coloru.darkgray.toColorf();

    pub fn rgb(r: f32, g: f32, b: f32) Colorf {
        return .{
            .r = r,
            .g = g,
            .b = b,
        };
    }

    pub fn rgba(r: f32, g: f32, b: f32, a: f32) Colorf {
        return .{
            .r = r,
            .g = g,
            .b = b,
            .a = a,
        };
    }

    pub fn clamp(self: Colorf) Colorf {
        return rgba(
            u.clampf(self.r, 0, 1),
            u.clampf(self.g, 0, 1),
            u.clampf(self.b, 0, 1),
            u.clampf(self.a, 0, 1),
        );
    }

    pub fn fade(self: Colorf, a: f32) Colorf {
        return rgba(
            self.r,
            self.g,
            self.b,
            self.a * a,
        );
    }

    pub fn toColoru(self: Colorf) Coloru {
        const clamped = self.clamp();
        return Coloru.rgba(
            u.as(u8, clamped.r * 255),
            u.as(u8, clamped.g * 255),
            u.as(u8, clamped.b * 255),
            u.as(u8, clamped.a * 255),
        );
    }

    pub fn getContrasting(self: Colorf) Colorf {
        const total = self.r + self.g + self.b;
        if (total > 1.5) return .black;
        return .white;
    }

    pub fn lerp(self: Colorf, other: Colorf, t: f32) Colorf {
        const t_clamped = u.clampf(t, 0, 1);
        return rgba(
            u.lerpf(self.r, other.r, t_clamped),
            u.lerpf(self.g, other.g, t_clamped),
            u.lerpf(self.b, other.b, t_clamped),
            u.lerpf(self.a, other.a, t_clamped),
        );
    }
};

pub const Smoothing = enum {
    none, // nearest neighbor
    bilinear,
};

pub const Blend = enum {
    alpha,
    multiply,
    render_tex_alpha, // yeah
};

pub const TextOpt = struct {
    font: ?Platform.Font = null,
    size: u32 = 20,
    color: Colorf = Colorf.black,
    center: bool = false,
};

pub const PolyOpt = struct {
    fill_color: ?Colorf = Colorf.black,
    outline_thickness: f32 = 1,
    outline_color: ?Colorf = null,
};

pub const TextureOrigin = union(enum) {
    topleft,
    center,
    offset: V2f,
};
pub const TextureOpt = struct {
    tint: Colorf = Colorf.white,
    smoothing: Smoothing = .none,
    // draw, rotate, scale with origin at center (bit weird for offset)
    origin: TextureOrigin = .topleft,
    // cut rect out of source image
    src_pos: ?V2f = null,
    src_dims: ?V2f = null,
    // scale and rotate (about origin)
    flip_x: bool = false,
    flip_y: bool = false,
    scaled_dims: ?V2f = null, // x y absolute scaled dims, applied before uniform_scaling
    uniform_scaling: f32 = 1.0,
    rot_rads: f32 = 0,
};

pub const Camera2D = struct {
    pos: V2f = .{},
    offset: V2f = .{},
    rot_rads: f32 = 0,
    zoom: f32 = 1,
};
