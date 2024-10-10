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

const AttackType = union(enum) {
    melee: void,
    projectile: EnemyProjectile,
    charge: void,
};

const EnemyProjectile = enum {
    arrow,
};

fn gobbowArrow(self: *const Thing, room: *Room) Error!void {
    var arrow = Thing{
        .kind = .projectile,
        .coll_radius = 5,
        .vel = self.dir.scale(4),
        .dir = self.dir,
        .coll_mask = Thing.CollMask.initMany(&.{.tile}),
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
    try arrow.init();
    defer arrow.deinit();
    _ = try room.queueSpawnThing(&arrow, self.pos);
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

pub fn getNearestTarget(self: *Thing, room: *Room) ?*Thing {
    var closest_dist = std.math.inf(f32);
    var closest: ?*Thing = null;
    for (&room.things.items) |*other| {
        if (!other.isActive()) continue;
        if (other.id.eql(self.id)) continue;
        if (!Thing.Faction.opposing_masks.get(self.faction).contains(other.faction)) continue;
        const dist = other.pos.dist(self.pos);
        if (dist < closest_dist) {
            closest_dist = dist;
            closest = other;
        }
    }
    return closest;
}

pub const AIController = struct {
    wander_dir: V2f = .{},
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
    attack_type: AttackType = .melee,
    LOS_thiccness: f32 = 10,

    pub fn update(self: *Thing, room: *Room) Error!void {
        assert(self.spawn_state == .spawned);
        const nearest_target = getNearestTarget(self, room);
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
                    self.updateVel(p.sub(self.pos).normalizedOrZero(), .{});
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
                    .melee => {
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
                            if (self.hitbox) |*hitbox| {
                                //std.debug.print("hit targetu\n", .{});
                                hitbox.mask = Thing.Faction.opposing_masks.get(self.faction);
                                hitbox.rel_pos = self.dir.scale(hitbox.rel_pos.length());
                                hitbox.active = true;
                                if (App.get().data.sounds.get(.thwack)) |s| {
                                    App.getPlat().playSound(s);
                                }
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
                    .charge => {
                        if (ai.ticks_in_state == 0) {
                            ai.can_turn_during_attack = false;
                            self.coll_mask.remove(.creature);
                            self.coll_layer.remove(.creature);
                        }
                        const hitbox = &self.hitbox.?;
                        _ = self.animator.creature.play(.charge, .{ .loop = true });

                        if (target.pos.sub(self.pos).dot(self.dir) > 0) {
                            const old_speed = self.vel.length();
                            self.updateVel(self.dir, .{ .accel = 0.2, .max_speed = 2.5 });
                            if (old_speed < 1 and self.vel.length() >= 1) {
                                //std.debug.print("hit targetu\n", .{});
                                hitbox.mask = Thing.Faction.opposing_masks.get(self.faction);
                                hitbox.deactivate_on_update = false;
                                hitbox.deactivate_on_hit = true;
                                hitbox.rel_pos = self.dir.scale(hitbox.rel_pos.length());
                                hitbox.active = true;
                            }
                            // gone past target, stop!
                        } else {
                            self.updateVel(.{}, .{ .max_speed = 2, .friction = 0.03 });
                            hitbox.active = false;
                            if (self.vel.length() < 0.1) {
                                //}
                                //if (self.last_coll != null or (self.vel.length() >= 1.4 and !hitbox.active)) {
                                self.coll_mask.insert(.creature);
                                self.coll_layer.insert(.creature);
                                ai.attack_cooldown.restart();
                                // must re-enter attack via pursue (once cooldown expires)
                                ai.ticks_in_state = 0;
                                continue :state .pursue;
                            }
                        }
                    },
                }

                break :state .attack;
            },
        };
        ai.ticks_in_state += 1;
        //std.debug.print("{any}\n", .{ai.state});

        if (false) {
            const coll = Thing.getCircleCollisionWithTiles(self.pos.add(self.vel), self.coll_radius, room);
            if (coll.collided) {
                if (coll.normal.dot(ai.wander_dir) < 0) {
                    ai.wander_dir = V2f.randomDir();
                }
            }
        }
        self.moveAndCollide(room);
    }
};

pub fn troll() Error!Thing {
    var ret = Thing{
        .kind = .troll,
        .spawn_state = .instance,
        .coll_radius = 20,
        .vision_range = 160,
        .coll_mask = Thing.CollMask.initMany(&.{ .creature, .tile }),
        .coll_layer = Thing.CollMask.initMany(&.{.creature}),
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
        .hp = Thing.HP.init(50),
        .faction = .enemy,
    };
    try ret.init();
    return ret;
}

pub fn gobbow() Error!Thing {
    var ret = Thing{
        .kind = .gobbow,
        .spawn_state = .instance,
        .coll_radius = 15,
        .vision_range = 160,
        .coll_mask = Thing.CollMask.initMany(&.{ .creature, .tile }),
        .coll_layer = Thing.CollMask.initMany(&.{.creature}),
        .controller = .{ .enemy = .{
            .attack_range = 300,
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
    };
    try ret.init();
    return ret;
}

pub fn sharpboi() Error!Thing {
    var ret = Thing{
        .kind = .sharpboi,
        .spawn_state = .instance,
        .coll_radius = 15,
        .vision_range = 160,
        .coll_mask = Thing.CollMask.initMany(&.{ .creature, .tile }),
        .coll_layer = Thing.CollMask.initMany(&.{.creature}),
        .controller = .{ .enemy = .{
            .attack_range = 150,
            .attack_cooldown = utl.TickCounter.initStopped(120),
            .attack_type = .charge,
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
            .effect = .{ .damage = 9 },
        },
        .hurtbox = .{
            .radius = 15,
        },
        .selectable = .{
            .height = 18 * 4, // TODO pixellszslz
            .radius = 8 * 4,
        },
        .hp = Thing.HP.init(35),
        .faction = .enemy,
    };
    try ret.init();
    return ret;
}
