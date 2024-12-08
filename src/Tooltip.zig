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
const Thing = @import("Thing.zig");
const TileMap = @import("TileMap.zig");
const Data = @import("Data.zig");
const Collision = @import("Collision.zig");
const sprites = @import("sprites.zig");
const ImmUI = @import("ImmUI.zig");
const Action = @import("Action.zig");
const Run = @import("Run.zig");
const StatusEffect = @import("StatusEffect.zig");
const Spell = @import("Spell.zig");
const icon_text = @import("icon_text.zig");
const Tooltip = @This();

pub const InfoKind = enum {
    status,
    damage,
    creature,
    keyword,
};
pub const Info = union(InfoKind) {
    status: StatusEffect.Kind,
    damage: Thing.Damage.Kind,
    creature: Thing.CreatureKind,
    keyword: Spell.Keyword,

    pub fn eql(a: Info, b: Info) bool {
        if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
        return switch (a) {
            .status => |kind| kind == b.status,
            .damage => |kind| kind == b.damage,
        };
    }
};
pub const Desc = utl.BoundedString(256);
pub const Title = utl.BoundedString(64);
pub const InfoArr = std.BoundedArray(Info, 8);

infos: InfoArr = .{},
title: Title = .{},
desc: Desc = .{},

pub const info_section_spacing: f32 = 4;

pub fn measureInfoContent(info: *const Info) V2f {
    var title_buf: [64]u8 = undefined;
    var desc_buf: [256]u8 = undefined;
    var title: []const u8 = "";
    var desc: []const u8 = "";

    switch (info.*) {
        .status => |kind| {
            title = StatusEffect.fmtName(&title_buf, kind) catch "";
            desc = StatusEffect.fmtDesc(&desc_buf, kind) catch "";
        },
        .damage => |kind| {
            title = Thing.Damage.Kind.fmtName(&title_buf, kind, false) catch "";
            desc = Thing.Damage.Kind.fmtDesc(&desc_buf, kind) catch "";
        },
        .creature => |kind| {
            title = kind.fmtName(&title_buf) catch "";
            desc = kind.fmtDesc(&desc_buf) catch "";
        },
        .keyword => |kind| {
            title = kind.fmtName(&title_buf) catch "";
            desc = kind.fmtDesc(&desc_buf) catch "";
        },
    }
    const title_dims = icon_text.measureIconText(title);
    const desc_dims = icon_text.measureIconText(desc);
    return v2f(
        @max(title_dims.x, desc_dims.x),
        title_dims.y + desc_dims.y + if (title_dims.y > 0 and desc_dims.y > 0) info_section_spacing else 0,
    );
}

pub const tooltip_padding = V2f.splat(5);

pub fn unqRenderInfo(info: *const Info, cmd_buf: *ImmUI.CmdBuf, pos: V2f, ui_scaling: f32) Error!void {
    var title_buf: [64]u8 = undefined;
    var desc_buf: [256]u8 = undefined;
    var title: []const u8 = "";
    var desc: []const u8 = "";
    const content_dims = measureInfoContent(info).scale(ui_scaling);
    const padding = tooltip_padding.scale(ui_scaling);
    const rect_dims = content_dims.add(padding.scale(2));
    const content_pos = pos.add(padding);

    try cmd_buf.append(.{ .rect = .{
        .pos = pos,
        .dims = rect_dims,
        .opt = .{
            .fill_color = Colorf.black.fade(0.9),
            .edge_radius = 0.2,
            .outline = .{ .color = .gray, .thickness = ui_scaling },
        },
    } });

    switch (info.*) {
        .status => |kind| {
            title = StatusEffect.fmtName(&title_buf, kind) catch "";
            desc = StatusEffect.fmtDesc(&desc_buf, kind) catch "";
        },
        .damage => |kind| {
            title = Thing.Damage.Kind.fmtName(&title_buf, kind, false) catch ""; // TODO aoe?
            desc = Thing.Damage.Kind.fmtDesc(&desc_buf, kind) catch "";
        },
        .creature => |kind| {
            title = kind.fmtName(&title_buf) catch "";
            desc = kind.fmtDesc(&desc_buf) catch "";
        },
        .keyword => |kind| {
            title = kind.fmtName(&title_buf) catch "";
            desc = kind.fmtDesc(&desc_buf) catch "";
        },
    }
    var curr_pos = content_pos;
    if (title.len > 0) {
        try icon_text.unqRenderIconText(cmd_buf, title, curr_pos, ui_scaling);
        const title_dims = icon_text.measureIconText(title);
        curr_pos.y += (title_dims.y + info_section_spacing) * ui_scaling;
    }
    try icon_text.unqRenderIconText(cmd_buf, desc, curr_pos, ui_scaling);
}

const tooltip_section_spacing: f32 = 4;

pub fn unqRender(tt: *const Tooltip, cmd_buf: *ImmUI.CmdBuf, pos: V2f, scaling: f32) Error!void {
    const plat = App.getPlat();
    const padding = tooltip_padding.scale(scaling);
    const section_spacing = tooltip_section_spacing * scaling;
    const info_tooltip_spacing: f32 = 1 * scaling;

    const title_dims = icon_text.measureIconText(tt.title.constSlice()).scale(scaling);
    const desc_dims = icon_text.measureIconText(tt.desc.constSlice()).scale(scaling);

    const main_content_dims = v2f(
        @max(title_dims.x, desc_dims.x),
        title_dims.y + desc_dims.y + if (title_dims.y > 0 and desc_dims.y > 0) section_spacing else 0,
    );
    const main_tooltip_dims = main_content_dims.add(padding.scale(2));

    // measure le infos
    var infos_dimses = std.BoundedArray(V2f, (InfoArr{}).buffer.len){};
    var total_infos_dims = V2f{};
    for (tt.infos.constSlice()) |*info| {
        const info_dims = measureInfoContent(info);
        const info_dims_scaled = info_dims.scale(scaling).add(padding.scale(2));
        infos_dimses.appendAssumeCapacity(info_dims_scaled);

        total_infos_dims.y += info_dims_scaled.y;
        total_infos_dims.x = @max(total_infos_dims.x, info_dims_scaled.x);
    }
    total_infos_dims.y += info_tooltip_spacing * @max(utl.as(f32, infos_dimses.len) - 1, 0);

    const entire_everything_dims = v2f(
        @max(main_tooltip_dims.x, total_infos_dims.x),
        main_tooltip_dims.y + if (infos_dimses.len > 0) info_tooltip_spacing + total_infos_dims.y else 0,
    );

    var adjusted_pos = pos;
    const bot_right = adjusted_pos.add(entire_everything_dims).add(padding);
    if (bot_right.x > plat.screen_dims_f.x) {
        adjusted_pos.x -= (bot_right.x - plat.screen_dims_f.x);
    }
    if (bot_right.y > plat.screen_dims_f.y) {
        adjusted_pos.y -= (bot_right.y - plat.screen_dims_f.y);
    }
    adjusted_pos = adjusted_pos.floor();

    // now drawawwwww
    // main tooltip
    try cmd_buf.append(.{ .rect = .{
        .pos = adjusted_pos,
        .dims = main_tooltip_dims,
        .opt = .{
            .fill_color = Colorf.black.fade(0.9),
            .edge_radius = 0.2,
            .outline = .{ .color = .gray, .thickness = scaling },
        },
    } });

    var content_curr_pos = adjusted_pos.add(padding);
    if (tt.title.len > 0) {
        try icon_text.unqRenderIconText(cmd_buf, tt.title.constSlice(), content_curr_pos, scaling);
        content_curr_pos.y += title_dims.y + section_spacing;
    }
    if (tt.desc.len > 0) {
        try icon_text.unqRenderIconText(cmd_buf, tt.desc.constSlice(), content_curr_pos, scaling);
        content_curr_pos.y += desc_dims.y + section_spacing;
    }

    var info_tooltip_pos = adjusted_pos.add(v2f(0, main_tooltip_dims.y + info_tooltip_spacing));
    for (tt.infos.constSlice(), 0..) |*info, i| {
        try unqRenderInfo(info, cmd_buf, info_tooltip_pos, scaling);
        info_tooltip_pos.y += infos_dimses.get(i).y + info_tooltip_spacing;
    }
}
