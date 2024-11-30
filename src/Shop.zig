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
    hover_timer: utl.TickCounter = utl.TickCounter.init(15),
    is_long_hovered: bool = false,
};

render_texture: Platform.RenderTexture2D,
spells: std.BoundedArray(ProductSlot, max_num_spells) = .{},
items: std.BoundedArray(ProductSlot, max_num_items) = .{},
rng: std.Random.DefaultPrng,
state: enum {
    shopping,
    done,
} = .shopping,
imm_ui: struct {
    commands: ImmUI.CmdBuf = .{},
} = .{},

pub fn init(seed: u64, run: *Run) Error!Shop {
    const plat = App.getPlat();

    var ret = Shop{
        .render_texture = plat.createRenderTexture("shop", core.native_dims),
        .rng = std.Random.DefaultPrng.init(seed),
    };

    var spells = std.BoundedArray(Spell, max_num_spells){};
    const spells_generated = Spell.makeShopSpells(ret.rng.random(), run.mode, spells.slice());
    spells.resize(spells_generated.len) catch unreachable;
    for (spells.constSlice()) |spell| {
        ret.spells.appendAssumeCapacity(.{
            .product = .{
                .kind = .{ .spell = spell },
                .price = .{ .gold = spell.getShopPrice(ret.rng.random()) },
            },
        });
    }

    var items = std.BoundedArray(Item, max_num_items){};
    items.resize(num_items) catch unreachable;
    const num_items_generated = Item.makeShopItems(ret.rng.random(), run.mode, items.slice());
    items.resize(num_items_generated) catch unreachable;
    for (items.constSlice()) |item| {
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
    const plat = App.getPlat();
    plat.destroyRenderTexture(self.render_texture);
}

pub fn reset(self: *Shop, run: *Run) Error!*Shop {
    self.deinit();
    var rng = std.Random.DefaultPrng.init(utl.as(u64, std.time.microTimestamp()));
    const seed = rng.random().int(u64);
    self.* = try init(seed, run);
    return self;
}

pub fn canBuy(run: *const Run, product: *const Product) bool {
    const price = product.price.gold;
    return run.gold >= price and run.canPickupProduct(product);
}

fn unqProductSlot(cmd_buf: *ImmUI.CmdBuf, slot: *ProductSlot, run: *const Run) Error!bool {
    const data = App.get().data;
    const plat = getPlat();
    const ui_scaling: f32 = 3;
    var ret: bool = false;

    const mouse_pos = plat.getMousePosScreen();
    const hovered = geom.pointIsInRectf(mouse_pos, slot.rect);
    const clicked = hovered and plat.input_buffer.mouseBtnIsJustPressed(.left);
    // TODO anything else here?
    const slot_enabled = slot.product != null;
    const can_buy = slot_enabled and canBuy(run, &slot.product.?);
    const bg_color = Colorf.rgb(0.17, 0.15, 0.15);
    var slot_contents_pos = slot.rect.pos.add(V2f.splat(slot_margin));

    if (hovered) {
        _ = slot.hover_timer.tick(false);
    } else {
        slot.hover_timer.restart();
    }
    slot.is_long_hovered = (hovered and !slot.hover_timer.running);

    // background rect
    if (can_buy and hovered) {
        // TODO animate
        slot_contents_pos = slot_contents_pos.add(v2f(0, -5));
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
                // TODO maybe?
                //const scaling = if (slot.is_long_hovered) ui_scaling + 1 else ui_scaling;
                spell.unqRenderCard(cmd_buf, slot_contents_pos, null, ui_scaling);
            },
            .item => |*item| {
                try item.unqRenderIcon(cmd_buf, slot_contents_pos, ui_scaling);
            },
        }
        const price_font = data.fonts.get(.pixeloid);
        const price_text_opt = draw.TextOpt{
            .color = if (can_buy) .yellow else .red,
            .size = price_font.base_size * utl.as(u32, ui_scaling),
            .smoothing = .none,
            .font = price_font,
            .border = .{ .dist = ui_scaling },
        };
        const price_str = try utl.bufPrintLocal("${}", .{product.price.gold});
        const price_str_dims = try plat.measureText(price_str, price_text_opt);
        const price_pos = slot.rect.pos.add(slot.rect.dims).sub(price_str_dims.add(V2f.splat(slot_margin)));

        try cmd_buf.append(.{ .label = .{
            .pos = price_pos,
            .text = ImmUI.initLabel(price_str),
            .opt = price_text_opt,
        } });
    }

    return ret;
}

pub fn update(self: *Shop, run: *const Run) Error!?Product {
    const plat = getPlat();
    const data = App.get().data;
    const ui_scaling: f32 = 3;
    var ret: ?Product = null;

    self.imm_ui.commands.clear();

    const title_center_pos = plat.native_rect_cropped_offset.add(v2f(
        plat.native_rect_cropped_dims.x * 0.5,
        60,
    ));
    try self.imm_ui.commands.append(.{ .label = .{
        .pos = title_center_pos,
        .text = ImmUI.initLabel("Shoppy Woppy"),
        .opt = .{
            .center = true,
            .color = .white,
            .size = 45,
        },
    } });

    const price_font = data.fonts.get(.pixeloid);
    const price_font_size = utl.as(f32, price_font.base_size) * ui_scaling;

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
        if (try unqProductSlot(&self.imm_ui.commands, slot, run)) {
            assert(canBuy(run, &slot.product.?));
            ret = slot.product.?;
            slot.product = null;
        }
    }

    for (self.items.slice()) |*slot| {
        if (try unqProductSlot(&self.imm_ui.commands, slot, run)) {
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

        if (menuUI.textButton(&self.imm_ui.commands, proceed_btn_pos, "Proceed", proceed_btn_dims)) {
            self.state = .done;
        }
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
}
