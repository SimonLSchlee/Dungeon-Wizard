const std = @import("std");
const utl = @import("util.zig");

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

const Thing = @This();
const App = @import("App.zig");
const getPlat = App.getPlat;
const Room = @import("Room.zig");
const TileMap = @import("TileMap.zig");
const data = @import("data.zig");
const pool = @import("pool.zig");
const sprites = @import("sprites.zig");

const player = @import("Player.zig");
const enemies = @import("enemies.zig");
const Spell = @import("Spell.zig");
pub const StatusEffect = @import("StatusEffect.zig");
pub const Collision = @import("Collision.zig");

pub const Kind = enum {
    creature,
    projectile,
    shield,
    spawner,
};

pub const CreatureKind = enum {
    player,
    troll,
    gobbow,
    sharpboi,
    impling,
    bat,
};

pub const Pool = pool.BoundedPool(Thing, Room.max_things_in_room);
// TODO wrap
pub const Id = pool.Id;

id: Id = undefined,
alloc_state: pool.AllocState = undefined,
spawn_state: enum {
    instance, // not in any pool
    spawning, // in pool. yet to be spawned
    spawned, // active in the world
    freeable, // in pool. yet to be freed
} = .instance,
//
kind: Kind = undefined,
creature_kind: ?CreatureKind = null,
pos: V2f = .{},
vel: V2f = .{},
dir: V2f = V2f.right,
dirv: f32 = 0,
coll_radius: f32 = 0,
coll_mask: Collision.Mask = .{},
coll_layer: Collision.Mask = .{},
last_coll: ?Collision = null,
vision_range: f32 = 0,
accel_params: AccelParams = .{},
dir_accel_params: DirAccelParams = .{},
dbg: struct {
    coords_searched: std.BoundedArray(V2i, 128) = .{},
    last_tick_hitbox_was_active: i64 = -10000,
} = .{},
controller: union(enum) {
    none: void,
    player: player.InputController,
    enemy: enemies.AIController,
    spell: Spell.Controller,
    projectile: ProjectileController,
    spawner: SpawnerController,
} = .none,
renderer: union(enum) {
    none: void,
    creature: CreatureRenderer,
    shape: ShapeRenderer,
    spawner: SpawnerRenderer,
} = .none,
animator: union(enum) {
    none: void,
    creature: sprites.CreatureAnimator,
} = .none,
path: std.BoundedArray(V2f, 32) = .{},
hitbox: ?HitBox = null,
hurtbox: ?HurtBox = null,
hp: ?HP = null,
faction: Faction = .object,
selectable: ?struct {
    // its a half capsule shape
    radius: f32 = 20,
    height: f32 = 50,
} = null,
statuses: StatusEffect.StatusArray = StatusEffect.proto_array,
enemy_difficulty: f32 = 0,

pub const Faction = enum {
    object,
    neutral,
    player,
    ally,
    enemy,
    bezerk,

    pub const Mask = std.EnumSet(Faction);
    // factions' natural enemies - who they will aggro on, and use to supply hitbox masks for (some, not all) projectiles
    pub const opposing_masks = std.EnumArray(Faction, Faction.Mask).init(.{
        .object = .{},
        .neutral = .{},
        .player = Faction.Mask.initMany(&.{ .enemy, .bezerk }),
        .ally = Faction.Mask.initMany(&.{ .enemy, .bezerk }),
        .enemy = Faction.Mask.initMany(&.{ .player, .ally, .bezerk }),
        .bezerk = Faction.Mask.initMany(&.{ .neutral, .player, .ally, .enemy, .bezerk }),
    });
};

pub const HP = struct {
    curr: f32 = 10,
    max: f32 = 10,

    pub const faction_colors = std.EnumArray(Faction, Colorf).init(.{
        .object = Colorf.gray,
        .neutral = Colorf.gray,
        .player = Colorf.green,
        .ally = Colorf.rgb(0, 0.5, 1),
        .enemy = Colorf.red,
        .bezerk = Colorf.orange,
    });

    pub fn init(max: f32) HP {
        return .{
            .curr = max,
            .max = max,
        };
    }
};

pub const HitEffect = struct {
    damage: f32 = 1,
    status_stacks: StatusEffect.StacksArray = StatusEffect.StacksArray.initDefault(0, .{}),
    force: V2f = .{},
};

pub const HitBox = struct {
    rel_pos: V2f = .{},
    radius: f32 = 0,
    mask: Faction.Mask = Faction.Mask.initEmpty(),
    active: bool = false,
    deactivate_on_update: bool = true,
    deactivate_on_hit: bool = true,
    effect: HitEffect,

    pub fn update(_: *HitBox, self: *Thing, room: *Room) void {
        const hitbox = &self.hitbox.?;
        if (!hitbox.active) return;
        // for debug vis
        self.dbg.last_tick_hitbox_was_active = room.curr_tick;

        const pos = self.pos.add(hitbox.rel_pos);
        for (&room.things.items) |*thing| {
            if (!thing.isActive()) continue;

            if (thing.hurtbox == null) continue;
            var hurtbox = &thing.hurtbox.?;
            if (!hitbox.mask.contains(thing.faction)) continue;
            const hurtbox_pos = thing.pos.add(hurtbox.rel_pos);
            const dist = pos.dist(hurtbox_pos);
            if (dist > hitbox.radius + hurtbox.radius) continue;
            // hit!
            hurtbox.hit(thing, room, hitbox.effect);
            //std.debug.print("{any}: I hit {any}\n", .{ self.kind, thing.kind });
            if (hitbox.deactivate_on_hit) {
                hitbox.active = false;
                break;
            }
        }
        if (hitbox.deactivate_on_update) {
            hitbox.active = false;
        }
    }
};

pub const HurtBox = struct {
    rel_pos: V2f = .{},
    radius: f32 = 0,

    pub fn hit(_: *HurtBox, self: *Thing, room: *Room, effect: HitEffect) void {
        const status_protect = self.statuses.getPtr(.protected);
        if (status_protect.stacks > 0) {
            status_protect.stacks -= 1;
            return;
        }
        if (self.hp) |*hp| {
            hp.curr = utl.clampf(hp.curr - effect.damage, 0, hp.max);
        }
        for (&self.statuses.values) |*status| {
            const stacks = effect.status_stacks.get(status.kind);
            status.stacks += stacks;
        }
        if (self.hp) |hp| {
            if (hp.curr == 0) {
                const mint_status = self.statuses.get(.mint);
                const run = &App.get().run;
                run.gold += mint_status.stacks;

                // TODO do this elsewhere, better
                self.deferFree(room);
            }
        }
    }
};

pub const SpawnerRenderer = struct {
    creature_kind: sprites.CreatureAnim.Kind,
    base_circle_radius: f32,
    sprite_tint: Colorf = .blank,
    base_circle_color: Colorf = .blank,

    pub fn renderUnder(self: *const Thing, _: *const Room) Error!void {
        const renderer = &self.renderer.spawner;
        const plat = App.getPlat();
        plat.circlef(self.pos, renderer.base_circle_radius, .{ .fill_color = renderer.base_circle_color });
    }

    pub fn render(self: *const Thing, _: *const Room) Error!void {
        const renderer = &self.renderer.spawner;
        const plat = App.getPlat();
        const anim = App.get().data.getCreatureAnim(renderer.creature_kind, .idle).?;
        const frame = anim.getRenderFrame(V2f.right, 0);
        const tint: Colorf = renderer.sprite_tint;
        const opt = draw.TextureOpt{
            .origin = frame.origin,
            .src_pos = frame.pos.toV2f(),
            .src_dims = frame.size.toV2f(),
            .uniform_scaling = 4,
            .tint = tint,
        };
        plat.texturef(self.pos, frame.texture, opt);
    }
};

pub const SpawnerController = struct {
    timer: utl.TickCounter = utl.TickCounter.init(1 * core.fups_per_sec / 2),
    state: enum {
        fade_in_circle,
        fade_in_creature,
        fade_out_circle,
    } = .fade_in_circle,
    creature_kind: CreatureKind,

    pub fn update(self: *Thing, room: *Room) Error!void {
        const spawner = &self.controller.spawner;
        switch (spawner.state) {
            .fade_in_circle => {
                self.renderer.spawner.base_circle_color = Colorf.white.fade(spawner.timer.remapTo0_1());
                if (spawner.timer.tick(true)) {
                    spawner.timer = utl.TickCounter.init(1 * core.fups_per_sec);
                    spawner.state = .fade_in_creature;
                }
            },
            .fade_in_creature => {
                self.renderer.spawner.sprite_tint = Colorf.black.fade(0).lerp(Colorf.white, spawner.timer.remapTo0_1());
                if (spawner.timer.tick(true)) {
                    _ = try room.queueSpawnCreatureByKind(spawner.creature_kind, self.pos);
                    spawner.state = .fade_out_circle;
                }
            },
            .fade_out_circle => {
                self.renderer.spawner.sprite_tint = .blank;
                self.renderer.spawner.base_circle_color = Colorf.white.fade(1 - spawner.timer.remapTo0_1());
                if (spawner.timer.tick(false)) {
                    self.deferFree(room);
                }
            },
        }
    }

    pub fn prototype(creature_kind: CreatureKind) Thing {
        const proto: Thing = App.get().data.creatures.get(creature_kind);
        return .{
            .kind = .spawner,
            .controller = .{
                .spawner = .{
                    .creature_kind = creature_kind,
                },
            },
            .renderer = .{
                .spawner = .{
                    .creature_kind = proto.animator.creature.creature_kind,
                    .base_circle_radius = proto.renderer.creature.draw_radius,
                },
            },
            .faction = proto.faction, // to ensure num_enemies_alive > 0
        };
    }
};

pub const ProjectileController = struct {
    pub fn update(self: *Thing, room: *Room) Error!void {
        assert(self.spawn_state == .spawned);
        if (self.hitbox) |hitbox| {
            if (!hitbox.active) {
                self.deferFree(room);
            }
        }
        self.moveAndCollide(room);
        if (self.last_coll) |_| {
            self.deferFree(room);
        }
    }
};

pub const ShapeRenderer = struct {
    pub const PointArray = std.BoundedArray(V2f, 32);

    kind: union(enum) {
        circle: struct {
            radius: f32,
        },
        sector: struct {
            start_ang_rads: f32,
            end_ang_rads: f32,
            radius: f32,
        },
        arrow: struct {
            thickness: f32,
            length: f32,
        },
        poly: PointArray,
    },
    poly_opt: draw.PolyOpt,
    draw_under: bool = false,
    draw_normal: bool = true,
    draw_over: bool = false,

    fn _render(self: *const Thing, renderer: *const ShapeRenderer, _: *const Room) void {
        const plat = App.getPlat();
        switch (renderer.kind) {
            .circle => |s| {
                plat.circlef(self.pos, s.radius, renderer.poly_opt);
            },
            .sector => |s| {
                plat.sectorf(self.pos, s.radius, s.start_ang_rads, s.end_ang_rads, renderer.poly_opt);
            },
            .arrow => |s| {
                const color: Colorf = if (renderer.poly_opt.fill_color) |c| c else .white;
                plat.arrowf(self.pos, self.pos.add(self.dir.scale(s.length)), s.thickness, color);
            },
            else => @panic("unimplemented"),
        }
    }
    pub fn renderUnder(self: *const Thing, room: *const Room) Error!void {
        const renderer = &self.renderer.shape;
        if (renderer.draw_under) {
            _render(self, renderer, room);
        }
    }
    pub fn render(self: *const Thing, room: *const Room) Error!void {
        const renderer = &self.renderer.shape;
        if (renderer.draw_normal) {
            _render(self, renderer, room);
        }
    }
    pub fn renderOver(self: *const Thing, room: *const Room) Error!void {
        const renderer = &self.renderer.shape;
        if (renderer.draw_over) {
            _render(self, renderer, room);
        }
    }
};

pub const CreatureRenderer = struct {
    draw_radius: f32 = 20,
    draw_color: Colorf = Colorf.red,

    pub fn renderUnder(self: *const Thing, _: *const Room) Error!void {
        assert(self.spawn_state == .spawned);
        const plat = getPlat();
        const renderer = &self.renderer.creature;

        plat.circlef(self.pos, renderer.draw_radius, .{
            .fill_color = null,
            .outline_color = renderer.draw_color,
        });
        const arrow_start = self.pos.add(self.dir.scale(renderer.draw_radius));
        const arrow_end = self.pos.add(self.dir.scale(renderer.draw_radius + 5));
        plat.arrowf(arrow_start, arrow_end, 5, renderer.draw_color);
    }

    pub fn render(self: *const Thing, room: *const Room) Error!void {
        assert(self.spawn_state == .spawned);
        const plat = getPlat();

        if (debug.show_selectable) {
            if (self.selectable) |s| {
                if (room.moused_over_thing) |id| {
                    if (id.eql(self.id)) {
                        const opt = draw.PolyOpt{ .fill_color = Colorf.cyan };
                        plat.circlef(self.pos, s.radius, opt);
                        plat.rectf(self.pos.sub(v2f(s.radius, s.height)), v2f(s.radius * 2, s.height), opt);
                    }
                }
            }
        }

        const animator = self.animator.creature;
        const frame = animator.getCurrRenderFrame(self.dir);
        const tint: Colorf = if (self.statuses.get(.frozen).stacks > 0) StatusEffect.proto_array.get(.frozen).color else .white;
        const opt = draw.TextureOpt{
            .origin = frame.origin,
            .src_pos = frame.pos.toV2f(),
            .src_dims = frame.size.toV2f(),
            .uniform_scaling = 4,
            .tint = tint,
        };
        plat.texturef(self.pos, frame.texture, opt);

        const protected = self.statuses.get(.protected);
        if (protected.stacks > 0) {
            // TODO dont use select radius
            const r = if (self.selectable) |s| s.height * 0.5 else self.coll_radius;
            const shield_center = self.pos.sub(v2f(0, r));
            const popt = draw.PolyOpt{
                .fill_color = null,
                .outline_color = StatusEffect.proto_array.get(.protected).color,
            };
            for (0..utl.as(usize, protected.stacks)) |i| {
                plat.circlef(shield_center, r * 2 + 2 + utl.as(f32, i) * 2, popt);
            }
        }
    }

    pub fn renderOver(self: *const Thing, _: *const Room) Error!void {
        assert(self.spawn_state == .spawned);
        const plat = getPlat();
        const renderer = &self.renderer.creature;

        const hp_height = 6;
        const hp_width = renderer.draw_radius * 2;
        const hp_y_offset = if (self.selectable) |s| s.height + 15 else renderer.draw_radius * 3.5;
        const hp_offset = v2f(-hp_width * 0.5, -hp_y_offset);

        if (self.hp) |hp| {
            const curr_width = utl.remapClampf(0, hp.max, 0, hp_width, hp.curr);
            plat.rectf(self.pos.add(hp_offset), v2f(hp_width, hp_height), .{ .fill_color = Colorf.black });
            plat.rectf(self.pos.add(hp_offset), v2f(curr_width, hp_height), .{ .fill_color = HP.faction_colors.get(self.faction) });
        }
        // debug draw statuses
        const status_height = 14;
        const status_y_offset = hp_y_offset - (hp_height + 3);
        var status_pos = self.pos.add(v2f(-hp_width * 0.5, -status_y_offset));
        for (self.statuses.values) |status| {
            if (status.stacks == 0) continue;
            const text = try utl.bufPrintLocal("{}", .{status.stacks});
            const text_dims = try plat.measureText(text, .{ .size = status_height - 1 });
            const status_box_width = text_dims.x;
            const text_color = Colorf.getContrasting(status.color);
            plat.rectf(status_pos, v2f(status_box_width, status_height), .{ .fill_color = status.color });
            try plat.textf(status_pos, "{s}", .{text}, .{ .size = status_height - 1, .color = text_color });
            status_pos.x += status_box_width;
        }
    }
};

pub const DefaultController = struct {
    pub fn update(_: *Thing, _: *Room) Error!void {}
};

fn updateController(self: *Thing, room: *Room) Error!void {
    switch (self.controller) {
        inline else => |c| {
            const C = @TypeOf(c);
            if (std.meta.hasMethod(C, "update")) {
                try C.update(self, room);
            }
        },
    }
}

pub fn update(self: *Thing, room: *Room) Error!void {
    if (self.statuses.get(.frozen).stacks == 0) {
        try updateController(self, room);
        if (self.statuses.get(.promptitude).stacks > 0) {
            try updateController(self, room);
        }
    }
    if (self.hitbox) |*hitbox| {
        hitbox.update(self, room);
    }
    for (&self.statuses.values) |*status| {
        if (status.cd_type != .no_cd and status.stacks > 0) {
            if (status.cooldown.tick(true)) {
                switch (status.cd_type) {
                    .remove_one_stack => {
                        status.stacks -= 1;
                    },
                    .remove_all_stacks => {
                        status.stacks = 0;
                    },
                    else => unreachable,
                }
                switch (status.kind) {
                    .blackmailed => if (status.stacks == 0) {
                        assert(self.creature_kind != null);
                        const proto = App.get().data.creatures.get(self.creature_kind.?);
                        self.faction = proto.faction;
                    },
                    else => {},
                }
            }
        }
    }
}

pub fn renderUnder(self: *const Thing, room: *const Room) Error!void {
    switch (self.renderer) {
        inline else => |r| {
            const R = @TypeOf(r);
            if (std.meta.hasMethod(R, "renderUnder")) {
                try R.renderUnder(self, room);
            }
        },
    }
}

pub fn render(self: *const Thing, room: *const Room) Error!void {
    switch (self.renderer) {
        inline else => |r| {
            const R = @TypeOf(r);
            if (std.meta.hasMethod(R, "render")) {
                try R.render(self, room);
            }
        },
    }
}

pub fn renderOver(self: *const Thing, room: *const Room) Error!void {
    switch (self.renderer) {
        inline else => |r| {
            const R = @TypeOf(r);
            if (std.meta.hasMethod(R, "renderOver")) {
                try R.renderOver(self, room);
            }
        },
    }

    const plat = App.getPlat();
    if (debug.show_thing_collisions) {
        if (self.last_coll) |coll| {
            plat.arrowf(coll.pos, coll.pos.add(coll.normal.scale(self.coll_radius * 0.75)), 3, Colorf.red);
        }
    }
    if (debug.show_thing_coords_searched) {
        if (self.path.len > 0) {
            for (self.dbg.coords_searched.constSlice()) |coord| {
                plat.circlef(TileMap.tileCoordToCenterPos(coord), 10, .{ .outline_color = Colorf.white, .fill_color = null });
            }
        }
    }
    if (debug.show_thing_paths) {
        if (self.path.len > 0) {
            try self.debugDrawPath(room);
        }
    }
    if (debug.show_hitboxes) {
        if (self.hitbox) |hitbox| {
            const ticks_since = room.curr_tick - self.dbg.last_tick_hitbox_was_active;
            if (ticks_since < 120) {
                const color = Colorf.red.fade(utl.remapClampf(0, 120, 0.5, 0, utl.as(f32, ticks_since)));
                const pos: V2f = self.pos.add(hitbox.rel_pos);
                plat.circlef(pos, hitbox.radius, .{ .fill_color = color });
            }
        }
        if (self.hurtbox) |hurtbox| {
            const color = Colorf.yellow.fade(0.5);
            plat.circlef(self.pos.add(hurtbox.rel_pos), hurtbox.radius, .{ .fill_color = color });
        }
    }
}

pub fn deferFree(self: *Thing, room: *Room) void {
    assert(self.spawn_state == .spawned);
    self.spawn_state = .freeable;
    room.free_queue.append(self.id) catch @panic("out of free_queue space!");
}

// copy retaining original id, alloc state and spawn_state
pub fn copyTo(self: *const Thing, other: *Thing) Error!void {
    const id = other.id;
    const alloc_state = other.alloc_state;
    const spawn_state = other.spawn_state;
    other.* = self.*;
    other.id = id;
    other.alloc_state = alloc_state;
    other.spawn_state = spawn_state;
}

fn defaultUpdate(self: *Thing, room: *Room) Error!void {
    assert(self.spawn_state == .spawned);
    self.moveAndCollide(room);
}

pub fn isActive(self: *const Thing) bool {
    return self.alloc_state == .allocated and self.spawn_state == .spawned;
}

pub fn moveAndCollide(self: *Thing, room: *Room) void {
    var num_iters: i32 = 0;

    self.last_coll = null;
    self.pos = self.pos.add(self.vel);

    while (num_iters < 5) {
        var _coll: ?Collision = null;

        if (self.coll_mask.contains(.creature)) {
            _coll = Collision.getNextCircleCollisionWithThings(self.pos, self.coll_radius, self.coll_mask, &.{self.id}, room);
        }
        if (_coll == null and self.coll_mask.contains(.tile)) {
            _coll = Collision.getCircleCollisionWithTiles(self.pos, self.coll_radius, &room.tilemap);
        }

        if (_coll) |coll| {
            self.last_coll = coll;
            // push out
            if (coll.pen_dist > 0) {
                self.pos = coll.pos.add(coll.normal.scale(self.coll_radius + 1));
            }
            // remove -normal component from vel, isn't necessary with current implementation
            //const d = coll_normal.dot(self.vel);
            //self.vel = self.vel.sub(coll_normal.scale(d + 0.1));
        }

        num_iters += 1;
    }
}

pub fn followPathGetNextPoint(self: *Thing, dist: f32) V2f {
    var ret: V2f = self.pos;

    if (self.path.len > 0) {
        assert(self.path.len >= 2);
        const curr_coord = TileMap.posToTileCoord(self.pos);
        const next_pos = self.path.buffer[1];
        const next_coord = TileMap.posToTileCoord(next_pos);
        const curr_to_next = next_pos.sub(self.pos);
        var remove_next = false;

        ret = next_pos;

        // for last square, only care about radius. for others, enter the square
        if ((self.path.len == 2 and curr_to_next.length() <= dist) or (self.path.len > 2 and curr_coord.eql(next_coord))) {
            remove_next = true;
        }

        if (remove_next) {
            _ = self.path.orderedRemove(0);
            if (self.path.len == 1) {
                _ = self.path.orderedRemove(0);
                ret = self.pos;
            }
        }
    }

    return ret;
}

pub fn findPath(self: *Thing, room: *Room, goal: V2f) Error!void {
    self.path = try room.tilemap.findPathThetaStar(getPlat().heap, self.pos, goal, self.coll_radius, &self.dbg.coords_searched);
    if (self.path.len == 0) {
        self.path.append(self.pos) catch unreachable;
        self.path.append(goal) catch unreachable;
    }
}

pub const DirAccelParams = struct {
    ang_accel: f32 = utl.pi * 0.002,
    max_ang_vel: f32 = utl.pi * 0.03,
};

pub fn updateDir(self: *Thing, desired_dir: V2f, params: DirAccelParams) void {
    const n = desired_dir.normalizedOrZero();
    if (!n.isZero()) {
        const a_dir: f32 = if (self.dir.cross(n) > 0) 1 else -1;
        const cos = self.dir.dot(n);
        const ang = std.math.acos(cos);

        self.dirv += a_dir * params.ang_accel;
        const abs_dirv = @abs(self.dirv);
        if (@abs(ang) <= abs_dirv * 2) {
            self.dir = n;
            self.dirv = 0;
        } else {
            if (abs_dirv > params.max_ang_vel) self.dirv = a_dir * params.max_ang_vel;
            self.dir = self.dir.rotRadians(self.dirv);
        }
    }
}

pub const AccelParams = struct {
    accel: f32 = 0.05,
    friction: f32 = 0.02,
    max_speed: f32 = 0.8,
};

pub fn updateVel(self: *Thing, accel_dir: V2f, params: AccelParams) void {
    const speed_limit: f32 = 20;
    const min_speed_threshold = 0.001;

    const accel = accel_dir.scale(params.accel);
    const len = self.vel.length();
    var new_vel = self.vel;
    var len_after_accel: f32 = len;

    // max speed isn't a hard limit - we just can't accelerate past it
    // this allows being over max speed if it changed over time, or something else accelerated us
    if (len < params.max_speed) {
        new_vel = self.vel.add(accel);
        len_after_accel = new_vel.length();
        if (len_after_accel > params.max_speed) {
            len_after_accel = params.max_speed;
            new_vel = new_vel.clampLength(params.max_speed);
        }
    }

    if (len_after_accel - params.friction > min_speed_threshold) {
        var n = new_vel.scale(1 / len_after_accel);
        new_vel = new_vel.sub(n.scale(params.friction));
        // speed limit is a hard limit. don't go past it
        new_vel = new_vel.clampLength(speed_limit);
    } else {
        new_vel = .{};
    }

    self.vel = new_vel;
}

pub fn debugDrawPath(self: *const Thing, room: *const Room) Error!void {
    const plat = getPlat();
    const inv_zoom = 1 / room.camera.zoom;
    const line_thickness = inv_zoom;
    for (0..self.path.len - 1) |i| {
        plat.arrowf(self.path.buffer[i], self.path.buffer[i + 1], line_thickness, Colorf.green);
        //p.linef(self.path.buffer[i], self.path.buffer[i + 1], line_thickness, Colorf.green);
    }
}

pub fn isEnemy(self: *const Thing) bool {
    if (self.faction == .enemy) return true;
    if (self.statuses.get(.blackmailed).stacks > 0) return true;

    return false;
}
