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
const debug = @import("debug.zig");

const App = @import("App.zig");
const getPlat = App.getPlat;
const Room = @import("Room.zig");
const Spell = @import("Spell.zig");
const Thing = @import("Thing.zig");
const Data = @import("Data.zig");
const Run = @import("Run.zig");
const menuUI = @import("menuUI.zig");
const gameUI = @import("gameUI.zig");
const Item = @import("Item.zig");
const ImmUI = @import("ImmUI.zig");
const icon_text = @import("icon_text.zig");
const Shop = @This();

const max_num_spells = 4;
const num_spells = 4;
const spells_spacing: f32 = 16;

const max_num_items = 4;
const num_items = 3;
const items_spacing: f32 = 10;

const slot_margin: f32 = 10;

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
    rect: geom.Rectf = .{},
    long_hover: menuUI.LongHover = .{},
};

spells: std.BoundedArray(ProductSlot, max_num_spells) = .{},
items: std.BoundedArray(ProductSlot, max_num_items) = .{},
rng: std.Random.DefaultPrng,
state: enum {
    shopping,
    done,
} = .shopping,

pub fn init(seed: u64, run: *Run) Error!Shop {
    var ret = Shop{
        .rng = std.Random.DefaultPrng.init(seed),
    };

    var spells_buf: [max_num_spells]Spell = undefined;
    const spells_generated = Spell.makeShopSpells(ret.rng.random(), run.mode, spells_buf[0..num_spells]);
    for (spells_generated) |spell| {
        ret.spells.appendAssumeCapacity(.{
            .product = .{
                .kind = .{ .spell = spell },
                .price = .{ .gold = spell.getShopPrice(ret.rng.random()) },
            },
        });
    }

    var items_buf: [max_num_items]Item = undefined;
    const items_generated = Item.makeShopItems(ret.rng.random(), run.mode, items_buf[0..num_items]);
    for (items_generated) |item| {
        ret.items.appendAssumeCapacity(.{
            .product = .{
                .kind = .{ .item = item },
                .price = .{ .gold = item.getShopPrice(ret.rng.random()) },
            },
        });
    }

    return ret;
}

pub fn deinit(self: *Shop) void {
    _ = self;
}

pub fn reset(self: *Shop, run: *Run) Error!*Shop {
    self.deinit();
    var rng = std.Random.DefaultPrng.init(utl.as(u64, std.time.microTimestamp()));
    const seed = rng.random().int(u64);
    self.* = try init(seed, run);
    return self;
}

pub fn canBuy(run: *Run, product: *const Product) bool {
    const price = product.price.gold;
    return run.gold >= price and run.canPickupProduct(product);
}

fn unqProductSlot(cmd_buf: *ImmUI.CmdBuf, tooltip_buf: *ImmUI.CmdBuf, slot: *ProductSlot, run: *Run) Error!bool {
    const plat = getPlat();
    const ui_scaling: f32 = plat.ui_scaling;
    var ret: bool = false;

    const mouse_pos = plat.getMousePosScreen();
    const hovered = geom.pointIsInRectf(mouse_pos, slot.rect);
    const clicked = hovered and plat.input_buffer.mouseBtnIsJustPressed(.left);
    // TODO anything else here?
    const slot_enabled = slot.product != null;
    const can_buy = slot_enabled and canBuy(run, &slot.product.?);
    const bg_color = Colorf.rgb(0.17, 0.15, 0.15);
    var slot_contents_pos = slot.rect.pos.add(V2f.splat(slot_margin));

    // background rect
    if (can_buy and hovered) {
        // TODO animate
        slot_contents_pos = slot_contents_pos.add(v2f(0, -3 * ui_scaling));
    }
    cmd_buf.append(.{ .rect = .{
        .pos = slot.rect.pos,
        .dims = slot.rect.dims,
        .opt = .{
            .fill_color = bg_color,
            .edge_radius = 0.2,
        },
    } }) catch @panic("Fail to append rect cmd");

    // slot contents
    if (slot_enabled) {
        const product = slot.product.?;

        ret = can_buy and hovered and clicked;
        switch (product.kind) {
            .spell => |*spell| {
                spell.unqRenderCard(cmd_buf, slot_contents_pos, null, ui_scaling);
                if (slot.long_hover.update(hovered)) {
                    try spell.unqRenderTooltip(tooltip_buf, slot_contents_pos.add(v2f(slot.rect.dims.x, 0)), ui_scaling);
                }
            },
            .item => |*item| {
                try item.unqRenderIcon(cmd_buf, slot_contents_pos, ui_scaling);
                if (slot.long_hover.update(hovered)) {
                    try item.unqRenderTooltip(tooltip_buf, slot_contents_pos.add(v2f(slot.rect.dims.x, 0)), ui_scaling);
                }
            },
        }
        const price_str = try utl.bufPrintLocal(
            "{any}{any}{}",
            .{
                icon_text.Icon.coin,
                icon_text.Fmt{ .tint = if (can_buy) .yellow else .red },
                product.price.gold,
            },
        );
        const price_str_dims = icon_text.measureIconText(price_str).scale(ui_scaling);
        const price_pos = slot.rect.pos.add(slot.rect.dims).sub(price_str_dims.add(V2f.splat(slot_margin)));
        try icon_text.unqRenderIconText(cmd_buf, price_str, price_pos, ui_scaling);
    }

    return ret;
}

pub fn update(self: *Shop, run: *Run) Error!?Product {
    const plat = getPlat();
    const data = App.get().data;
    const ui_scaling: f32 = plat.ui_scaling;
    var ret: ?Product = null;

    try run.imm_ui.commands.append(.{ .clear = .{
        .color = .gray,
    } });

    const title_center_pos = v2f(
        plat.screen_dims_f.x * 0.5,
        30 * ui_scaling,
    );
    const title_font = data.fonts.get(.pixeloid);
    try run.imm_ui.commands.append(.{ .label = .{
        .pos = title_center_pos,
        .text = ImmUI.initLabel("Shoppy Woppy"),
        .opt = .{
            .center = true,
            .color = .white,
            .font = title_font,
            .size = title_font.base_size * utl.as(u32, ui_scaling + 2),
        },
    } });

    const price_font = data.fonts.get(.seven_x_five);
    const price_font_size = utl.as(f32, price_font.base_size) * (ui_scaling);

    // spells
    const spell_dims = Spell.card_dims.scale(ui_scaling);
    const spell_slot_dims = spell_dims.add(V2f.splat(slot_margin).scale(2)).add(v2f(0, price_font_size + slot_margin));
    const spells_center = title_center_pos.add(v2f(0, 23 + 60 + spell_dims.y * 0.5));

    var spell_rects = std.BoundedArray(geom.Rectf, max_num_spells){};
    spell_rects.resize(self.spells.len) catch unreachable;
    gameUI.layoutRectsFixedSize(
        spell_rects.len,
        spell_slot_dims,
        spells_center,
        .{ .direction = .horizontal, .space_between = spells_spacing },
        spell_rects.slice(),
    );
    for (spell_rects.constSlice(), 0..) |rect, i| {
        self.spells.buffer[i].rect = rect;
    }

    // items
    const item_dims = Item.icon_dims.scale(ui_scaling);
    const item_slot_dims = item_dims.add(V2f.splat(slot_margin).scale(2)).add(v2f(0, price_font_size + slot_margin));
    const items_center = spells_center.add(v2f(0, spell_slot_dims.y * 0.5 + 40 + item_slot_dims.y * 0.5));

    var item_rects = std.BoundedArray(geom.Rectf, max_num_spells){};
    item_rects.resize(self.items.len) catch unreachable;
    gameUI.layoutRectsFixedSize(
        item_rects.len,
        item_slot_dims,
        items_center,
        .{ .direction = .horizontal, .space_between = items_spacing },
        item_rects.slice(),
    );
    for (item_rects.constSlice(), 0..) |rect, i| {
        self.items.buffer[i].rect = rect;
    }

    for (self.spells.slice()) |*slot| {
        if (try unqProductSlot(&run.imm_ui.commands, &run.tooltip_ui.commands, slot, run)) {
            assert(canBuy(run, &slot.product.?));
            ret = slot.product.?;
            slot.product = null;
        }
    }

    for (self.items.slice()) |*slot| {
        if (try unqProductSlot(&run.imm_ui.commands, &run.tooltip_ui.commands, slot, run)) {
            assert(canBuy(run, &slot.product.?));
            ret = slot.product.?;
            slot.product = null;
        }
    }

    // proceed btn
    {
        const proceed_btn_dims = v2f(170, 100);
        const btn_center = items_center.add(v2f(0, item_slot_dims.y * 0.5 + 40 + proceed_btn_dims.y * 0.5));
        const proceed_btn_pos = btn_center.sub(proceed_btn_dims.scale(0.5));

        if (menuUI.textButton(&run.imm_ui.commands, proceed_btn_pos, "Proceed", proceed_btn_dims, ui_scaling)) {
            self.state = .done;
        }
    }

    return ret;
}

pub fn shopColliderProto() Thing {
    return Thing{
        .kind = .vfx,
        .spawn_state = .instance,
        .coll_radius = 62,
        .coll_mass = std.math.inf(f32),
        .coll_layer = Thing.Collision.Mask.initMany(&.{.creature}),
    };
}
