const std = @import("std");
const assert = std.debug.assert;
const utl = @import("util.zig");

pub const Platform = @import("raylib.zig");
const core = @import("core.zig");
const Error = core.Error;
const Key = core.Key;
const draw = @import("draw.zig");
const Colorf = draw.Colorf;
const geom = @import("geometry.zig");
const V2f = @import("V2f.zig");
const v2f = V2f.v2f;
const V2i = @import("V2i.zig");
const v2i = V2i.v2i;

const Run = @This();
const App = @import("App.zig");
const getPlat = App.getPlat;
const sprites = @import("sprites.zig");
const ImmUI = @import("ImmUI.zig");
const icon_text = @import("icon_text.zig");

// render text at the right size to fit into a rect, with padding
pub fn textInRect(topleft: V2f, dims: V2f, rect_opt: draw.PolyOpt, text_padding: V2f, comptime fmt: []const u8, args: anytype, text_opt: draw.TextOpt) Error!void {
    const plat = App.getPlat();
    const half_dims = dims.scale(0.5);
    const text_rel_pos = if (text_opt.center) half_dims else text_padding;
    const text_dims = dims.sub(text_padding.scale(2));
    assert(text_dims.x > 0 and text_dims.y > 0);
    const text = try utl.bufPrintLocal(fmt, args);
    const fitted_text_opt = try plat.fitTextToRect(text_dims, text, text_opt);
    plat.rectf(topleft, dims, rect_opt);
    try plat.textf(topleft.add(text_rel_pos), fmt, args, fitted_text_opt);
}

pub fn renderToolTip(title: []const u8, body: []const u8, pos: V2f) Error!void {
    const plat = App.getPlat();
    const title_opt = draw.TextOpt{
        .color = .white,
        .size = 25,
    };
    const title_dims = try plat.measureText(title, title_opt);
    const body_opt = draw.TextOpt{
        .color = .white,
        .size = 20,
    };
    const body_dims = try plat.measureText(body, body_opt);
    const text_dims = v2f(@max(title_dims.x, body_dims.x), title_dims.y + body_dims.y);
    const modal_dims = text_dims.add(v2f(10, 15));
    var adjusted_pos = pos;
    const bot_right = adjusted_pos.add(modal_dims);
    const native_cropped_rect_bot_right = plat.native_rect_cropped_offset.add(plat.native_rect_cropped_dims);
    if (bot_right.x > native_cropped_rect_bot_right.x) {
        adjusted_pos.x -= (bot_right.x - native_cropped_rect_bot_right.x);
    }
    if (bot_right.y > native_cropped_rect_bot_right.y) {
        adjusted_pos.y -= (bot_right.y - native_cropped_rect_bot_right.y);
    }

    plat.rectf(adjusted_pos, modal_dims, .{ .fill_color = Colorf.black.fade(0.8) });
    var text_pos = adjusted_pos.add(v2f(5, 5));
    try plat.textf(text_pos, "{s}", .{title}, title_opt);
    text_pos.y += 5 + title_dims.y;
    try plat.textf(text_pos, "{s}", .{body}, body_opt);
}

pub const Modal = struct {
    rect: geom.Rectf = .{},
    poly_opt: draw.PolyOpt = .{},
    title_rel_pos: V2f = .{},
    title: utl.BoundedString(128) = .{},
    text_opt: draw.TextOpt = .{},
    padding: V2f = .{},

    pub fn toRectf(self: Modal) geom.Rectf {
        return self.rect;
    }
    pub fn getInnerRect(self: Modal) geom.Rect {
        return geom.Rectf{
            .pos = self.rect.pos.add(self.padding),
            .dims = self.rect.dims.sub(self.padding.scale(2)),
        };
    }
    pub fn render(self: Modal) Error!void {
        const plat = App.getPlat();
        plat.rectf(self.rect.pos, self.rect.dims, self.poly_opt);
        try plat.textf(self.rect.pos.add(self.title_rel_pos), "{s}", .{self.title.constSlice()}, self.text_opt);
    }
};

pub const ClickableRect = struct {
    rect: geom.Rectf = .{},

    pub fn toRectf(self: ClickableRect) geom.Rectf {
        return self.rect;
    }
    pub fn isHovered(self: ClickableRect) bool {
        const plat = App.getPlat();
        return geom.pointIsInRectf(plat.getMousePosScreen(), self.rect);
    }
    pub fn isClicked(self: ClickableRect) bool {
        const plat = App.getPlat();
        return self.isHovered() and plat.input_buffer.mouseBtnIsJustPressed(.left);
    }
};

pub const Button = struct {
    clickable_rect: ClickableRect = .{},
    poly_opt: draw.PolyOpt = .{
        .fill_color = Colorf.red.fade(0.5),
    },
    text: utl.BoundedString(64) = .{},
    text_padding: V2f = v2f(20, 20),
    text_rel_pos: V2f = .{},
    text_opt: draw.TextOpt = .{
        .color = Colorf.black,
        .center = true,
    },
    pub fn toRectf(self: Button) geom.Rectf {
        return self.clickable_rect.toRectf();
    }
    pub fn isHovered(self: Button) bool {
        return self.clickable_rect.isHovered();
    }
    pub fn isClicked(self: Button) bool {
        return self.clickable_rect.isClicked();
    }
    pub fn render(self: Button) Error!void {
        const plat = App.getPlat();
        const rect = self.clickable_rect.rect;
        plat.rectf(rect.pos, rect.dims, self.poly_opt);
        if (self.isHovered()) {
            var selected_poly_opt = self.poly_opt;
            selected_poly_opt.fill_color = null;
            selected_poly_opt.outline = .{ .color = Colorf.red, .thickness = 3 };
            plat.rectf(rect.pos.sub(v2f(5, 5)), rect.dims.add(v2f(10, 10)), selected_poly_opt);
        }
        try plat.textf(rect.pos.add(self.text_rel_pos), "{s}", .{self.text.constSlice()}, self.text_opt);
    }
};

pub fn sectorTimer(pos: V2f, radius: f32, timer: utl.TickCounter, poly_opt: draw.PolyOpt) void {
    const plat = App.getPlat();
    const rads = timer.remapTo0_1() * utl.tau;
    plat.sectorf(pos, radius, 0, rads, poly_opt);
    const secs_left = utl.as(u32, @ceil(core.fups_to_secsf(timer.num_ticks - timer.curr_tick)));
    plat.textf(pos, "{}", .{secs_left}, .{
        .center = true,
        .color = .white,
        .size = utl.as(u32, radius * 1.5),
    }) catch {};
}

pub fn unqSectorTimer(cmd_buf: *ImmUI.CmdBuf, pos: V2f, radius: f32, timer: *const utl.TickCounter, poly_opt: draw.PolyOpt) void {
    const rads = timer.remapTo0_1() * utl.tau;
    cmd_buf.append(.{ .sector = .{
        .pos = pos,
        .radius = radius,
        .start_ang_rads = 0,
        .end_ang_rads = rads,
        .opt = poly_opt,
    } }) catch @panic("Fail to append sector cmd");

    const secs_left = utl.as(u32, @ceil(core.fups_to_secsf(timer.num_ticks - timer.curr_tick)));
    const secs_left_str = utl.bufPrintLocal("{}", .{secs_left}) catch @panic("Fail to format secs_left");
    cmd_buf.append(.{ .label = .{
        .pos = pos,
        .text = ImmUI.initLabel(secs_left_str),
        .opt = .{
            .center = true,
            .color = .white,
            .size = utl.as(u32, radius * 1.5),
        },
    } }) catch @panic("Fail to append label cmd");
}

pub fn textButton(cmd_buf: *ImmUI.CmdBuf, pos: V2f, str: []const u8, dims: V2f) bool {
    const plat = getPlat();
    const mouse_pos = plat.getMousePosScreen();
    const hovered = geom.pointIsInRectf(mouse_pos, .{ .pos = pos, .dims = dims });
    const clicked = hovered and plat.input_buffer.mouseBtnIsJustPressed(.left);
    cmd_buf.append(.{
        .rect = .{
            .pos = pos,
            .dims = dims,
            .opt = .{
                .fill_color = .orange,
                .outline = if (hovered) .{ .color = .red, .thickness = 5 } else null,
            },
        },
    }) catch @panic("Fail to append rect cmd");
    const font = App.get().data.fonts.get(.pixeloid);
    cmd_buf.append(.{
        .label = .{
            .pos = pos.add(dims.scale(0.5)),
            .text = ImmUI.initLabel(str),
            .opt = .{
                .center = true,
                .color = .black,
                .size = font.base_size * 2,
                .font = font,
                .smoothing = .none,
            },
        },
    }) catch @panic("Fail to append text cmd");
    return clicked;
}
