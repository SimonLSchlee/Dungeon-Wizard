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

const App = @import("App.zig");
const getPlat = App.getPlat;
const Thing = @import("Thing.zig");
const Room = @import("Room.zig");
const TileMap = @import("TileMap.zig");

const AttackType = union(enum) {
    melee: struct {
        lunge_accel: ?Thing.AccelParams = null,
    },
    projectile: EnemyProjectile,
};

const EnemyProjectile = enum {
    arrow,
};

fn gobbowArrow(self: *const Thing, room: *Room) Error!void {
    const arrow = Thing{
        .kind = .projectile,
        .coll_radius = 5,
        .vel = self.dir.scale(4),
        .dir = self.dir,
        .coll_mask = Thing.Collision.Mask.initMany(&.{.tile}),
        .controller = .{ .projectile = .{} },
        .renderer = .{ .shape = .{
            .kind = .{ .arrow = .{
                .length = 35,
                .thickness = 4,
            } },
            .poly_opt = .{ .fill_color = draw.Coloru.rgb(220, 172, 89).toColorf() },
        } },
        .hitbox = .{
            .active = true,
            .deactivate_on_hit = true,
            .deactivate_on_update = false,
            .mask = Thing.Faction.opposing_masks.get(self.faction),
            .effect = .{ .damage = 7 },
            .radius = 4,
            .rel_pos = self.dir.scale(28),
        },
    };
    assert(try room.queueSpawnThing(&arrow, self.pos) != null);
}

pub fn getThingsInRadius(self: *Thing, room: *Room, radius: f32, buf: []*Thing) usize {
    var num: usize = 0;
    for (&room.things.items) |*thing| {
        if (num >= buf.len) break;
        if (!thing.isActive()) continue;
        if (thing.id.eql(self.id)) continue;

        const dist = thing.pos.dist(self.pos);

        if (dist < radius) {
            buf[num] = thing;
            num += 1;
        }
    }
    return num;
}

pub fn getNearestOpposingThing(self: *Thing, room: *Room) ?*Thing {
    var closest_dist = std.math.inf(f32);
    var closest: ?*Thing = null;
    for (&room.things.items) |*other| {
        if (!other.isActive()) continue;
        if (other.id.eql(self.id)) continue;
        if (!Thing.Faction.opposing_masks.get(self.faction).contains(other.faction)) continue;
        if (other.isInvisible()) continue;
        const dist = other.pos.dist(self.pos);
        if (dist < closest_dist) {
            closest_dist = dist;
            closest = other;
        }
    }
    return closest;
}

pub const AIController = struct {
    state: enum {
        idle,
        pursue,
        attack,
    } = .idle,
    ticks_in_state: i64 = 0,
    target: ?Thing.Id = null,
    attack_range: f32 = 40,
    attack_cooldown: utl.TickCounter = utl.TickCounter.initStopped(60),
    can_turn_during_attack: bool = true,
    attack_type: AttackType = .{ .melee = .{} },
    LOS_thiccness: f32 = 10,

    pub fn update(self: *Thing, room: *Room) Error!void {
        assert(self.spawn_state == .spawned);
        const nearest_target = getNearestOpposingThing(self, room);
        const ai = &self.controller.enemy;

        // always go for the nearest targeet
        if (nearest_target) |t| {
            ai.target = t.id;
        } else {
            ai.target = null;
        }

        self.renderer.creature.draw_color = Colorf.yellow;
        _ = ai.attack_cooldown.tick(false);
        ai.state = state: switch (ai.state) {
            .idle => {
                if (ai.target) |_| {
                    ai.ticks_in_state = 0;
                    continue :state .pursue;
                }
                self.updateVel(.{}, .{});
                _ = self.animator.creature.play(.idle, .{ .loop = true });
                break :state .idle;
            },
            .pursue => {
                const target = blk: {
                    if (ai.target) |t_id| {
                        if (room.getThingById(t_id)) |t| {
                            break :blk t;
                        }
                    }
                    ai.target = null;
                    ai.ticks_in_state = 0;
                    continue :state .idle;
                };
                const dist = target.pos.dist(self.pos);
                const range = @max(dist - self.coll_radius - target.coll_radius, 0);
                if (range <= ai.attack_range and room.tilemap.isLOSBetweenThicc(self.pos, target.pos, ai.LOS_thiccness)) {
                    // in range, but have to wait for cooldown before starting attack
                    if (ai.attack_cooldown.running) {
                        self.updateVel(.{}, .{});
                        if (dist > 0.001) {
                            self.dir = target.pos.sub(self.pos).normalized();
                        }
                        _ = self.animator.creature.play(.idle, .{ .loop = true });
                    } else {
                        ai.ticks_in_state = 0;
                        continue :state .attack;
                    }
                } else {
                    _ = self.animator.creature.play(.move, .{ .loop = true });
                    try self.findPath(room, target.pos);
                    const p = self.followPathGetNextPoint(10);
                    self.updateVel(p.sub(self.pos).normalizedOrZero(), self.accel_params);
                    if (!self.vel.isAlmostZero()) {
                        self.dir = self.vel.normalized();
                    }
                }
                break :state .pursue;
            },
            .attack => {
                if (ai.ticks_in_state == 0) {
                    ai.can_turn_during_attack = true;
                }
                // if target no longer exists, go idle
                const target = blk: {
                    if (ai.target) |t_id| {
                        if (room.getThingById(t_id)) |t| {
                            break :blk t;
                        }
                    }
                    ai.target = null;
                    ai.ticks_in_state = 0;
                    continue :state .idle;
                };
                const dist = target.pos.dist(self.pos);
                // dont want it to be cancelable
                //const range = @max(dist - self.coll_radius - target.coll_radius, 0);
                // unless out of range, then pursue
                //if (range > ai.attack_range) {
                //    ai.ticks_in_state = 0;
                //    continue :state .pursue;
                //}
                // face le target, unless past point of no return
                if (ai.can_turn_during_attack and dist > 0.001) {
                    self.dir = target.pos.sub(self.pos).normalized();
                }

                switch (ai.attack_type) {
                    .melee => |m| {
                        self.updateVel(.{}, .{});
                        const events = self.animator.creature.play(.attack, .{ .loop = true });
                        if (events.contains(.end)) {
                            self.updateVel(.{}, .{});
                            //std.debug.print("attack end\n", .{});
                            if (self.hitbox) |*hitbox| {
                                hitbox.active = false;
                            }
                            if (m.lunge_accel) |accel_params| {
                                self.coll_mask.insert(.creature);
                                self.coll_layer.insert(.creature);
                                self.updateVel(.{}, .{ .friction = accel_params.max_speed });
                            }
                            ai.attack_cooldown.restart();
                            // must re-enter attack via pursue (once cooldown expires)
                            ai.ticks_in_state = 0;
                            continue :state .pursue;
                        }
                        if (events.contains(.commit)) {
                            ai.can_turn_during_attack = false;
                        }
                        if (events.contains(.hit)) {
                            self.renderer.creature.draw_color = Colorf.red;
                            if (self.hitbox) |*hitbox| {
                                //std.debug.print("hit targetu\n", .{});
                                hitbox.mask = Thing.Faction.opposing_masks.get(self.faction);
                                hitbox.rel_pos = self.dir.scale(hitbox.rel_pos.length());
                                hitbox.active = true;
                                if (App.get().data.sounds.get(.thwack)) |s| {
                                    App.getPlat().playSound(s);
                                }
                            }
                            if (m.lunge_accel) |accel_params| {
                                self.coll_mask.remove(.creature);
                                self.coll_layer.remove(.creature);
                                self.updateVel(self.dir, accel_params);
                            }
                        }
                    },
                    .projectile => |proj_name| {
                        self.updateVel(.{}, .{});
                        const events = self.animator.creature.play(.attack, .{ .loop = true });
                        if (events.contains(.end)) {
                            //std.debug.print("attack end\n", .{});
                            ai.attack_cooldown.restart();
                            // must re-enter attack via pursue (once cooldown expires)
                            ai.ticks_in_state = 0;
                            continue :state .pursue;
                        }
                        if (events.contains(.commit)) {
                            ai.can_turn_during_attack = false;
                        }
                        if (events.contains(.hit)) {
                            self.renderer.creature.draw_color = Colorf.red;
                            switch (proj_name) {
                                .arrow => {
                                    try gobbowArrow(self, room);
                                },
                            }
                        }
                    },
                }
                break :state .attack;
            },
        };
        ai.ticks_in_state += 1;

        self.moveAndCollide(room);
    }
};

pub const HidingPlacesArray = std.BoundedArray(struct { pos: V2f, fleer_dist: f32, flee_from_dist: f32 }, 32);
pub fn getHidingPlaces(room: *const Room, fleer_pos: V2f, flee_from_pos: V2f, min_flee_dist: f32) Error!HidingPlacesArray {
    const plat = getPlat();
    const tilemap = &room.tilemap;
    const start_coord = TileMap.posToTileCoord(fleer_pos);
    var places = HidingPlacesArray{};
    var queue = std.BoundedArray(V2i, 128){};
    var seen = std.AutoArrayHashMap(V2i, void).init(plat.heap);
    defer seen.deinit();
    try seen.put(start_coord, {});
    queue.append(start_coord) catch unreachable;

    while (queue.len > 0) {
        const curr = queue.orderedRemove(0);
        const pos = TileMap.tileCoordToCenterPos(curr);
        const flee_from_dist = pos.dist(flee_from_pos);
        const fleer_dist = pos.dist(fleer_pos);
        if (fleer_dist > min_flee_dist) {
            places.append(.{ .pos = pos, .fleer_dist = fleer_dist, .flee_from_dist = flee_from_dist }) catch {};
        }
        if (places.len >= places.buffer.len) break;

        for (TileMap.neighbor_dirs) |dir| {
            const dir_v = TileMap.neighbor_dirs_coords.get(dir);
            const next = curr.add(dir_v);
            //std.debug.print("neighbor {}, {}\n", .{ next.p.x, next.p.y });
            if (tilemap.tiles.get(next)) |tile| {
                if (!tile.passable) continue;
            }
            if (seen.get(next)) |_| continue;
            try seen.put(next, {});
            queue.append(next) catch break;
        }
    }
    return places;
}

pub const AcolyteAIController = struct {
    wander_dir: V2f = .{},
    state: enum {
        idle,
        flee,
        cast,
    } = .idle,
    ticks_in_state: i64 = 0,
    flee_range: f32 = 250,
    cast_cooldown: utl.TickCounter = utl.TickCounter.initStopped(5 * core.fups_per_sec),
    flee_cooldown: utl.TickCounter = utl.TickCounter.initStopped(1 * core.fups_per_sec),
    // debug
    hiding_places: HidingPlacesArray = .{},
    to_enemy: V2f = .{},

    pub fn update(self: *Thing, room: *Room) Error!void {
        assert(self.spawn_state == .spawned);
        const nearest_enemy = getNearestOpposingThing(self, room);
        const ai = &self.controller.acolyte_enemy;

        self.renderer.creature.draw_color = Colorf.yellow;
        _ = ai.cast_cooldown.tick(false);
        _ = ai.flee_cooldown.tick(false);
        ai.state = state: switch (ai.state) {
            .idle => {
                if (!ai.flee_cooldown.running) {
                    if (nearest_enemy) |e| {
                        if (e.pos.dist(self.pos) <= ai.flee_range) {
                            ai.ticks_in_state = 0;
                            continue :state .flee;
                        }
                    }
                }
                if (!ai.cast_cooldown.running) {
                    // TODO genericiszesez?
                    if (room.num_enemies_alive < 10) {
                        ai.ticks_in_state = 0;
                        continue :state .cast;
                    }
                }
                self.updateVel(.{}, .{});
                _ = self.animator.creature.play(.idle, .{ .loop = true });
                break :state .idle;
            },
            .flee => {
                if (ai.ticks_in_state == 0) {
                    assert(nearest_enemy != null);
                    const flee_from_pos = nearest_enemy.?.pos;
                    ai.hiding_places = try getHidingPlaces(room, self.pos, flee_from_pos, ai.flee_range);
                    ai.to_enemy = flee_from_pos.sub(self.pos);
                    if (ai.hiding_places.len > 0) {
                        var best_f: f32 = -std.math.inf(f32);
                        var best_pos: ?V2f = null;
                        for (ai.hiding_places.constSlice()) |h| {
                            const self_to_pos = h.pos.sub(self.pos).normalizedOrZero();
                            const len = @max(ai.to_enemy.length() - ai.flee_range, 0);
                            const to_enemy_n = ai.to_enemy.setLengthOrZero(len);
                            const dir_f = self_to_pos.dot(to_enemy_n.neg());
                            const f = h.flee_from_dist + dir_f;
                            if (best_pos == null or f > best_f) {
                                best_f = f;
                                best_pos = h.pos;
                            }
                        }
                        if (best_pos) |pos| {
                            try self.findPath(room, pos);
                        }
                    }
                }
                _ = self.animator.creature.play(.move, .{ .loop = true });
                const p = self.followPathGetNextPoint(10);
                self.updateVel(p.sub(self.pos).normalizedOrZero(), self.accel_params);
                if (!self.vel.isAlmostZero()) {
                    self.dir = self.vel.normalized();
                }
                if (self.path.len == 0) {
                    ai.flee_cooldown.restart();
                    ai.ticks_in_state = 0;
                    continue :state .idle;
                }
                break :state .flee;
            },
            .cast => {
                if (ai.ticks_in_state == 60) {
                    const dir = (if (nearest_enemy) |e| e.pos.sub(self.pos) else self.pos.neg()).normalizedOrZero();
                    const spawn_pos = self.pos.add(dir.scale(self.coll_radius * 2));
                    var spawner = Thing.SpawnerController.prototype(.bat);
                    spawner.faction = self.faction;
                    _ = try room.queueSpawnThing(&spawner, spawn_pos);
                    ai.cast_cooldown.restart();
                    ai.ticks_in_state = 0;
                    continue :state .idle;
                }
                self.updateVel(.{}, .{});
                _ = self.animator.creature.play(.cast, .{ .loop = true });
                break :state .cast;
            },
        };
        ai.ticks_in_state += 1;

        self.moveAndCollide(room);
    }
};

pub fn bat() Error!Thing {
    return Thing{
        .kind = .creature,
        .creature_kind = .bat,
        .spawn_state = .instance,
        .coll_radius = 9,
        .accel_params = .{
            .max_speed = 1,
        },
        .vision_range = 160,
        .coll_mask = Thing.Collision.Mask.initMany(&.{ .creature, .tile }),
        .coll_layer = Thing.Collision.Mask.initMany(&.{.creature}),
        .controller = .{ .enemy = .{
            .attack_cooldown = utl.TickCounter.initStopped(60),
        } },
        .renderer = .{ .creature = .{
            .draw_color = .yellow,
            .draw_radius = 10,
        } },
        .animator = .{ .creature = .{
            .creature_kind = .bat,
        } },
        .hitbox = .{
            .mask = Thing.Faction.opposing_masks.get(.enemy),
            .radius = 10,
            .rel_pos = V2f.right.scale(60),
            .effect = .{ .damage = 4 },
        },
        .hurtbox = .{
            .radius = 10,
        },
        .selectable = .{
            .height = 17 * 4, // TODO pixellszslz
            .radius = 6 * 4,
        },
        .hp = Thing.HP.init(5),
        .faction = .enemy,
        .enemy_difficulty = 0.25,
    };
}

pub fn troll() Error!Thing {
    return Thing{
        .kind = .creature,
        .creature_kind = .troll,
        .spawn_state = .instance,
        .coll_radius = 20,
        .accel_params = .{
            .max_speed = 0.7,
        },
        .vision_range = 160,
        .coll_mask = Thing.Collision.Mask.initMany(&.{ .creature, .tile }),
        .coll_layer = Thing.Collision.Mask.initMany(&.{.creature}),
        .controller = .{ .enemy = .{
            .attack_cooldown = utl.TickCounter.initStopped(60),
        } },
        .renderer = .{ .creature = .{
            .draw_color = .yellow,
            .draw_radius = 20,
        } },
        .animator = .{ .creature = .{
            .creature_kind = .troll,
        } },
        .hitbox = .{
            .mask = Thing.Faction.opposing_masks.get(.enemy),
            .radius = 15,
            .rel_pos = V2f.right.scale(60),
            .effect = .{ .damage = 15 },
        },
        .hurtbox = .{
            .radius = 15,
        },
        .selectable = .{
            .height = 20 * 4, // TODO pixellszslz
            .radius = 9 * 4,
        },
        .hp = Thing.HP.init(40),
        .faction = .enemy,
        .enemy_difficulty = 2.5,
    };
}

pub fn gobbow() Error!Thing {
    return Thing{
        .kind = .creature,
        .creature_kind = .gobbow,
        .spawn_state = .instance,
        .coll_radius = 15,
        .vision_range = 160,
        .coll_mask = Thing.Collision.Mask.initMany(&.{ .creature, .tile }),
        .coll_layer = Thing.Collision.Mask.initMany(&.{.creature}),
        .controller = .{ .enemy = .{
            .attack_range = 270,
            .attack_cooldown = utl.TickCounter.initStopped(60),
            .attack_type = .{ .projectile = .arrow },
        } },
        .renderer = .{ .creature = .{
            .draw_color = .yellow,
            .draw_radius = 15,
        } },
        .animator = .{ .creature = .{
            .creature_kind = .gobbow,
        } },
        .hurtbox = .{
            .radius = 15,
        },
        .selectable = .{
            .height = 12 * 4, // TODO pixellszslz
            .radius = 6 * 4,
        },
        .hp = Thing.HP.init(20),
        .faction = .enemy,
        .enemy_difficulty = 1.5,
    };
}

pub fn sharpboi() Error!Thing {
    return Thing{
        .kind = .creature,
        .creature_kind = .sharpboi,
        .spawn_state = .instance,
        .accel_params = .{
            .max_speed = 0.9,
        },
        .coll_radius = 15,
        .vision_range = 160,
        .coll_mask = Thing.Collision.Mask.initMany(&.{ .creature, .tile }),
        .coll_layer = Thing.Collision.Mask.initMany(&.{.creature}),
        .controller = .{ .enemy = .{
            .attack_range = 110,
            .attack_cooldown = utl.TickCounter.initStopped(140),
            .attack_type = .{ .melee = .{
                .lunge_accel = .{
                    .accel = 5,
                    .max_speed = 5,
                    .friction = 0,
                },
            } },
            .LOS_thiccness = 30,
        } },
        .renderer = .{ .creature = .{
            .draw_color = .yellow,
            .draw_radius = 15,
        } },
        .animator = .{ .creature = .{
            .creature_kind = .sharpboi,
        } },
        .hitbox = .{
            .mask = Thing.Faction.opposing_masks.get(.enemy),
            .radius = 15,
            .rel_pos = V2f.right.scale(40),
            .effect = .{ .damage = 8 },
            .deactivate_on_update = false,
            .deactivate_on_hit = true,
        },
        .hurtbox = .{
            .radius = 15,
        },
        .selectable = .{
            .height = 18 * 4, // TODO pixellszslz
            .radius = 8 * 4,
        },
        .hp = Thing.HP.init(25),
        .faction = .enemy,
        .enemy_difficulty = 2.5,
    };
}

pub fn acolyte() Error!Thing {
    return Thing{
        .kind = .creature,
        .creature_kind = .acolyte,
        .spawn_state = .instance,
        .accel_params = .{
            .accel = 0.3,
            .friction = 0.09,
            .max_speed = 1.25,
        },
        .coll_radius = 15,
        .vision_range = 160,
        .coll_mask = Thing.Collision.Mask.initMany(&.{ .creature, .tile }),
        .coll_layer = Thing.Collision.Mask.initMany(&.{.creature}),
        .controller = .{ .acolyte_enemy = .{} },
        .renderer = .{ .creature = .{
            .draw_color = .yellow,
            .draw_radius = 15,
        } },
        .animator = .{ .creature = .{
            .creature_kind = .acolyte,
        } },
        .hitbox = null,
        .hurtbox = .{
            .radius = 15,
        },
        .selectable = .{
            .height = 12 * 4, // TODO pixellszslz
            .radius = 6 * 4,
        },
        .hp = Thing.HP.init(30),
        .faction = .enemy,
        .enemy_difficulty = 3,
    };
}
