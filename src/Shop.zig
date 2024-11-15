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
const ImmUI = @import("ImmUI.zig");
const Shop = @This();

pub const SpellOrItem = union(enum) {
    spell: Spell,
    item: Item,
};

pub const Product = struct {
    kind: SpellOrItem,
    price: union(enum) {
        gold: i32,
    } = .{ .gold = 10 },
};

const ProductSlot = struct {
    product: ?Product,
    crect: menuUI.ClickableRect,
};

render_texture: Platform.RenderTexture2D,
products: std.BoundedArray(ProductSlot, 12) = .{},
proceed_button: menuUI.Button,
rng: std.Random.DefaultPrng,
state: enum {
    shopping,
    done,
} = .shopping,
imm_ui: struct {
    commands: ImmUI.CmdBuf = .{},
} = .{},

pub fn init(seed: u64) Error!Shop {
    const plat = App.getPlat();

    const proceed_btn_dims = v2f(120, 70);
    const proceed_btn_center = v2f(core.native_dims_f.x - proceed_btn_dims.x - 80, core.native_dims_f.y - proceed_btn_dims.y - 140);
    var proceed_btn = menuUI.Button{
        .clickable_rect = .{ .rect = .{
            .pos = proceed_btn_center.sub(proceed_btn_dims.scale(0.5)),
            .dims = proceed_btn_dims,
        } },
        .text_padding = v2f(10, 10),
        .poly_opt = .{ .fill_color = .orange },
        .text_opt = .{ .center = true, .color = .black, .size = 30 },
        .text_rel_pos = proceed_btn_dims.scale(0.5),
    };
    proceed_btn.text = @TypeOf(proceed_btn.text).init("Proceed") catch unreachable;

    var ret = Shop{
        .render_texture = plat.createRenderTexture("shop", core.native_dims),
        .proceed_button = proceed_btn,
        .rng = std.Random.DefaultPrng.init(seed),
    };

    {
        const max_num_spells = 4;
        const num_spells = 4;
        const spell_width: f32 = 150;
        const spell_spacing = 25;
        const spell_product_dims = v2f(spell_width, spell_width / 0.7);
        const spells_center = v2f(core.native_dims_f.x * 0.5, 100 + spell_product_dims.y * 0.5);
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
                .crect = .{ .rect = .{ .dims = rect.dims, .pos = rect.pos } },
            }) catch unreachable;
        }

        const max_num_items = 4;
        const num_items = 3;
        const item_width: f32 = 150;
        const item_spacing = 25;
        const item_product_dims = v2f(item_width, item_width / 0.7);
        const items_center = v2f(core.native_dims_f.x * 0.5, spells_bottom_y + 50 + item_product_dims.y * 0.5);
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
                    .price = .{ .gold = 20 },
                },
                .crect = .{ .rect = .{ .dims = rect.dims, .pos = rect.pos } },
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

pub fn canBuy(run: *const Run, product: *const Product) bool {
    const price = product.price.gold;
    return run.gold >= price and run.canPickupProduct(product);
}

pub fn update(self: *Shop, run: *const Run) Error!?Product {
    self.imm_ui.commands.clear();
    var ret: ?Product = null;

    for (self.products.slice()) |*slot| {
        try self.imm_ui.commands.append(.{ .rect = .{
            .pos = slot.crect.rect.pos,
            .dims = slot.crect.rect.dims,
            .opt = .{
                .fill_color = Colorf.rgb(0.07, 0.05, 0.05),
            },
        } });
        if (slot.product == null) continue;
        const product: *Product = &slot.product.?;
        var hovered_rect = slot.crect.rect;
        if (slot.crect.isHovered()) {
            const new_dims = hovered_rect.dims.scale(1.1);
            const new_pos = hovered_rect.pos.sub(new_dims.sub(hovered_rect.dims).scale(0.5));
            hovered_rect.pos = new_pos;
            hovered_rect.dims = new_dims;
        }
        // renderr
        switch (product.kind) {
            .spell => |spell| {
                spell.unqRenderCard(&self.imm_ui.commands, hovered_rect.pos, null);
            },
            .item => |item| {
                try item.unqRenderIcon(&self.imm_ui.commands, hovered_rect);
            },
        }
        const price_pos = hovered_rect.pos.add(hovered_rect.dims).sub(v2f(50, 40));
        const price_str = try u.bufPrintLocal("${}", .{product.price.gold});
        try self.imm_ui.commands.append(.{ .label = .{
            .pos = price_pos,
            .text = ImmUI.Command.LabelString.initTrunc(price_str),
            .opt = .{
                .center = true,
                .color = .yellow,
                .size = 30,
            },
        } });
        // buyy
        if (slot.crect.isClicked()) {
            if (canBuy(run, product)) {
                ret = product.*;
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

pub fn render(self: *Shop, run: *Run, native_render_texture: Platform.RenderTexture2D) Error!void {
    _ = run;
    const plat = getPlat();

    plat.startRenderToTexture(native_render_texture);
    plat.clear(Colorf.rgb(0.2, 0.2, 0.2));
    plat.setBlend(.render_tex_alpha);

    try ImmUI.render(&self.imm_ui.commands);

    try plat.textf(v2f(core.native_dims_f.x * 0.5, 50), "Shoppy woppy", .{}, .{ .center = true, .color = .white, .size = 45 });

    try self.proceed_button.render();
}
