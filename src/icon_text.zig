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
const getPlat = App.getPlat;
const getData = App.getData;
const Data = @import("Data.zig");
const ImmUI = @import("ImmUI.zig");

pub const IconText = struct {
    buf: []u8,
};

pub const Icon = enum {
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

    pub fn format(self: Icon, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) Error!void {
        _ = fmt;
        _ = options;
        var buf: [icon_num_utf8_bytes]u8 = undefined;
        const s = iconToUtf8(&buf, self) catch return Error.EncodingFail;
        writer.print("{s}", .{s}) catch return Error.EncodingFail;
    }
};

pub const Part = union(enum) {
    icon: Icon,
    text: []const u8,
};

pub const icon_codepoint_start: u21 = 0xE000;
pub const icon_codepoint_end: u21 = icon_codepoint_start + @typeInfo(Icon).@"enum".fields.len;
pub const icon_num_utf8_bytes = 3;

pub inline fn iconToCodePoint(icon: Icon) u21 {
    return icon_codepoint_start + @intFromEnum(icon);
}

pub inline fn codePointToIcon(codepoint: u21) Icon {
    assert(codepoint >= icon_codepoint_start and codepoint < icon_codepoint_end);
    return @enumFromInt(codepoint - icon_codepoint_start);
}

pub fn iconToUtf8(buf: []u8, icon: Icon) Error![]u8 {
    const codepoint = iconToCodePoint(icon);
    const num = std.unicode.utf8Encode(codepoint, buf) catch |e| {
        std.debug.print("ERROR: {any}\n", .{e});
        return Error.EncodingFail;
    };
    assert(num == icon_num_utf8_bytes);
    return buf[0..num];
}

pub fn utf8ToIcon(buf: []const u8) Error!?Icon {
    if (buf.len < icon_num_utf8_bytes) return null;
    const num_bytes_in_codepoint = std.unicode.utf8ByteSequenceLength(buf[0]) catch return Error.DecodingFail;
    if (num_bytes_in_codepoint != icon_num_utf8_bytes) return null;
    const codepoint = std.unicode.utf8Decode3(buf[0..3].*) catch |e| {
        std.debug.print("ERROR: {any}\n", .{e});
        return Error.DecodingFail;
    };
    if (codepoint < icon_codepoint_start or codepoint >= icon_codepoint_end) return null;

    const icon = codePointToIcon(codepoint);
    return icon;
}

pub fn partsToUtf8(buf: []u8, parts: []const Part) Error![]u8 {
    var idx: usize = 0;
    for (parts) |part| {
        switch (part) {
            .icon => |icon| {
                if (buf[idx..].len < icon_num_utf8_bytes) {
                    return Error.NoSpaceLeft;
                }
                _ = try iconToUtf8(buf[idx..], icon);
                idx += icon_num_utf8_bytes;
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
            const maybe_icon = utf8ToIcon(self.buf[curr_idx..]) catch |e| {
                std.debug.print("ERROR: {any}\n", .{e});
                return null;
            };
            if (maybe_icon) |icon| {
                if (curr_idx == self.idx) {
                    self.idx += icon_num_utf8_bytes;
                    return .{ .icon = icon };
                } else {
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

pub fn unqRenderIconText(cmd_buf: *ImmUI.CmdBuf, buf: []const u8, pos: V2f, scaling: f32, color: Colorf) Error!void {
    const plat = getPlat();
    const data = App.get().data;
    const icon_text_font = data.fonts.get(.seven_x_five);
    const icon_text_opt = draw.TextOpt{
        .font = icon_text_font,
        .size = icon_text_font.base_size * utl.as(u32, @round(scaling)),
        .smoothing = .none,
        .color = color,
    };
    const line_height = utl.as(f32, icon_text_font.base_size * utl.as(u32, @round(scaling)));
    const line_spacing: f32 = 2 * scaling;
    var it = utf8ToPartsIterator(buf);
    var curr_pos: V2f = pos;
    var last_was_text: bool = false;
    while (it.next()) |part| {
        switch (part) {
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
