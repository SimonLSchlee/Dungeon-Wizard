const std = @import("std");
const u = @import("util.zig");

pub const Platform = @import("raylib.zig");
const core = @import("core.zig");
const Error = core.Error;
const Key = core.Key;
const debug = @import("debug.zig");
const assert = debug.assert;
const draw = @import("draw.zig");
const Colorf = draw.Colorf;
const geom = @import("geometry.zig");
const V2f = @import("V2f.zig");
const v2f = V2f.v2f;
const V2i = @import("V2i.zig");
const v2i = V2i.v2i;

const Room = @This();
const App = @import("App.zig");
const getPlat = App.getPlat;
const Data = @import("Data.zig");
const Thing = @import("Thing.zig");
const pool = @import("pool.zig");
const TileMap = @import("TileMap.zig");
const Fog = @import("Fog.zig");
const gameUI = @import("gameUI.zig");
const Spell = @import("Spell.zig");
const Run = @import("Run.zig");
const PackedRoom = @import("PackedRoom.zig");

pub const max_things_in_room = 128;

pub const ThingBoundedArray = std.BoundedArray(pool.Id, max_things_in_room);

pub const InitParams = struct {
    packed_room: PackedRoom,
    difficulty: f32,
    seed: u64,
    deck: Spell.SpellArray,
};

pub const Wave = struct {
    proto: Thing = undefined,
    positions: PackedRoom.WavePositionsArray = .{},
};
pub const WavesArray = std.BoundedArray(Wave, 10);

const WavesParams = struct {
    protos: std.BoundedArray(Thing, 8),
    difficulty: f32,
    difficulty_error: f32 = 4,

    pub fn init(difficulty: f32) WavesParams {
        const data = App.get().data;
        var ret = WavesParams{
            .protos = .{},
            .difficulty = difficulty,
        };
        const enemy_prototypes = [_]Thing{
            data.things.get(.troll).?,
            data.things.get(.gobbow).?,
            data.things.get(.sharpboi).?,
            // data.things.get(.acolyte),
        };
        for (enemy_prototypes) |p| {
            ret.protos.append(p) catch unreachable;
        }
        return ret;
    }
};

fn makeWaves(packed_room: PackedRoom, rng: std.Random, params: WavesParams) WavesArray {
    var difficulty_left = params.difficulty;
    var ret = WavesArray{};
    std.debug.print("\n\n#############\n", .{});
    std.debug.print("Making waves! difficulty: {d:.1}, error: {d:.1}\n", .{ params.difficulty, params.difficulty_error });
    for (packed_room.waves, 0..) |wave_positions, i| {
        if (wave_positions.len == 0) continue;
        var wave = Wave{};
        wave.positions = wave_positions;
        while (difficulty_left > params.difficulty_error) {
            const idx = rng.intRangeLessThan(usize, 0, params.protos.len);
            const proto = params.protos.buffer[idx];
            const wave_difficulty = proto.enemy_difficulty * u.as(f32, wave_positions.len);
            if (wave_difficulty > difficulty_left + params.difficulty_error) continue;
            difficulty_left -= wave_difficulty;
            wave.proto = proto;
            std.debug.print("  {}: selected {any}, total difficulty: {d:.2}\n", .{ i, wave.proto.kind, wave_difficulty });
            std.debug.print("    {d:.2} difficulty left\n", .{difficulty_left});
            ret.append(wave) catch unreachable;
            break;
        }
    }
    std.debug.print("#############\n\n", .{});
    return ret;
}

// Room is basically the "World" state, of things that can change frame-to-frame in realtime while playing the 'main' game
// that would include the UI state, graphics, etc...
// save state - debugging
// level in starting state - tilemap currently doing this
//   - clone the prototype to 'reload' the Room
//   -
//   - could just use 'Room' - prototype 'Room' has all the stuff for a given level
//     - serialize a Room - with an option to serialize the entire state, for debugging, or just the 'level' stuff for loading levels
//     - move tilemap parsing code to Room
//     -
// edit mode:
// - edit level starting state - can save, reload, etc
//   - distinguish between 'spawns' and 'Things'
// - edit current state for adhoc testing
//   - e.g. adding 'Thing's or w/e
// load/save states for debugging/testing
// load/save levels, on load some state (player hp and stuff?) comes from higher level ("Run" or "Save" or something)
//

// fields to deep copy/reinit on clone()
//  - render texture - just reinit?
//  - is the same as the below; serialize entire state
// fields to serialize if we want to save game state to disk, probably for debugging
//  - ui, debug stuff, things, fog, spawn queue...everything except stuff we just reinit() (render_texture?)
//  - more data, follow pointers and de/serialize those... etc
camera: draw.Camera2D = .{},
things: Thing.Pool = undefined,
spawn_queue: ThingBoundedArray = .{},
free_queue: ThingBoundedArray = .{},
moused_over_thing: ?Thing.Id = null,
player_id: ?pool.Id = null,
spell_slots: gameUI.SpellSlots = .{},
draw_pile: Spell.SpellArray = .{},
discard_pile: Spell.SpellArray = .{},
fog: Fog = undefined,
ui_clicked: bool = false,
curr_tick: i64 = 0,
paused: bool = false,
edit_mode: bool = false,
waves: WavesArray = .{},
first_wave_timer: u.TickCounter = undefined,
curr_wave: i32 = 0,
num_enemies_alive: i32 = 0,
progress_state: enum {
    none,
    lost,
    won,
} = .none,
// reinit stuff, never needs saving or copying, probably?:
render_texture: ?Platform.RenderTexture2D = null,
next_pool_id: u32 = 0, // i hate this, can we change it?
rng: std.Random.DefaultPrng = undefined,
// fields to save/load for level loading
//  - spawns, tiles, zones
//  - gets 'append'ed to a file
//  - this could just be a string or idx for lookup in data.rooms or something, or data.load_room() with a cache behind it, or...
//  - could just store its own whole-ass prototype to reinit from
// so this may as well be a different data structure than "Room"
// oh except, the tiles, (like, it IS used at runtime) ya know... so... no it should be just in Room
//
tilemap: TileMap = .{},
init_params: InitParams,

pub fn init(params: InitParams) Error!Room {
    const plat = getPlat();

    var ret: Room = .{
        .next_pool_id = 0,
        .render_texture = plat.createRenderTexture("room", plat.screen_dims),
        .fog = try Fog.init(),
        .init_params = params,
    };

    // everything is done except spawning stuff
    try ret.reset();

    return ret;
}

pub fn deinit(self: *Room) void {
    self.clearThings();
    self.fog.deinit();
    self.tilemap.deinit();
    if (self.render_texture) |tex| {
        getPlat().destroyRenderTexture(tex);
    }
}

fn clearThings(self: *Room) void {
    self.things = Thing.Pool.init(self.next_pool_id);
    self.next_pool_id += 1;
    self.spawn_queue.len = 0;
    self.free_queue.len = 0;
    self.player_id = null;
    self.spell_slots = .{};
    self.draw_pile = .{};
    self.discard_pile = .{};
}

pub fn reset(self: *Room) Error!void {
    const plat = getPlat();
    self.clearThings();
    self.fog.clearAll();
    self.camera = .{
        .offset = plat.screen_dims_f.scale(0.5),
        .zoom = 1,
    };
    self.curr_tick = 0;
    self.rng = std.Random.DefaultPrng.init(self.init_params.seed);
    self.first_wave_timer = u.TickCounter.init(5 * core.fups_per_sec);
    self.curr_wave = 0;
    self.num_enemies_alive = 0;
    self.draw_pile = self.init_params.deck;
    self.tilemap.deinit();
    self.tilemap = try TileMap.init(self.init_params.packed_room.tiles.constSlice(), self.init_params.packed_room.dims);
    self.waves = makeWaves(self.init_params.packed_room, self.rng.random(), WavesParams.init(self.init_params.difficulty));

    for (self.init_params.packed_room.thing_spawns.constSlice()) |spawn| {
        std.debug.print("Room init: spawning a {any}\n", .{spawn.kind});
        if (try self.queueSpawnThingByKind(spawn.kind, spawn.pos)) |id| {
            if (spawn.kind == .player) {
                self.player_id = id;
            }
        }
    }

    for (0..gameUI.SpellSlots.num_slots) |i| {
        if (self.drawSpell()) |spell| {
            self.spell_slots.fillSlot(spell, i);
        }
    }
}

pub fn reloadFromPackedRoom(self: *Room, packed_room: PackedRoom) Error!void {
    self.tilemap.deinit();
    self.init_params.packed_room = packed_room;
    try self.reset();
}

pub fn queueSpawnThing(self: *Room, proto: *const Thing, pos: V2f) Error!?pool.Id {
    const t = self.things.alloc();
    if (t) |thing| {
        try proto.copyTo(thing);
        thing.spawn_state = .spawning;
        thing.pos = pos;
        try self.spawn_queue.append(thing.id);
        if (thing.isEnemy()) self.num_enemies_alive += 1;
        return thing.id;
    }
    return null;
}

pub fn queueSpawnThingByKind(self: *Room, kind: Thing.Kind, pos: V2f) Error!?pool.Id {
    const app = App.get();
    if (app.data.things.getPtr(kind)) |proto| {
        return self.queueSpawnThing(proto, pos);
    }
    return null;
}

pub fn getThingById(self: *Room, id: pool.Id) ?*Thing {
    return self.things.get(id);
}

pub fn getConstThingById(self: *const Room, id: pool.Id) ?*const Thing {
    return self.things.getConst(id);
}

pub fn getThingByPos(self: *Room, pos: V2f) ?*Thing {
    for (&self.things.items) |*thing| {
        if (!thing.isActive()) continue;
        if (pos.dist(thing.pos) < thing.coll_radius) {
            return thing;
        }
    }
    return null;
}

pub fn getPlayer(self: *Room) ?*Thing {
    if (self.player_id) |id| {
        return self.getThingById(id);
    }
    return null;
}

pub fn getConstPlayer(self: *const Room) ?*const Thing {
    if (self.player_id) |id| {
        return self.getConstThingById(id);
    }
    return null;
}

pub fn drawSpell(self: *Room) ?Spell {
    if (self.draw_pile.len > 0) {
        const last = u.as(u32, self.draw_pile.len - 1);
        const idx = u.as(usize, self.rng.random().intRangeAtMost(u32, 0, last));
        const spell = self.draw_pile.swapRemove(idx);
        return spell;
    } else {
        self.draw_pile.insertSlice(0, self.discard_pile.constSlice()) catch unreachable;
        self.discard_pile.len = 0;
    }
    return null;
}

pub fn discardSpell(self: *Room, spell: Spell) void {
    self.discard_pile.append(spell) catch @panic("discard pile ran out of space");
}

pub fn spawnCurrWave(self: *Room) Error!void {
    assert(self.curr_wave < self.waves.len);
    const wave = self.waves.get(u.as(usize, self.curr_wave));
    const spawner_proto = Thing.SpawnerController.prototype(wave.proto.kind);
    for (wave.positions.constSlice()) |pos| {
        _ = try self.queueSpawnThing(&spawner_proto, pos);
    }
    self.curr_wave += 1;
}

pub fn update(self: *Room) Error!void {
    const plat = getPlat();
    self.ui_clicked = false;

    if (debug.enable_debug_controls and plat.input_buffer.keyIsJustPressed(.backtick)) {
        self.edit_mode = !self.edit_mode;
    }

    if (self.edit_mode) {
        if (plat.input_buffer.mouseBtnIsJustPressed(.left)) {
            const pos = plat.screenPosToCamPos(self.camera, plat.input_buffer.getCurrMousePos());
            //std.debug.print("spawn sheep at {d:0.2}, {d:0.2}\n", .{ pos.x, pos.y });
            _ = try self.queueSpawnThingByKind(.troll, pos);
        }
    } else {
        if (plat.input_buffer.keyIsJustPressed(.space)) {
            self.paused = !self.paused;
        }
    }
    for (self.spawn_queue.constSlice()) |id| {
        const t = self.getThingById(id);
        assert(t != null);
        const thing = t.?;
        assert(thing.alloc_state == .allocated);
        assert(thing.spawn_state == .spawning);
        thing.spawn_state = .spawned;
    }
    self.spawn_queue.len = 0;

    {
        const mouse_pos = plat.screenPosToCamPos(self.camera, plat.input_buffer.getCurrMousePos());
        self.moused_over_thing = null;
        var best_y = -std.math.inf(f32);
        for (&self.things.items) |*thing| {
            if (!thing.isActive()) continue;
            if (thing.selectable == null) continue;
            if (thing.pos.y < best_y) continue;

            const selectable = thing.selectable.?;
            const rect = geom.Rectf{
                .pos = thing.pos.sub(v2f(selectable.radius, selectable.height)),
                .dims = v2f(selectable.radius * 2, selectable.height),
            };
            //const top_circle_pos = thing.pos.sub(v2f(0, selectable.height));

            if (mouse_pos.dist(thing.pos) < selectable.radius or
                geom.pointIsInRectf(mouse_pos, rect)) //or
                //mouse_pos.dist(top_circle_pos) < selectable.radius)
            {
                best_y = thing.pos.y;
                self.moused_over_thing = thing.id;
            }
        }
    }

    if (!self.edit_mode and !self.paused) {
        // waves spawning
        if (self.curr_wave < self.waves.len) {
            // first wave spawns after fixed time
            if (self.curr_wave == 0) {
                if (self.first_wave_timer.tick(false)) {
                    try self.spawnCurrWave();
                }
            } else if (self.num_enemies_alive == 0) {
                try self.spawnCurrWave();
            }
        }
        // check if won or lost
        if (self.getPlayer()) |player| {
            if (player.hp) |hp| {
                if (hp.curr > 0) {
                    if (self.curr_wave >= self.waves.len and self.num_enemies_alive == 0) {
                        self.progress_state = .won;
                    } else {
                        self.progress_state = .none;
                    }
                } else {
                    self.progress_state = .lost;
                }
            }
        }
        // spell slots
        {
            const old = self.spell_slots.selected;
            try self.spell_slots.update(self);
            const new = self.spell_slots.selected;
            if (old != new) {
                self.ui_clicked = true;
            }
        }
        // things
        for (&self.things.items) |*thing| {
            if (!thing.isActive()) continue;
            try thing.update(self);
        }
        // fog
        self.fog.clearVisible();
        if (self.getPlayer()) |player| {
            self.camera.pos = player.pos;
            try self.fog.addVisibleCircle(self.tilemap.dims, player.pos, player.vision_range + player.coll_radius);
        }
    }

    for (self.free_queue.constSlice()) |id| {
        const t = self.getThingById(id);
        assert(t != null);
        const thing = t.?;
        assert(thing.alloc_state == .allocated);
        assert(thing.spawn_state == .freeable);
        self.things.free(id);
        if (thing.isEnemy()) self.num_enemies_alive -= 1;
    }
    self.free_queue.len = 0;

    // TODO might mess up edit modeu
    if (!self.edit_mode) {
        self.curr_tick += 1;
    }
}

pub fn render(self: *const Room) Error!void {
    if (self.render_texture == null) return;
    const plat = getPlat();

    const fog_enabled = !self.edit_mode;
    if (fog_enabled) {
        try self.fog.renderToTexture(self.camera);
    }

    plat.startRenderToTexture(self.render_texture.?);
    plat.clear(Colorf.darkgray);
    plat.setBlend(.render_tex_alpha);

    plat.startCamera2D(self.camera);

    try self.tilemap.debugDraw();
    //try self.tilemap.debugDrawGrid(self.camera);
    // exit
    for (self.init_params.packed_room.exits.constSlice()) |epos| {
        const color = if (self.progress_state == .won) Colorf.rgb(0.2, 0.1, 0.2) else Colorf.rgb(0.4, 0.4, 0.4);
        plat.circlef(epos, 20, .{ .fill_color = Colorf.rgb(0.4, 0.3, 0.4) });
        plat.circlef(epos.add(v2f(0, 2)), 19, .{ .fill_color = color });
    }

    // waves
    if (debug.show_waves) {
        for (self.waves.constSlice(), 0..) |wave, i| {
            for (wave.positions.constSlice()) |pos| {
                try plat.textf(pos, "{}", .{i}, .{ .center = true, .color = .magenta });
            }
        }
    }

    // spell targeting
    if (!self.edit_mode) {
        if (self.getConstPlayer()) |player| {
            if (self.spell_slots.getSelectedSlot()) |slot| {
                assert(slot.spell != null);
                try slot.spell.?.renderTargeting(self, player);
            }
        }
    }

    {
        var thing_arr = std.BoundedArray(*const Thing, @TypeOf(self.things).max_len){};
        const player = self.getConstPlayer();
        for (&self.things.items) |*thing| {
            if (!thing.isActive()) continue;
            if (fog_enabled) {
                if (player) |p| {
                    if (thing.pos.dist(p.pos) > p.vision_range + p.coll_radius + thing.coll_radius) {
                        continue;
                    }
                } else {
                    // no player? cant see anything
                    continue;
                }
            }
            thing_arr.append(thing) catch unreachable;
        }

        const SortStruct = struct {
            pub fn lessThan(_: void, lhs: *const Thing, rhs: *const Thing) bool {
                return lhs.pos.y < rhs.pos.y;
            }
        };
        std.sort.pdq(*const Thing, thing_arr.slice(), {}, SortStruct.lessThan);
        for (thing_arr.constSlice()) |thing| {
            try thing.renderUnder(self);
        }
        for (thing_arr.constSlice()) |thing| {
            try thing.render(self);
        }
        for (thing_arr.constSlice()) |thing| {
            try thing.renderOver(self);
        }
    }

    if (debug.show_tilemap_grid) {
        try self.tilemap.debugDrawGrid(self.camera);
    }
    plat.endCamera2D();

    if (fog_enabled) {
        const fog_texture_opt = .{
            .flip_y = true,
        };
        plat.setBlend(.multiply);
        plat.texturef(.{}, self.fog.render_tex.texture, fog_texture_opt);
        plat.setBlend(.render_tex_alpha);
    }

    if (self.edit_mode) {
        const opt: draw.TextOpt = .{ .center = true, .size = 50, .color = .white };
        const txt = "edit mode";
        const dims = (try plat.measureText(txt, opt)).add(v2f(10, 4));
        const p: V2f = v2f(plat.screen_dims_f.x * 0.5, plat.screen_dims_f.y - 50);
        plat.rectf(p.sub(dims.scale(0.5)), dims, .{ .fill_color = Colorf.black.fade(0.5) });
        try plat.textf(p, txt, .{}, opt);
    } else {
        try self.spell_slots.render(self);
        if (self.paused) {
            const opt: draw.TextOpt = .{ .center = true, .size = 50, .color = .white };
            const txt = "[paused]";
            const dims = (try plat.measureText(txt, opt)).add(v2f(10, 4));
            const p: V2f = v2f(plat.screen_dims_f.x * 0.5, plat.screen_dims_f.y - 50);
            plat.rectf(p.sub(dims.scale(0.5)), dims, .{ .fill_color = Colorf.black.fade(0.5) });
            try plat.textf(p, txt, .{}, opt);
        }
    }
    if (debug.show_num_enemies) {
        try plat.textf(v2f(10, 10), "num_enemies_alive: {}", .{self.num_enemies_alive}, .{ .color = .white });
    }

    plat.endRenderToTexture();
}
