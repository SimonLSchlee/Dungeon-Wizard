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

const Run = @This();
const App = @import("App.zig");
const getPlat = App.getPlat;
const Room = @import("Room.zig");
const Spell = @import("Spell.zig");
const Thing = @import("Thing.zig");
const Data = @import("Data.zig");
const PackedRoom = @import("PackedRoom.zig");
const menuUI = @import("menuUI.zig");
const gameUI = @import("gameUI.zig");
const Shop = @import("Shop.zig");
const Item = @import("Item.zig");

pub const Reward = struct {
    pub const UI = struct {
        modal_topleft: V2f,
        modal_dims: V2f,
        modal_opt: draw.PolyOpt,
        title_center: V2f,
        title_opt: draw.TextOpt,
        spell_rects: std.BoundedArray(menuUI.ClickableRect, max_spells),
        item_rects: std.BoundedArray(menuUI.ClickableRect, max_items),
        skip_or_continue_button: menuUI.Button,
    };

    const base_spells: usize = 3;
    const max_spells = 8;
    const base_items = 1;
    const max_items = 8;

    spells: std.BoundedArray(Spell, max_spells) = .{},
    items: std.BoundedArray(Item, max_items) = .{},
};

pub const GamePauseUI = struct {
    deck_button: menuUI.Button,
    pause_menu_button: menuUI.Button,
};

pub fn makeStarterDeck(dbg: bool) Spell.SpellArray {
    var ret = Spell.SpellArray{};
    // TODO placeholder
    const unherring = Spell.getProto(.unherring);
    const protec = Spell.getProto(.protec);
    const frost = Spell.getProto(.frost_vom);
    const blackmail = Spell.getProto(.blackmail);
    const mint = Spell.getProto(.mint);
    const impling = Spell.getProto(.impling);
    const promptitude = Spell.getProto(.promptitude);
    const flamey_explodey = Spell.getProto(.flamey_explodey);
    const expose = Spell.getProto(.expose);

    const deck_cards = if (dbg)
        &[_]struct { Spell, usize }{
            .{ unherring, 1 },
            .{ protec, 1 },
            .{ frost, 1 },
            .{ blackmail, 1 },
            .{ mint, 1 },
            .{ impling, 1 },
            .{ promptitude, 1 },
            .{ flamey_explodey, 1 },
        }
    else
        &[_]struct { Spell, usize }{
            .{ unherring, 4 },
            .{ protec, 2 },
            .{ expose, 1 },
        };

    deck: for (deck_cards) |t| {
        for (0..t[1]) |_| {
            ret.append(t[0]) catch break :deck;
        }
    }

    return ret;
}

pub const PlaceKind = enum {
    room,
    shop,
};
pub const Place = union(PlaceKind) {
    pub const Array = std.BoundedArray(Place, 32);

    room: struct {
        kind: union(enum) {
            first,
            normal: usize,
            boss,
        },
        difficulty: f32,
    },
    shop: struct {
        num: usize,
    },
};

gold: i32 = 0,
room: ?Room = null,
reward: ?Reward = null,
shop: ?Shop = null,
reward_ui: Reward.UI = undefined,
game_pause_ui: GamePauseUI = undefined,
screen: enum {
    game,
    pause_menu,
    reward,
    shop,
    dead,
} = .game,
seed: u64,
rng: std.Random.DefaultPrng = undefined,
places: Place.Array = .{},
curr_place_idx: usize = 0,
player_thing: Thing = undefined,
deck: Spell.SpellArray = .{},
slots_init_params: gameUI.Slots.InitParams = .{},
load_timer: u.TickCounter = u.TickCounter.init(20),
load_state: enum {
    none,
    fade_in,
    fade_out,
} = .fade_in,
curr_tick: i64 = 0,

pub fn init(seed: u64) Error!Run {
    const app = App.get();

    var ret: Run = .{
        .rng = std.Random.DefaultPrng.init(seed),
        .seed = seed,
        .deck = makeStarterDeck(false),
        .game_pause_ui = makeGamePauseUI(),
        .player_thing = app.data.creatures.get(.player),
    };

    // TODO elsewhererre?
    ret.slots_init_params.items = @TypeOf(ret.slots_init_params.items).fromSlice(&.{
        Item.getProto(.pot_hp),
        null,
        null,
        null,
    }) catch unreachable;

    // init places
    var places = Place.Array{};
    for (0..app.data.normal_rooms.len) |i| {
        try places.append(.{ .room = .{ .difficulty = 0, .kind = .{ .normal = i } } });
    }
    assert(places.len >= 2);
    ret.rng.random().shuffleWithIndex(Place, places.slice(), u32);
    for (places.slice(), 0..) |*place, i| {
        place.room.difficulty = 4 + u.as(f32, i) * 2;
    }
    try places.insert(places.len / 2, .{ .shop = .{ .num = 0 } });
    try places.insert(0, .{ .room = .{ .difficulty = 0, .kind = .first } });
    try places.append(.{ .shop = .{ .num = 1 } });
    try places.append(.{ .room = .{ .difficulty = places.get(places.len - 2).room.difficulty, .kind = .boss } });
    ret.places = places;

    return ret;
}

pub fn deinit(self: *Run) void {
    if (self.room) |*room| {
        room.deinit();
    }
}

pub fn reset(self: *Run) Error!*Run {
    self.deinit();
    var rng = std.Random.DefaultPrng.init(u.as(u64, std.time.microTimestamp()));
    const seed = rng.random().int(u64);
    self.* = try init(seed);
    return self;
}

pub fn startRun(self: *Run) Error!void {
    try self.loadPlaceFromCurrIdx();
}

pub fn loadPlaceFromCurrIdx(self: *Run) Error!void {
    const data = App.get().data;
    if (self.room) |*room| {
        room.deinit();
        self.room = null;
    }
    if (self.shop) |*shop| {
        shop.deinit();
        self.shop = null;
    }
    switch (self.places.get(self.curr_place_idx)) {
        .room => |r| {
            const packed_room = switch (r.kind) {
                .first => data.first_room,
                .normal => |idx| data.normal_rooms.get(idx),
                .boss => data.boss_room,
            };
            const exit_doors = self.makeExitDoors(packed_room);
            const waves_params = Room.WavesParams{
                .difficulty = r.difficulty,
            };
            self.room = try Room.init(.{
                .deck = self.deck,
                .waves_params = waves_params,
                .packed_room = packed_room,
                .seed = self.rng.random().int(u64),
                .exits = exit_doors,
                .player = self.player_thing,
                .slots_params = self.slots_init_params,
            });
            // TODO hacky
            // update once to clear fog
            try self.room.?.update();
            self.screen = .game;
        },
        .shop => |s| {
            _ = s.num;
            self.shop = try Shop.init(self.rng.random().int(u64));
            self.screen = .shop;
        },
    }
}

pub fn makeExitDoors(_: *Run, packed_room: PackedRoom) std.BoundedArray(gameUI.ExitDoor, 4) {
    var ret = std.BoundedArray(gameUI.ExitDoor, 4){};
    for (packed_room.exits.constSlice()) |pos| {
        ret.append(.{ .pos = pos }) catch unreachable;
    }
    return ret;
}

pub fn makeReward(self: *Run) void {
    const random = self.rng.random();
    var reward = Reward{};
    reward.spells.resize(Reward.base_spells) catch unreachable;
    const num_spells_generated = Spell.makeRoomReward(random, reward.spells.slice());
    reward.spells.resize(num_spells_generated) catch unreachable;
    const num_items = random.uintAtMost(usize, Reward.base_items);
    if (num_items > 0) {
        reward.items.resize(num_items) catch unreachable;
        const num_items_generated = Item.makeRoomReward(random, reward.items.slice());
        reward.items.resize(num_items_generated) catch unreachable;
    }
    self.reward = reward;
    self.reward_ui = makeRewardUI(&reward);
    self.screen = .reward;
}

pub fn canPickupProduct(self: *const Run, product: *const Shop.Product) bool {
    switch (product.kind) {
        .spell => |_| {
            if (self.deck.len >= self.deck.buffer.len) return false;
        },
        .item => |_| {
            if (self.slots_init_params.items.len >= self.slots_init_params.items.buffer.len) return false;
            for (self.slots_init_params.items.constSlice()) |maybe_item| {
                if (maybe_item == null) break;
            } else {
                return false;
            }
        },
    }
    return true;
}

pub fn pickupProduct(self: *Run, product: *const Shop.Product) void {
    assert(self.canPickupProduct(product));
    switch (product.kind) {
        .spell => |spell| {
            assert(self.deck.len < self.deck.buffer.len);
            self.deck.append(spell) catch unreachable;
            // TODO ugh?
            if (self.room) |*room| {
                room.init_params.deck.append(spell) catch unreachable;
                room.draw_pile.append(spell) catch unreachable;
            }
        },
        .item => |item| {
            assert(self.slots_init_params.items.len < self.slots_init_params.items.buffer.len);
            for (self.slots_init_params.items.slice()) |*item_slot| {
                if (item_slot.* == null) {
                    item_slot.* = item;
                    break;
                }
            } else {
                unreachable;
            }
        },
    }
}

fn loadNextPlace(self: *Run) void {
    self.load_state = .fade_out;
}

pub fn gameUpdate(self: *Run) Error!void {
    const plat = getPlat();
    assert(self.room != null);
    const room = &self.room.?;

    if (debug.enable_debug_controls) {
        if (plat.input_buffer.keyIsJustPressed(.f4)) {
            try room.reset();
        }
        if (room.edit_mode) {
            if (plat.input_buffer.getNumberKeyJustPressed()) |num| {
                const app = App.get();
                const n: usize = if (num == 0) 9 else num - 1;
                if (n < app.data.test_rooms.len) {
                    const packed_room = app.data.test_rooms.get(n);
                    try room.reloadFromPackedRoom(packed_room);
                }
            }
        }
    }
    if (!room.edit_mode) {
        if (plat.input_buffer.keyIsJustPressed(.escape)) {
            room.paused = true;
            self.screen = .pause_menu;
        }
    }
    try room.update();
    switch (room.progress_state) {
        .none => {},
        .lost => {},
        .won => {
            const curr_room_place = self.places.get(self.curr_place_idx).room;
            if (self.reward == null and curr_room_place.kind == .normal) {
                self.makeReward();
                // TODO bettterrr?
                self.gold += u.as(i32, @floor(curr_room_place.difficulty));
            }
        },
        .exited => |exit_door| {
            _ = exit_door;
            self.player_thing.hp = room.getConstPlayer().?.hp.?;
            // TODO make it betterrrs?
            self.slots_init_params.items = .{};
            for (room.ui_slots.items.constSlice()) |slot| {
                self.slots_init_params.items.append(slot.kind.item) catch unreachable;
            }
            self.loadNextPlace();
        },
    }
    if (room.paused) {
        // TODO update game pause ui
    }
}

pub fn pauseMenuUpdate(self: *Run) Error!void {
    const plat = getPlat();
    // TODO could pause in shop or w/e
    assert(self.room != null);
    const room = &self.room.?;
    if (plat.input_buffer.keyIsJustPressed(.space) or plat.input_buffer.keyIsJustPressed(.escape)) {
        room.paused = false;
        self.screen = .game;
    }
}

pub fn rewardUpdate(self: *Run) Error!void {
    const plat = getPlat();
    _ = plat;
    // TODO could get rewards not in room?
    assert(self.reward != null);
    const reward = &self.reward.?;
    const reward_ui = self.reward_ui;
    if (reward_ui.skip_or_continue_button.isClicked()) {
        self.screen = .game;
    } else {
        for (reward_ui.spell_rects.constSlice(), 0..) |crect, i| {
            if (crect.isClicked()) {
                const spell = reward.spells.get(i);
                const product = Shop.Product{ .kind = .{ .spell = spell } };
                if (self.canPickupProduct(&product)) {
                    self.pickupProduct(&product);
                    reward.spells.len = 0;
                }
                self.reward_ui = makeRewardUI(reward);
                break;
            }
        }
        for (reward_ui.item_rects.constSlice(), 0..) |crect, i| {
            if (crect.isClicked()) {
                const item = reward.items.get(i);
                const product = Shop.Product{ .kind = .{ .item = item } };
                if (self.canPickupProduct(&product)) {
                    self.pickupProduct(&product);
                }
                _ = reward.items.orderedRemove(i);
                self.reward_ui = makeRewardUI(reward);
                break;
            }
        }
    }
}

pub fn shopUpdate(self: *Run) Error!void {
    const plat = App.getPlat();
    assert(self.shop != null);
    const shop = &self.shop.?;

    if (debug.enable_debug_controls) {
        if (plat.input_buffer.keyIsJustPressed(.f4)) {
            _ = try shop.reset();
        }
        if (plat.input_buffer.keyIsJustPressed(.k)) {
            self.gold += 100;
        }
    }

    if (try shop.update(self)) |*product| {
        const price = product.price.gold;
        assert(self.gold >= price);
        self.gold -= price;
        self.pickupProduct(product);
    }
    if (shop.state == .done) {
        self.loadNextPlace();
    }
}

pub fn deadUpdate(self: *Run) Error!void {
    const plat = getPlat();
    _ = plat;
    _ = self;
    // TODO
}

pub fn update(self: *Run) Error!void {
    const plat = App.getPlat();

    if (debug.enable_debug_controls) {
        if (plat.input_buffer.keyIsJustPressed(.f3)) {
            _ = try self.reset();
        }
        if (plat.input_buffer.keyIsJustPressed(.o)) {
            self.makeReward();
        }
        if (plat.input_buffer.keyIsJustPressed(.l)) {
            self.loadNextPlace();
        }
    }
    // TODO hack to stop stack getting too massive on run + room init
    if (self.curr_tick == 0) {
        try self.startRun();
    }

    switch (self.load_state) {
        .none => switch (self.screen) {
            .game => try self.gameUpdate(),
            .pause_menu => try self.pauseMenuUpdate(),
            .reward => try self.rewardUpdate(),
            .shop => try self.shopUpdate(),
            .dead => try self.deadUpdate(),
        },
        .fade_in => if (self.load_timer.tick(true)) {
            self.load_state = .none;
        },
        .fade_out => if (self.load_timer.tick(true)) {
            self.curr_place_idx += 1;
            try self.loadPlaceFromCurrIdx();
            self.reward = null;
            self.load_state = .fade_in;
        },
    }
    self.curr_tick += 1;
}

fn makeGamePauseUI() GamePauseUI {
    const plat = App.getPlat();
    const screen_margin = v2f(30, 60);
    const button_dims = v2f(100, 50);
    const button_y = plat.screen_dims_f.y - screen_margin.y - button_dims.y;
    var deck_button = menuUI.Button{
        .rect = .{
            .pos = v2f(screen_margin.x, button_y),
            .dims = button_dims,
        },
        .poly_opt = .{ .fill_color = .orange },
        .text_opt = .{ .center = true, .color = .black, .size = 30 },
        .text_rel_pos = button_dims.scale(0.5),
    };
    deck_button.text = @TypeOf(deck_button.text).init("Deck") catch unreachable;

    var pause_menu_button = menuUI.Button{
        .rect = .{
            .pos = v2f(plat.screen_dims_f.x - screen_margin.x - button_dims.x, button_y),
            .dims = button_dims,
        },
        .poly_opt = .{ .fill_color = .orange },
        .text_opt = .{ .center = true, .color = .black, .size = 30 },
        .text_rel_pos = button_dims.scale(0.5),
    };
    pause_menu_button.text = @TypeOf(pause_menu_button.text).init("Menu") catch unreachable;

    return .{
        .deck_button = deck_button,
        .pause_menu_button = pause_menu_button,
    };
}

fn makeRewardUI(reward: *const Reward) Reward.UI {
    const plat = App.getPlat();
    const modal_dims = v2f(plat.screen_dims_f.x * 0.8, plat.screen_dims_f.y * 0.8);
    const modal_topleft = plat.screen_dims_f.sub(modal_dims).scale(0.5);
    const modal_opt = draw.PolyOpt{
        .fill_color = Colorf.rgba(0.1, 0.1, 0.1, 0.8),
        .outline_color = Colorf.rgba(0.1, 0.1, 0.2, 0.8),
        .outline_thickness = 4,
    };
    var curr_row_y = modal_topleft.y + 20;
    const center_x = modal_topleft.x + modal_dims.x * 0.5;

    // title
    const title_center = v2f(center_x, curr_row_y + 40);
    const title_opt = draw.TextOpt{
        .size = 40,
        .color = .white,
        .center = true,
    };
    curr_row_y += 80;

    // spells
    const spell_dims = v2f(250, 250.0 / 0.7);
    var spell_grects = std.BoundedArray(geom.Rectf, Reward.max_spells){};
    spell_grects.resize(reward.spells.len) catch unreachable;
    if (spell_grects.len > 0) {
        gameUI.layoutRectsFixedSize(spell_grects.len, spell_dims, v2f(center_x, curr_row_y + spell_dims.y * 0.5), .{ .direction = .horizontal, .space_between = 20 }, spell_grects.slice());
    }
    // TODO ARARGHH
    var spell_rects = std.BoundedArray(menuUI.ClickableRect, Reward.max_spells){};
    for (spell_grects.constSlice()) |r| {
        spell_rects.append(.{ .dims = r.dims, .pos = r.pos }) catch unreachable;
    }
    curr_row_y += spell_dims.y + 40;

    const item_dims = v2f(100, 100);
    var item_grects = std.BoundedArray(geom.Rectf, Reward.max_spells){};
    item_grects.resize(reward.items.len) catch unreachable;
    if (item_grects.len > 0) {
        gameUI.layoutRectsFixedSize(item_grects.len, item_dims, v2f(center_x, curr_row_y + item_dims.y * 0.5), .{ .direction = .horizontal, .space_between = 20 }, item_grects.slice());
    }
    // TODO ARARGHH
    var item_rects = std.BoundedArray(menuUI.ClickableRect, Reward.max_spells){};
    for (item_grects.constSlice()) |r| {
        item_rects.append(.{ .dims = r.dims, .pos = r.pos }) catch unreachable;
    }
    curr_row_y += item_dims.y + 40;

    const skip_btn_dims = v2f(150, 70);
    const skip_btn_center = v2f(center_x, curr_row_y + skip_btn_dims.y * 0.5);
    var skip_button = menuUI.Button{
        .rect = .{
            .pos = skip_btn_center.sub(skip_btn_dims.scale(0.5)),
            .dims = skip_btn_dims,
        },
        .poly_opt = .{ .fill_color = .orange },
        .text_opt = .{ .center = true, .color = .black, .size = 30 },
        .text_rel_pos = skip_btn_dims.scale(0.5),
    };
    if (reward.items.len == 0 and reward.spells.len == 0) {
        skip_button.poly_opt.fill_color = .cyan;
        skip_button.text = @TypeOf(skip_button.text).init("Continue") catch unreachable;
    } else {
        skip_button.text = @TypeOf(skip_button.text).init("Skip") catch unreachable;
    }

    return .{
        .modal_dims = modal_dims,
        .modal_topleft = modal_topleft,
        .modal_opt = modal_opt,
        .title_center = title_center,
        .title_opt = title_opt,
        .spell_rects = spell_rects,
        .item_rects = item_rects,
        .skip_or_continue_button = skip_button,
    };
}

pub fn render(self: *Run) Error!void {
    const plat = getPlat();
    plat.clear(Colorf.magenta);

    if (self.room) |room| {
        try room.render();
        //const game_scale: i32 = 2;
        //const game_dims_scaled_f = game_dims.scale(game_scale).toV2f();
        //const topleft = p.screen_dims_f.sub(game_dims_scaled_f).scale(0.5);
        const game_texture_opt = .{
            .flip_y = true,
        };
        plat.texturef(.{}, room.render_texture.?.texture, game_texture_opt);
    }

    switch (self.screen) {
        .game => {
            assert(self.room != null);
            const room = &self.room.?;
            if (room.paused) {
                try self.game_pause_ui.deck_button.render();
                try self.game_pause_ui.pause_menu_button.render();
            }
        },
        .pause_menu => {},
        .reward => {
            assert(self.reward != null);
            const reward = &self.reward.?;
            const reward_ui = self.reward_ui;
            plat.rectf(reward_ui.modal_topleft, reward_ui.modal_dims, reward_ui.modal_opt);
            try plat.textf(reward_ui.title_center, "Choose 1", .{}, reward_ui.title_opt);
            for (reward_ui.spell_rects.constSlice(), 0..) |crect, i| {
                const spell = reward.spells.get(i);
                var hovered_crect = crect;
                if (crect.isHovered()) {
                    const new_dims = crect.dims.scale(1.1);
                    const new_pos = crect.pos.sub(new_dims.sub(crect.dims).scale(0.5));
                    hovered_crect.pos = new_pos;
                    hovered_crect.dims = new_dims;
                }
                try spell.renderInfo(hovered_crect);
            }
            for (reward_ui.item_rects.constSlice(), 0..) |crect, i| {
                const item = reward.items.get(i);
                var show_tooltip = false;
                var hovered_crect = crect;
                if (crect.isHovered()) {
                    show_tooltip = true;
                    const new_dims = crect.dims.scale(1.1);
                    const new_pos = crect.pos.sub(new_dims.sub(crect.dims).scale(0.5));
                    hovered_crect.pos = new_pos;
                    hovered_crect.dims = new_dims;
                }
                plat.rectf(hovered_crect.pos, hovered_crect.dims, .{ .fill_color = .darkgray });
                try item.renderIcon(hovered_crect);
                if (show_tooltip) {
                    try item.renderToolTip(hovered_crect.pos.add(v2f(hovered_crect.dims.x, 0)));
                }
            }
            try reward_ui.skip_or_continue_button.render();
        },
        .shop => {
            assert(self.shop != null);
            const shop = &self.shop.?;
            try shop.render(self);
            const shop_texture_opt = .{
                .flip_y = true,
            };
            plat.texturef(.{}, shop.render_texture.texture, shop_texture_opt);
        },
        .dead => {},
    }
    { // gold
        const fill_color = Colorf.rgb(1, 0.9, 0);
        const text_color = Colorf.rgb(0.44, 0.3, 0.0);
        const poly_opt = .{ .fill_color = fill_color, .outline_color = text_color, .outline_thickness = 10 };
        const center = v2f(250, plat.screen_dims_f.y - 100);
        const num = 3;
        const lower = center.add(v2f(0, 7 * num));
        for (0..num) |i| {
            plat.circlef(lower.add(v2f(0, u.as(f32, i) * -7)), 55, poly_opt);
        }
        const gold_width = (try plat.measureText("Gold", .{ .size = 25 })).x;
        try plat.textf(center.sub(v2f(gold_width, 0)), "Gold: {}", .{self.gold}, .{
            .color = text_color,
            .size = 25,
        });
    }
    switch (self.load_state) {
        .none => {},
        .fade_in => {
            const color = Colorf.black.fade(1 - self.load_timer.remapTo0_1());
            plat.rectf(.{}, plat.screen_dims_f, .{ .fill_color = color });
        },
        .fade_out => {
            const color = Colorf.black.fade(self.load_timer.remapTo0_1());
            plat.rectf(.{}, plat.screen_dims_f, .{ .fill_color = color });
        },
    }
}
