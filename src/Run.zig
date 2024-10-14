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

pub fn makeStarterDeck() Spell.SpellArray {
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
    const starter_deck = [_]struct { Spell, usize }{
        .{ unherring, 3 },
        .{ protec, 1 },
        .{ frost, 1 },
        .{ blackmail, 1 },
        .{ mint, 3 },
        .{ impling, 1 },
        .{ promptitude, 1 },
        .{ flamey_explodey, 1 },
    };

    deck: for (starter_deck) |t| {
        for (0..t[1]) |_| {
            ret.append(t[0]) catch break :deck;
        }
    }

    return ret;
}

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
packed_room_data_indices: std.BoundedArray(usize, 32) = .{},
curr_room_idx: usize = 0,
player_thing: ?Thing = null,
deck: Spell.SpellArray = .{},
curr_tick: i64 = 0,

pub fn init(seed: u64) Error!Run {
    const app = App.get();

    var ret: Run = .{
        .rng = std.Random.DefaultPrng.init(seed),
        .seed = seed,
        .deck = makeStarterDeck(),
        .game_pause_ui = makeGamePauseUI(),
    };
    for (0..app.data.rooms.len) |i| {
        try ret.packed_room_data_indices.append(i);
    }
    assert(ret.packed_room_data_indices.len > 0);

    try ret.loadRoomFromCurrIdx();

    return ret;
}

pub fn deinit(self: *Run) void {
    if (self.room) |*room| {
        room.deinit();
    }
}

pub fn reset(self: *Run) Error!*Run {
    self.deinit();
    self.* = .{};
    try self.init();
    return self;
}

pub fn loadRoomFromCurrIdx(self: *Run) Error!void {
    const data = App.get().data;
    if (self.room) |*room| {
        room.deinit();
    }
    const idx = self.packed_room_data_indices.get(self.curr_room_idx);
    const packed_room = data.rooms.get(idx);
    const exit_doors = self.makeExitDoors(packed_room);
    self.room = try Room.init(.{
        .deck = self.deck,
        .difficulty = 10,
        .packed_room = packed_room,
        .seed = self.seed,
        .exits = exit_doors,
    });
}

pub fn makeExitDoors(_: *Run, packed_room: PackedRoom) std.BoundedArray(gameUI.ExitDoor, 4) {
    var ret = std.BoundedArray(gameUI.ExitDoor, 4){};
    for (packed_room.exits.constSlice()) |pos| {
        ret.append(.{ .pos = pos }) catch unreachable;
    }
    return ret;
}

pub fn update(self: *Run) Error!void {
    const plat = getPlat();

    assert(self.room != null);
    const room = &self.room.?;

    switch (self.screen) {
        .game => {
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
            } else {
                if (plat.input_buffer.keyIsJustPressed(.escape)) {
                    room.paused = true;
                    self.screen = .pause_menu;
                }
            }
            try room.update();
            if (room.progress_state == .won and self.reward == null) {
                self.reward = Spell.Reward.init(self.rng.random());
                self.reward_ui = self.makeRewardUI();
                self.screen = .reward;
            }
            if (room.paused) {
                // update game pause ui
            }
        },
        .pause_menu => {
            if (plat.input_buffer.keyIsJustPressed(.space) or plat.input_buffer.keyIsJustPressed(.escape)) {
                room.paused = false;
                self.screen = .game;
            }
        },
        .reward => {
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
        },
        .shop => {},
        .dead => {},
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
    assert(self.room != null);
    const room = &self.room.?;
    try room.render();
    //const game_scale: i32 = 2;
    //const game_dims_scaled_f = game_dims.scale(game_scale).toV2f();
    //const topleft = p.screen_dims_f.sub(game_dims_scaled_f).scale(0.5);
    const game_texture_opt = .{
        .flip_y = true,
    };
    plat.texturef(.{}, room.render_texture.?.texture, game_texture_opt);

    switch (self.screen) {
        .game => {
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
        .shop => {},
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
}
