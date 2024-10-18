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

pub const RewardUI = struct {
    modal_topleft: V2f,
    modal_dims: V2f,
    modal_opt: draw.PolyOpt,
    rects: std.BoundedArray(menuUI.ClickableRect, 8),
    skip_button: menuUI.Button,
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
reward: ?Spell.Reward = null,
reward_ui: RewardUI = undefined,
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

    try ret.loadPlaceFromCurrIdx();

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

pub fn loadPlaceFromCurrIdx(self: *Run) Error!void {
    const data = App.get().data;
    if (self.room) |*room| {
        room.deinit();
        self.room = null;
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
            });
            // TODO hacky
            // update once to clear fog
            try self.room.?.update();
            self.screen = .game;
        },
        .shop => |s| {
            _ = s.num;
            // TODO generate shop
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

pub fn makeSpellReward(self: *Run) void {
    self.reward = Spell.Reward.init(self.rng.random());
    self.reward_ui = self.makeRewardUI();
    self.screen = .reward;
}

fn loadNextPlace(self: *Run) void {
    self.load_state = .fade_out;
}

pub fn gameUpdate(self: *Run) Error!void {
    const plat = getPlat();
    assert(self.room != null);
    const room = &self.room.?;

    if (debug.enable_debug_controls) {
        if (plat.input_buffer.keyIsJustPressed(.f3)) {
            _ = try self.reset();
        }
        if (plat.input_buffer.keyIsJustPressed(.f4)) {
            try room.reset();
        }
        if (plat.input_buffer.keyIsJustPressed(.o)) {
            self.makeSpellReward();
        }
        if (plat.input_buffer.keyIsJustPressed(.l)) {
            self.loadNextPlace();
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
            if (self.reward == null and self.places.get(self.curr_place_idx).room.kind == .normal) {
                self.makeSpellReward();
            }
        },
        .exited => |exit_door| {
            _ = exit_door;
            self.player_thing.hp = room.getConstPlayer().?.hp.?;
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
    assert(self.room != null);
    const room = &self.room.?;
    assert(self.reward != null);
    const reward = &self.reward.?;
    const reward_ui = self.reward_ui;
    if (reward_ui.skip_button.isClicked()) {
        self.screen = .game;
    } else {
        for (reward_ui.rects.constSlice(), 0..) |crect, i| {
            if (crect.isClicked()) {
                const spell = reward.spells.get(i);
                try self.deck.append(spell);
                // TODO ugh?
                room.init_params.deck.append(spell) catch unreachable;
                room.draw_pile.append(spell) catch unreachable;
                self.screen = .game;
                break;
            }
        }
    }
}

pub fn shopUpdate(self: *Run) Error!void {
    const plat = getPlat();
    if (plat.input_buffer.mouseBtnIsJustPressed(.left)) {
        self.loadNextPlace();
    }
    // TODO
}

pub fn deadUpdate(self: *Run) Error!void {
    const plat = getPlat();
    _ = plat;
    _ = self;
    // TODO
}

pub fn update(self: *Run) Error!void {
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

fn makeRewardUI(self: *Run) RewardUI {
    const plat = App.getPlat();
    assert(self.reward != null);
    const reward = self.reward.?;
    const slot_aspect = 0.7;
    const modal_dims = v2f(plat.screen_dims_f.x * 0.75, plat.screen_dims_f.y * 0.6);
    const modal_topleft = plat.screen_dims_f.sub(modal_dims).scale(0.5);
    const modal_padding = plat.screen_dims_f.scale(0.08);
    const slots_dims = modal_dims.sub(modal_padding.scale(2));
    const slots_topleft = modal_topleft.add(modal_padding);
    const slot_spacing = modal_padding.x * 0.3;
    const num_slots_f = u.as(f32, reward.spells.len);
    const slots_spacing_total = (num_slots_f - 1) * (slot_spacing);
    const slot_width = (slots_dims.x - slots_spacing_total) / num_slots_f;
    const slot_dims = v2f(slot_width, slot_width / slot_aspect);

    const modal_opt = draw.PolyOpt{
        .fill_color = Colorf.rgba(0.1, 0.1, 0.1, 0.8),
        .outline_color = Colorf.rgba(0.1, 0.1, 0.2, 0.8),
        .outline_thickness = 4,
    };

    var rects = std.BoundedArray(menuUI.ClickableRect, 8){};
    for (0..reward.spells.len) |i| {
        const offset = v2f(u.as(f32, i) * (slot_dims.x + slot_spacing), 0);
        const pos = slots_topleft.add(offset);
        rects.append(.{ .pos = pos, .dims = slot_dims }) catch unreachable;
    }

    const skip_btn_dims = modal_dims.scale(0.1);
    const slots_bottom_y = slots_topleft.y + slots_dims.y;
    const space_left_y = @max(slots_bottom_y - modal_topleft.y - modal_dims.y, 0);
    const skip_btn_center = v2f(slots_topleft.x + slots_dims.x * 0.5, slots_bottom_y + space_left_y * 0.5);
    var skip_button = menuUI.Button{
        .rect = .{
            .pos = skip_btn_center.sub(skip_btn_dims.scale(0.5)),
            .dims = skip_btn_dims,
        },
        .poly_opt = .{ .fill_color = .orange },
        .text_opt = .{ .center = true, .color = .black, .size = 30 },
        .text_rel_pos = skip_btn_dims.scale(0.5),
    };
    skip_button.text = @TypeOf(skip_button.text).init("Skip") catch unreachable;

    return .{
        .modal_dims = modal_dims,
        .modal_topleft = modal_topleft,
        .modal_opt = modal_opt,
        .rects = rects,
        .skip_button = skip_button,
    };
}

pub fn render(self: *Run) Error!void {
    const plat = getPlat();
    plat.clear(Colorf.magenta);
    // room is always present
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
            for (reward_ui.rects.constSlice(), 0..) |crect, i| {
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
            try reward_ui.skip_button.render();
        },
        .shop => {
            try plat.textf(plat.screen_dims_f.scale(0.5), "Shop placeholder, click to proceed", .{}, .{ .center = true, .color = .white });
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
