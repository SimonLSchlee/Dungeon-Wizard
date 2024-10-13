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

pub const ClickableRect = struct {
    pos: V2f = .{},
    dims: V2f = v2f(200, 100),

    pub fn toRectf(self: ClickableRect) geom.Rectf {
        return .{ .pos = self.pos, .dims = self.dims };
    }
    pub fn isHovered(self: ClickableRect) bool {
        const plat = App.getPlat();
        return geom.pointIsInRectf(plat.mousePosf(), self.toRectf());
    }
    pub fn isClicked(self: ClickableRect) bool {
        const plat = App.getPlat();
        return self.isHovered() and plat.input_buffer.mouseBtnIsJustPressed(.left);
    }
};

pub const Button = struct {
    rect: ClickableRect = .{},
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
        return self.rect.toRectf();
    }
    pub fn isHovered(self: Button) bool {
        return self.rect.isHovered();
    }
    pub fn isClicked(self: Button) bool {
        return self.rect.isClicked();
    }
    pub fn render(self: Button) Error!void {
        const plat = App.getPlat();
        const rect = self.rect;
        plat.rectf(rect.pos, rect.dims, self.poly_opt);
        if (self.isHovered()) {
            var selected_poly_opt = self.poly_opt;
            selected_poly_opt.fill_color = null;
            selected_poly_opt.outline_thickness = 3;
            selected_poly_opt.outline_color = Colorf.red;
            plat.rectf(rect.pos.sub(v2f(5, 5)), rect.dims.add(v2f(10, 10)), selected_poly_opt);
        }
        try plat.textf(rect.pos.add(self.text_rel_pos), "{s}", .{self.text.constSlice()}, self.text_opt);
    }
};
