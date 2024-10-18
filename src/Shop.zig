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

const Product = struct {
    kind: union(enum) {
        spell: Spell,
        item: Item,
    },
    price: union(enum) {
        gold: i32,
    },
};

const ProductSlot = struct {
    product: ?Product,
    rect: menuUI.ClickableRect,
};

render_texture: Platform.RenderTexture2D,
products: std.BoundedArray(ProductSlot, 12) = .{},
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

    {
        const max_num_spells = 4;
        const num_spells = 4;
        const spell_width: f32 = 250;
        const spell_spacing = 25;
        const spell_product_dims = v2f(spell_width, spell_width / 0.7);
        const spells_center = v2f(plat.screen_dims_f.x * 0.5, 100 + spell_product_dims.y * 0.5);
        const spells_bottom_y = spells_center.y + spell_product_dims.y * 0.5;
        var spells = std.BoundedArray(Spell, max_num_spells){};
        spells.resize(num_spells) catch unreachable;
        const num_spells_generated = Spell.makeShopSpells(ret.rng.random(), spells.slice());
        spells.resize(num_spells_generated) catch unreachable;
        var spell_rects = std.BoundedArray(geom.Rectf, max_num_spells){};
        spell_rects.resize(num_spells_generated) catch unreachable;
        gameUI.layoutRectsFixedSize(
            spells.len,
            spell_product_dims,
            spells_center,
            .{
                .direction = .horizontal,
                .space_between = spell_spacing,
            },
            spell_rects.slice(),
        );
        for (spells.constSlice(), 0..) |spell, i| {
            const rect = spell_rects.get(i);
            ret.products.append(.{
                .product = .{
                    .kind = .{ .spell = spell },
                    .price = .{ .gold = 10 },
                },
                .rect = .{ .dims = rect.dims, .pos = rect.pos },
            }) catch unreachable;
        }

        const max_num_items = 4;
        const num_items = 3;
        const item_width: f32 = 250;
        const item_spacing = 25;
        const item_product_dims = v2f(item_width, item_width / 0.7);
        const items_center = v2f(plat.screen_dims_f.x * 0.5, spells_bottom_y + 50 + item_product_dims.y * 0.5);
        var items = std.BoundedArray(Item, max_num_items){};
        items.resize(num_items) catch unreachable;
        const num_items_generated = Item.makeShopItems(ret.rng.random(), items.slice());
        items.resize(num_items_generated) catch unreachable;
        var item_rects = std.BoundedArray(geom.Rectf, max_num_items){};
        item_rects.resize(num_items_generated) catch unreachable;
        gameUI.layoutRectsFixedSize(
            items.len,
            item_product_dims,
            items_center,
            .{
                .direction = .horizontal,
                .space_between = item_spacing,
            },
            item_rects.slice(),
        );
        for (items.constSlice(), 0..) |item, i| {
            const rect = item_rects.get(i);
            ret.products.append(.{
                .product = .{
                    .kind = .{ .item = item },
                    .price = .{ .gold = 30 },
                },
                .rect = .{ .dims = rect.dims, .pos = rect.pos },
            }) catch unreachable;
        }
    }

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

pub fn canBuy(run: *const Run, product: Product) bool {
    const price = product.price.gold;
    if (run.gold < price) return false;
    switch (product.kind) {
        .spell => |_| {
            if (run.deck.len >= run.deck.buffer.len) return false;
        },
        .item => |_| {
            if (run.slots_init_params.items.len >= run.slots_init_params.items.buffer.len) return false;
            for (run.slots_init_params.items.constSlice()) |maybe_item| {
                if (maybe_item == null) break;
            } else {
                return false;
            }
        },
    }
    return true;
}

pub fn update(self: *Shop, run: *const Run) Error!?Product {
    const plat = getPlat();
    _ = plat;
    var ret: ?Product = null;

    for (self.products.slice()) |*slot| {
        if (slot.product == null) continue;
        const product = slot.product.?;
        var hovered_crect = slot.rect;
        if (hovered_crect.isHovered()) {
            const new_dims = slot.rect.dims.scale(1.1);
            const new_pos = slot.rect.pos.sub(new_dims.sub(slot.rect.dims).scale(0.5));
            hovered_crect.pos = new_pos;
            hovered_crect.dims = new_dims;
        }
        if (hovered_crect.isClicked()) {
            if (canBuy(run, product)) {
                ret = product;
                slot.product = null;
                break;
            }
        }
    }

    if (self.proceed_button.isClicked()) {
        self.state = .done;
    }
    return ret;
}

pub fn render(self: *Shop, run: *Run) Error!void {
    const plat = getPlat();
    _ = run;

    plat.startRenderToTexture(self.render_texture);
    plat.clear(Colorf.rgb(0.2, 0.2, 0.2));
    plat.setBlend(.render_tex_alpha);

    try plat.textf(v2f(plat.screen_dims_f.x * 0.5, 50), "Shoppy woppy", .{}, .{ .center = true, .color = .white, .size = 45 });

    for (self.products.constSlice()) |slot| {
        plat.rectf(slot.rect.pos, slot.rect.dims, .{ .fill_color = .darkgray });
        var hovered_crect = slot.rect;
        if (hovered_crect.isHovered()) {
            const new_dims = slot.rect.dims.scale(1.1);
            const new_pos = slot.rect.pos.sub(new_dims.sub(slot.rect.dims).scale(0.5));
            hovered_crect.pos = new_pos;
            hovered_crect.dims = new_dims;
        }
        if (slot.product == null) continue;
        const product = slot.product.?;
        switch (product.kind) {
            .spell => |spell| {
                try spell.renderInfo(hovered_crect);
            },
            .item => |item| {
                try item.renderInfo(hovered_crect);
            },
        }
        const price_pos = hovered_crect.pos.add(hovered_crect.dims).sub(v2f(50, 40));
        try plat.textf(price_pos, "${}", .{product.price.gold}, .{ .center = true, .color = .yellow, .size = 40 });
    }

    try self.proceed_button.render();

    plat.endRenderToTexture();
}
