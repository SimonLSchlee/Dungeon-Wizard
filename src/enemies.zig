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

const EnemyProjectile = enum {
    arrow,
};

fn gobbowArrow(pos: V2f, dir: V2f, room: *Room) Error!void {
    var arrow = Thing{
        .kind = .projectile,
        .coll_radius = 5,
        .vel = dir.scale(4),
        .dir = dir,
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
            .mask = Thing.HurtBox.Mask.initMany(&.{ .player, .ally }),
            .damage = 7,
            .radius = 4,
            .rel_pos = dir.scale(28),
        },
    };
    try arrow.init();
    defer arrow.deinit();
    _ = try room.queueSpawnThing(&arrow, pos);
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
    if (room.getPlayer()) |p| {
        const dist = p.pos.dist(self.pos);
        if (dist <= closest_dist) {
            closest_dist = dist;
            closest = p;
        }
    }
    for (&room.things.items) |*other| {
        if (!other.isActive()) continue;
        if (other.id.eql(self.id)) continue;
        if (other.faction == .enemy or other.faction == .neutral) continue;
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
        melee_attack,
    } = .idle,
    ticks_in_state: i64 = 0,
    target: ?Thing.Id = null,
    attack_range: f32 = 40,
    attack_cooldown: utl.TickCounter = utl.TickCounter.initStopped(60),
    can_turn_during_attack: bool = true,
    attack_projectile: ?EnemyProjectile = null,

    pub fn update(self: *Thing, room: *Room) Error!void {
        assert(self.spawn_state == .spawned);
        const nearest_target = getNearestTarget(self, room);
        const ai = &self.controller.enemy;

        self.renderer.creature.draw_color = Colorf.yellow;
        _ = ai.attack_cooldown.tick(false);
        ai.state = state: switch (ai.state) {
            .idle => {
                if (nearest_target) |t| {
                    ai.target = t.id;
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
                if (range <= ai.attack_range) {
                    // in range, but have to wait for cooldown before starting attack
                    if (ai.attack_cooldown.running) {
                        self.updateVel(.{}, .{});
                        if (dist > 0.001) {
                            self.dir = target.pos.sub(self.pos).normalized();
                        }
                        _ = self.animator.creature.play(.idle, .{ .loop = true });
                    } else {
                        ai.ticks_in_state = 0;
                        continue :state .melee_attack;
                    }
                } else {
                    _ = self.animator.creature.play(.move, .{ .loop = true });
                    try self.findPath(room, target.pos);
                    const p = self.followPathGetNextPoint(10);
                    self.updateVel(p.sub(self.pos).normalizedOrZero(), .{});
                }
                break :state .pursue;
            },
            .melee_attack => {
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

                self.updateVel(.{}, .{});
                const events = self.animator.creature.play(.attack, .{ .loop = true });
                if (events.contains(.end)) {
                    //std.debug.print("attack end\n", .{});
                    ai.attack_cooldown.restart();
                    // must re-enter melee_attack via pursue (once cooldown expires)
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
                        hitbox.rel_pos = self.dir.scale(hitbox.rel_pos.length());
                        hitbox.active = true;
                    }
                    if (ai.attack_projectile) |proj_name| {
                        switch (proj_name) {
                            .arrow => {
                                try gobbowArrow(self.pos, self.dir, room);
                            },
                        }
                    }
                }

                break :state .melee_attack;
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

        if (!self.vel.isZero()) {
            self.dir = self.vel.normalized();
        }
        try self.moveAndCollide(room);
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
            .mask = Thing.HurtBox.Mask.initMany(&.{ .player, .ally }),
            .radius = 15,
            .rel_pos = V2f.right.scale(60),
            .damage = 15,
        },
        .hurtbox = .{
            .layers = Thing.HurtBox.Mask.initOne(.enemy),
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
            .attack_projectile = .arrow,
        } },
        .renderer = .{ .creature = .{
            .draw_color = .yellow,
            .draw_radius = 15,
        } },
        .animator = .{ .creature = .{
            .creature_kind = .gobbow,
        } },
        .hurtbox = .{
            .layers = Thing.HurtBox.Mask.initOne(.enemy),
            .radius = 15,
        },
        .selectable = .{
            .height = 9 * 4, // TODO pixellszslz
            .radius = 6 * 4,
        },
        .hp = Thing.HP.init(20),
        .faction = .enemy,
    };
    try ret.init();
    return ret;
}
