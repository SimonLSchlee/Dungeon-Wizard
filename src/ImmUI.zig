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

const ImmUI = @This();
const App = @import("App.zig");
const getPlat = App.getPlat;

pub const Command = union(enum) {
    pub const LabelString = utl.BoundedString(128);
    pub const Panel = struct {
        // init
        center_pos: V2f = .{},
        padding: V2f = .{},
        v_spacing: f32 = 0,
        opt: draw.PolyOpt = .{},
        // running
        curr_pos: V2f = .{},
        pos: V2f = .{},
        dims: V2f = .{},
    };

    panel_start: Panel,
    panel_end,
    rect: struct {
        pos: V2f,
        dims: V2f,
        opt: draw.PolyOpt,
        pub fn render(self: *const @This()) Error!void {
            const plat = getPlat();
            plat.rectf(self.pos, self.dims, self.opt);
        }
    },
    sector: struct {
        pos: V2f,
        radius: f32,
        start_ang_rads: f32,
        end_ang_rads: f32,
        opt: draw.PolyOpt,
        pub fn render(self: *const @This()) Error!void {
            const plat = getPlat();
            plat.sectorf(self.pos, self.radius, self.start_ang_rads, self.end_ang_rads, self.opt);
        }
    },
    label: struct {
        pos: V2f,
        text: LabelString,
        opt: draw.TextOpt,
        pub fn render(self: *const @This()) Error!void {
            const plat = getPlat();
            try plat.textf(self.pos, "{s}", .{self.text.constSlice()}, self.opt);
        }
    },
    texture: struct {
        pos: V2f,
        texture: Platform.Texture2D,
        opt: draw.TextureOpt,
        pub fn render(self: *const @This()) Error!void {
            const plat = getPlat();
            plat.texturef(self.pos, self.texture, self.opt);
        }
    },
};

pub const CmdBuf = std.BoundedArray(Command, 256);

pub fn render(cmd_buf: *const CmdBuf) Error!void {
    for (cmd_buf.slice()) |*command| {
        switch (command.*) {
            inline else => |*c| {
                const C = @TypeOf(c.*);
                if (std.meta.hasMethod(C, "render")) {
                    try C.render(c);
                }
            },
        }
    }
}
