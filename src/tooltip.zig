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
const icon_text = @import("icon_text.zig");

pub const InfoKind = enum {
    status,
    damage,
};

pub const Info = union(enum) {
    status: StatusEffect.Kind,
    damage: Thing.Damage.Kind,

    pub fn eql(a: Info, b: Info) bool {
        if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
        return switch (a) {
            .status => |kind| kind == b.status,
            .damage => |kind| kind == b.damage,
        };
    }
};

pub const tooltip_padding = v2f(10, 10);
pub const tooltip_section_spacing: f32 = 8;

pub fn measureToolTipContent(info: *const Info) V2f {
    var buf: [128]u8 = undefined;
    var title_dims = V2f{};
    var desc_dims = V2f{};
    switch (info.*) {
        .status => |kind| {
            const title = StatusEffect.fmtName(&buf, kind) catch "";
            title_dims = icon_text.measureIconText(title);
            const desc = StatusEffect.fmtDesc(&buf, kind) catch "";
            desc_dims = icon_text.measureIconText(desc);
        },
        .damage => |kind| {
            const title = Thing.Damage.Kind.fmtName(&buf, kind, false) catch "";
            title_dims = icon_text.measureIconText(title);
            const desc = Thing.Damage.Kind.fmtDesc(&buf, kind) catch "";
            desc_dims = icon_text.measureIconText(desc);
        },
    }
    return v2f(
        @max(title_dims.x, desc_dims.x),
        title_dims.y + desc_dims.y + tooltip_section_spacing,
    );
}

pub fn unqRenderToolTip(info: *const Info, cmd_buf: *ImmUI.CmdBuf, pos: V2f, ui_scaling: f32) Error!void {
    var buf: [128]u8 = undefined;
    const content_dims = measureToolTipContent(info).scale(ui_scaling);
    const rect_dims = content_dims.add(tooltip_padding.scale(2));
    const content_pos = pos.add(tooltip_padding);

    try cmd_buf.append(.{ .rect = .{
        .pos = pos,
        .dims = rect_dims,
        .opt = .{
            .fill_color = Colorf.black.fade(0.9),
            .edge_radius = 0.2,
        },
    } });
    switch (info.*) {
        .status => |kind| {
            var curr_pos = content_pos;
            const title = StatusEffect.fmtName(&buf, kind) catch "";
            const title_dims = icon_text.measureIconText(title).scale(ui_scaling);
            try icon_text.unqRenderIconText(cmd_buf, title, curr_pos, ui_scaling, .white);
            curr_pos.y += title_dims.y + tooltip_section_spacing;
            const desc = StatusEffect.fmtDesc(&buf, kind) catch "";
            try icon_text.unqRenderIconText(cmd_buf, desc, curr_pos, ui_scaling, .white);
        },
        .damage => |kind| {
            var curr_pos = content_pos;
            const title = Thing.Damage.Kind.fmtName(&buf, kind, false) catch ""; // TODO aoe?
            const title_dims = icon_text.measureIconText(title).scale(ui_scaling);
            try icon_text.unqRenderIconText(cmd_buf, title, curr_pos, ui_scaling, .white);
            curr_pos.y += title_dims.y + tooltip_section_spacing;
            const desc = Thing.Damage.Kind.fmtDesc(&buf, kind) catch "";
            try icon_text.unqRenderIconText(cmd_buf, desc, curr_pos, ui_scaling, .white);
        },
    }
}
