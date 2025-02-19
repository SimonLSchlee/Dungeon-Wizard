const std = @import("std");
const utl = @import("util.zig");

pub const Platform = @import("raylib.zig");
const core = @import("core.zig");
const Error = core.Error;
const Key = core.Key;
const debug = @import("debug.zig");
const assert = debug.assert;
const draw = @import("draw.zig");
const Colorf = draw.Colorf;
const geom = @import("geometry.zig");
const V2f = @import("V2f.zig");
const v2f = V2f.v2f;
const V2i = @import("V2i.zig");
const v2i = V2i.v2i;

const App = @import("App.zig");
const Log = App.Log;
const getPlat = App.getPlat;
const getData = App.getData;
const Data = @import("Data.zig");
const ImmUI = @import("ImmUI.zig");

// A "Private Use Area" of unicode
pub const pua_codepoint_start: u21 = 0xE000;
pub const pua_codepoint_end: u21 = 0xF8FF;
pub const pua_num_codepoints: u21 = 6400;
pub const pua_codepoint_num_utf8_bytes = 3;

pub const Icon = enum(u8) {
    target,
    skull,
    mouse,
    wizard,
    lightning,
    fire,
    icicle,
    magic,
    aoe_lightning,
    aoe_fire,
    aoe_ice,
    aoe_magic,
    water,
    arrow_right,
    heart,
    card,
    fast_forward,
    shield_empty,
    sword_hilt,
    droplets,
    arrow_shaft,
    shoes,
    ouchy_skull,
    spiral_yellow,
    doorway,
    monster_with_sword,
    ice_ball,
    arrow_180_CC,
    arrows_opp,
    mana_crystal,
    blood_splat,
    magic_eye,
    ouchy_heart,
    coin,
    wizard_inverse,
    spiky,
    burn,
    trailblaze,
    draw_card,
    shield,
    impling,
    summon,
    mislay,
    mana_crystal_smol,
    slime,
    mana_empty,
    mana_flame,
    snowfren,
    fairy,
    fireproof,
    lightningproof,
    bubble,

    pub const codepoint_start: u21 = pua_codepoint_start;
    pub const codepoint_end: u21 = codepoint_start + std.math.maxInt(@typeInfo(Icon).@"enum".tag_type);

    pub fn format(self: Icon, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) Error!void {
        _ = fmt;
        _ = options;
        var buf: [pua_codepoint_num_utf8_bytes]u8 = undefined;
        const s = self.toUtf8(&buf) catch return Error.EncodingFail;
        writer.print("{s}", .{s}) catch return Error.EncodingFail;
    }
    pub inline fn toCodePoint(icon: Icon) u21 {
        return codepoint_start + @intFromEnum(icon);
    }
    pub inline fn checkCodePoint(codepoint: u21) bool {
        return codepoint >= codepoint_start and codepoint < codepoint_end;
    }
    pub inline fn fromCodePoint(codepoint: u21) Icon {
        assert(checkCodePoint(codepoint));
        return @enumFromInt(codepoint - codepoint_start);
    }
    pub fn toUtf8(icon: Icon, buf: []u8) Error![]u8 {
        const codepoint = icon.toCodePoint();
        return fmtCodePoint(buf, codepoint);
    }
    pub fn fromUtf8(buf: []const u8) Error!?Icon {
        if (try parseCodePoint(buf)) |codepoint| {
            if (!checkCodePoint(codepoint)) return null;
            return fromCodePoint(codepoint);
        }
        return null;
    }
};

pub const Fmt = packed struct(u8) {
    pub const Tint = enum(u4) {
        white,
        red,
        green,
        blue,
        cyan,
        magenta,
        yellow,
        orange,
        purple,

        pub const colors = std.EnumArray(Tint, Colorf).init(.{
            .white = .white,
            .red = .red,
            .green = .green,
            .blue = .blue,
            .cyan = .cyan,
            .magenta = .magenta,
            .yellow = .yellow,
            .orange = .orange,
            .purple = .purple,
        });
        pub fn toColor(tint: Tint) Colorf {
            return colors.get(tint);
        }
    };
    tint: Tint = .white,
    _: u4 = 0,

    pub const codepoint_start: u21 = Icon.codepoint_end;
    pub const codepoint_end: u21 = codepoint_start + @typeInfo(Tint).@"enum".fields.len;

    pub fn format(self: Fmt, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) Error!void {
        _ = fmt;
        _ = options;
        var buf: [pua_codepoint_num_utf8_bytes]u8 = undefined;
        const s = self.toUtf8(&buf) catch return Error.EncodingFail;
        writer.print("{s}", .{s}) catch return Error.EncodingFail;
    }
    pub inline fn toCodePoint(fmt: Fmt) u21 {
        comptime {
            if (codepoint_end > pua_codepoint_end) {
                @compileError("Too many Fmt codepoints");
            }
        }
        const fmt_bits: u8 = @bitCast(fmt);
        return codepoint_start + utl.as(u21, fmt_bits);
    }
    pub inline fn checkCodePoint(codepoint: u21) bool {
        return codepoint >= codepoint_start and codepoint < codepoint_end;
    }
    pub inline fn fromCodePoint(codepoint: u21) Fmt {
        assert(checkCodePoint(codepoint));
        const bits: u21 = codepoint - codepoint_start;
        return @bitCast(utl.as(u8, bits));
    }
    pub fn toUtf8(fmt: Fmt, buf: []u8) Error![]u8 {
        const codepoint = fmt.toCodePoint();
        return fmtCodePoint(buf, codepoint);
    }
    pub fn fromUtf8(buf: []const u8) Error!?Fmt {
        if (try parseCodePoint(buf)) |codepoint| {
            if (!checkCodePoint(codepoint)) return null;
            return fromCodePoint(codepoint);
        }
        return null;
    }
};

pub const Part = union(enum) {
    fmt: Fmt,
    icon: Icon,
    text: []const u8,
};

pub fn fmtCodePoint(buf: []u8, codepoint: u21) Error![]u8 {
    const num = std.unicode.utf8Encode(codepoint, buf) catch |e| {
        Log.errorAndStackTrace(e);
        return Error.EncodingFail;
    };
    assert(num == pua_codepoint_num_utf8_bytes);
    return buf[0..num];
}

pub fn parseCodePoint(buf: []const u8) Error!?u21 {
    if (buf.len < pua_codepoint_num_utf8_bytes) return null;
    const num_bytes_in_codepoint = std.unicode.utf8ByteSequenceLength(buf[0]) catch return Error.DecodingFail;
    if (num_bytes_in_codepoint != pua_codepoint_num_utf8_bytes) return null;
    const codepoint = std.unicode.utf8Decode3(buf[0..3].*) catch |e| {
        Log.errorAndStackTrace(e);
        return Error.DecodingFail;
    };
    return codepoint;
}

pub fn parseFmtOrIconPart(buf: []const u8) Error!?Part {
    if (try parseCodePoint(buf)) |codepoint| {
        if (Icon.checkCodePoint(codepoint)) {
            return .{ .icon = Icon.fromCodePoint(codepoint) };
        } else if (Fmt.checkCodePoint(codepoint)) {
            return .{ .fmt = Fmt.fromCodePoint(codepoint) };
        }
    }
    return null;
}

pub fn partsToUtf8(buf: []u8, parts: []const Part) Error![]u8 {
    var idx: usize = 0;
    for (parts) |part| {
        switch (part) {
            .fmt => |fmt| {
                if (buf[idx..].len < pua_codepoint_num_utf8_bytes) {
                    return Error.NoSpaceLeft;
                }
                const b = try fmt.toUtf8(buf[idx..]);
                idx += b.len;
            },
            .icon => |icon| {
                if (buf[idx..].len < pua_codepoint_num_utf8_bytes) {
                    return Error.NoSpaceLeft;
                }
                const b = try icon.toUtf8(buf[idx..]);
                idx += b.len;
            },
            .text => |text| {
                if (buf[idx..].len < text.len) {
                    return Error.NoSpaceLeft;
                }
                @memcpy(buf[idx .. idx + text.len], text);
                idx += text.len;
            },
        }
    }
    return buf[0..idx];
}

const Utf8ToPartsIterator = struct {
    buf: []const u8,
    idx: usize = 0,

    pub fn next(self: *Utf8ToPartsIterator) ?Part {
        if (self.idx >= self.buf.len) return null;
        var curr_idx: usize = self.idx;

        while (curr_idx < self.buf.len) {
            const maybe_part = parseFmtOrIconPart(self.buf[curr_idx..]) catch |e| {
                Log.errorAndStackTrace(e);
                return null;
            };
            if (maybe_part) |part| {
                if (curr_idx == self.idx) {
                    self.idx += pua_codepoint_num_utf8_bytes;
                    return part;
                } else {
                    // text followed by icon; return the text and ignore the Part till next time
                    break;
                }
            } else {
                curr_idx += 1;
            }
        }
        assert(curr_idx > self.idx);
        const ret_buf = self.buf[self.idx..curr_idx];
        self.idx = curr_idx;
        return .{ .text = ret_buf };
    }
};

pub fn utf8ToPartsIterator(buf: []const u8) Utf8ToPartsIterator {
    return Utf8ToPartsIterator{
        .buf = buf,
    };
}

pub fn measureIconText(buf: []const u8) V2f {
    if (buf.len == 0) return .{};
    const plat = getPlat();
    const data = App.get().data;
    const icon_text_font = data.fonts.get(.seven_x_five);
    const icon_text_opt = draw.TextOpt{
        .font = icon_text_font,
        .size = icon_text_font.base_size,
        .smoothing = .none,
    };
    const line_height = utl.as(f32, icon_text_font.base_size);
    const line_spacing = 2;
    var it = utf8ToPartsIterator(buf);
    var dims = v2f(0, line_height);
    var curr_line_width: f32 = 0;
    var last_was_text: bool = false;
    while (it.next()) |part| {
        switch (part) {
            .fmt => |fmt| {
                _ = fmt;
            },
            .icon => |icon| {
                curr_line_width += 1; // pre-spacing (after text or icon)
                curr_line_width += data.text_icons.sprite_dims_cropped.?.get(icon).x;
                last_was_text = false;
            },
            .text => |text| {
                if (!last_was_text) curr_line_width += 1; // pre-spacing (after icon)
                last_was_text = true;
                var line_it = std.mem.splitScalar(u8, text, '\n');
                while (line_it.next()) |line| {
                    const line_sz = plat.measureText(line, icon_text_opt) catch V2f{};
                    curr_line_width += line_sz.x;
                    // new line was found
                    if (line_it.index) |_| {
                        dims.x = @max(dims.x, curr_line_width);
                        dims.y += line_height + line_spacing;
                        curr_line_width = 0;
                    }
                }
            },
        }
    }
    dims.x = @max(dims.x, curr_line_width);

    return dims;
}

pub fn unqRenderIconText(cmd_buf: *ImmUI.CmdBuf, buf: []const u8, pos: V2f, scaling: f32) Error!void {
    const plat = getPlat();
    const data = App.get().data;
    const icon_text_font = data.fonts.get(.seven_x_five);
    var icon_text_opt = draw.TextOpt{
        .font = icon_text_font,
        .size = icon_text_font.base_size * utl.as(u32, @round(scaling)),
        .smoothing = .none,
        .round_to_pixel = true,
        .color = .white,
    };
    const line_height = utl.as(f32, icon_text_font.base_size * utl.as(u32, @round(scaling)));
    const line_spacing: f32 = 2 * scaling;
    var it = utf8ToPartsIterator(buf);
    var curr_pos: V2f = pos;
    var last_was_text: bool = false;
    var fmt = Fmt{};
    while (it.next()) |part| {
        switch (part) {
            .fmt => |f| {
                fmt = f;
            },
            .icon => |icon| {
                curr_pos.x += 1 * scaling; // pre-spacing (after text or icon)
                const cropped_dims = data.text_icons.sprite_dims_cropped.?.get(icon);
                if (data.text_icons.getRenderFrame(icon)) |rf| {
                    cmd_buf.appendAssumeCapacity(.{ .texture = .{
                        .pos = curr_pos,
                        .texture = rf.texture,
                        .opt = .{
                            .src_dims = cropped_dims,
                            .src_pos = rf.pos.toV2f(),
                            .uniform_scaling = scaling,
                            .tint = fmt.tint.toColor(),
                            .round_to_pixel = true,
                        },
                    } });
                }
                curr_pos.x += cropped_dims.x * scaling;
                last_was_text = false;
            },
            .text => |text| {
                if (!last_was_text) curr_pos.x += 1 * scaling; // pre-spacing (icon)
                last_was_text = true;
                var line_it = std.mem.splitScalar(u8, text, '\n');
                icon_text_opt.color = fmt.tint.toColor();
                while (line_it.next()) |line| {
                    cmd_buf.appendAssumeCapacity(.{ .label = .{
                        .pos = curr_pos,
                        .text = ImmUI.initLabel(line),
                        .opt = icon_text_opt,
                    } });
                    const line_sz = plat.measureText(line, icon_text_opt) catch V2f{};
                    curr_pos.x += line_sz.x;
                    // new line was found
                    if (line_it.index) |_| {
                        curr_pos.x = pos.x;
                        curr_pos.y += line_height + line_spacing;
                    }
                }
            },
        }
    }
}
