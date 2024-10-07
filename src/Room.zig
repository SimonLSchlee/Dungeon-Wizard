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

pub const max_things_in_room = 128;
pub const max_spells_in_deck = 32;

pub const ThingBoundedArray = std.BoundedArray(pool.Id, max_things_in_room);
pub const SpellArray = std.BoundedArray(Spell, max_spells_in_deck);

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
deck: SpellArray = .{},
discard: SpellArray = .{},
fog: Fog = undefined,
ui_clicked: bool = false,
curr_tick: i64 = 0,
edit_mode: bool = false,
// reinit stuff, never needs saving or copying, probably?:
render_texture: ?Platform.RenderTexture2D = null,
next_pool_id: u32 = 0, // i hate this, can we change it?
seed: u64 = 0,
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

pub fn init(seed: u64) Error!Room {
    const plat = getPlat();
    const app = App.get();

    var ret: Room = .{
        .next_pool_id = 1,
        .things = Thing.Pool.init(0),
        .render_texture = plat.createRenderTexture("room", plat.screen_dims),
        .camera = .{
            .offset = plat.screen_dims_f.scale(0.5),
            .zoom = 1,
        },
        .fog = try Fog.init(),
        .rng = std.Random.DefaultPrng.init(seed),
        .seed = seed,
    };

    // temporaryyyy
    try ret.tilemap.initStr(app.data.levels[0]);

    // everything is done except spawning stuff
    try ret.reset();

    return ret;
}

fn clearThings(self: *Room) void {
    for (&self.things.items) |*thing| {
        if (thing.alloc_state != .allocated) continue;
        thing.deinit();
    }
    self.things = Thing.Pool.init(self.next_pool_id);
    self.next_pool_id += 1;
    self.spawn_queue.len = 0;
    self.free_queue.len = 0;
    self.player_id = null;
    self.spell_slots = .{};
    self.deck = .{};
    self.discard = .{};
}

pub fn reset(self: *Room) Error!void {
    self.clearThings();
    self.fog.clearAll();
    self.curr_tick = 0;
    self.rng.seed(self.seed);

    for (self.tilemap.spawns.constSlice()) |spawn| {
        std.debug.print("Room init: spawning a {any}\n", .{spawn.kind});
        if (try self.queueSpawnThingByKind(spawn.kind, spawn.pos)) |id| {
            if (spawn.kind == .player) {
                self.player_id = id;
            }
        }
    }
    // TODO placeholder
    const unherring = Spell.getProto(.unherring);
    const protec = Spell.getProto(.protec);
    const frost = Spell.getProto(.frost_vom);
    for (0..5) |_| {
        self.deck.append(unherring) catch break;
        self.deck.append(protec) catch break;
    }
    self.deck.append(frost) catch {};
    for (0..gameUI.SpellSlots.num_slots) |i| {
        if (self.drawSpell()) |spell| {
            self.spell_slots.fillSlot(spell, i);
        }
    }
}

fn reloadFromTilemapString(self: *Room, str: []const u8) Error!void {
    self.tilemap.deinit();
    try self.tilemap.initStr(str);
    try self.reset();
}

pub fn deinit(self: *Room) void {
    self.clearThings();
    self.fog.deinit();
    self.tilemap.deinit();
    if (self.render_texture) |tex| {
        getPlat().destroyRenderTexture(tex);
    }
}

pub fn queueSpawnThing(self: *Room, proto: *const Thing, pos: V2f) Error!?pool.Id {
    const t = self.things.alloc();
    if (t) |thing| {
        try proto.copyTo(thing);
        thing.spawn_state = .spawning;
        thing.pos = pos;
        try self.spawn_queue.append(thing.id);
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
    if (self.deck.len > 0) {
        const last = u.as(u32, self.deck.len - 1);
        const idx = u.as(usize, self.rng.random().intRangeAtMost(u32, 0, last));
        const spell = self.deck.swapRemove(idx);
        return spell;
    } else {
        self.deck.insertSlice(0, self.discard.constSlice()) catch unreachable;
    }
    return null;
}

pub fn discardSpell(self: *Room, spell: Spell) void {
    self.discard.append(spell) catch @panic("discard ran out of space");
}

pub fn update(self: *Room) Error!void {
    const plat = getPlat();
    self.ui_clicked = false;

    if (plat.input_buffer.keyIsJustPressed(.backtick)) {
        self.edit_mode = !self.edit_mode;
    }

    if (self.edit_mode) {
        if (plat.input_buffer.getNumberKeyJustPressed()) |num| {
            const app = App.get();
            const n: usize = if (num == 0) 9 else num - 1;
            if (n < app.data.levels.len) {
                const s = app.data.levels[n];
                try self.reloadFromTilemapString(s);
            }
        }
        if (plat.input_buffer.mouseBtnIsJustPressed(.left)) {
            const pos = plat.screenPosToCamPos(self.camera, plat.input_buffer.getCurrMousePos());
            //std.debug.print("spawn sheep at {d:0.2}, {d:0.2}\n", .{ pos.x, pos.y });
            _ = try self.queueSpawnThingByKind(.troll, pos);
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

    if (!self.edit_mode) {
        {
            const old = self.spell_slots.selected;
            try self.spell_slots.update(self);
            const new = self.spell_slots.selected;
            if (old != new) {
                self.ui_clicked = true;
            }
        }

        for (&self.things.items) |*thing| {
            if (!thing.isActive()) continue;
            try thing.update(self);
        }

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
        thing.deinit();
        self.things.free(id);
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

    if (self.getConstPlayer()) |player| {
        if (self.spell_slots.getSelectedSlot()) |slot| {
            assert(slot.spell != null);
            try slot.spell.?.renderTargeting(self, player);
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
    }

    plat.endRenderToTexture();
}
