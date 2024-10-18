const std = @import("std");
const assert = std.debug.assert;
const u = @import("util.zig");

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
const debug = @import("debug.zig");

const App = @import("App.zig");
const getPlat = App.getPlat;
const Room = @import("Room.zig");
const Spell = @import("Spell.zig");
const Thing = @import("Thing.zig");
const Data = @import("Data.zig");
const Run = @import("Run.zig");
const PackedRoom = @import("PackedRoom.zig");
const menuUI = @import("menuUI.zig");
const gameUI = @import("gameUI.zig");
const Item = @import("Item.zig");
const Shop = @This();

const ShopProduct = struct {
    kind: union(enum) {
        spell: Spell,
        item: Item,
    },
    price: union(enum) {
        gold: i32,
    },
    rect: menuUI.ClickableRect,
};

render_texture: Platform.RenderTexture2D,
items: std.BoundedArray(ShopProduct, 12) = .{},
proceed_button: menuUI.Button,
rng: std.Random.DefaultPrng,
state: enum {
    shopping,
    done,
} = .shopping,

pub fn init(seed: u64) Error!Shop {
    const plat = App.getPlat();

    const proceed_btn_dims = v2f(120, 70);
    const proceed_btn_center = v2f(plat.screen_dims_f.x - proceed_btn_dims.x - 80, plat.screen_dims_f.y - proceed_btn_dims.y - 140);
    var proceed_btn = menuUI.Button{
        .rect = .{
            .pos = proceed_btn_center.sub(proceed_btn_dims.scale(0.5)),
            .dims = proceed_btn_dims,
        },
        .text_padding = v2f(10, 10),
        .poly_opt = .{ .fill_color = .orange },
        .text_opt = .{ .center = true, .color = .black, .size = 30 },
        .text_rel_pos = proceed_btn_dims.scale(0.5),
    };
    proceed_btn.text = @TypeOf(proceed_btn.text).init("Proceed") catch unreachable;

    var ret = Shop{
        .render_texture = plat.createRenderTexture("shop", plat.screen_dims),
        .proceed_button = proceed_btn,
        .rng = std.Random.DefaultPrng.init(seed),
    };

    // TODO
    ret.items.len = 0;

    return ret;
}

pub fn deinit(self: *Shop) void {
    const plat = App.getPlat();
    plat.destroyRenderTexture(self.render_texture);
}

pub fn reset(self: *Shop) Error!*Shop {
    self.deinit();
    var rng = std.Random.DefaultPrng.init(u.as(u64, std.time.microTimestamp()));
    const seed = rng.random().int(u64);
    self.* = try init(seed);
    return self;
}

pub fn update(self: *Shop, run: *Run) Error!void {
    const plat = getPlat();
    _ = plat;
    _ = run;
    if (self.proceed_button.isClicked()) {
        self.state = .done;
    }
}

pub fn render(self: *Shop, run: *Run) Error!void {
    const plat = getPlat();
    _ = run;

    plat.startRenderToTexture(self.render_texture);
    plat.clear(Colorf.rgb(0.4, 0.4, 0.4));
    plat.setBlend(.render_tex_alpha);

    try self.proceed_button.render();

    plat.endRenderToTexture();
}
