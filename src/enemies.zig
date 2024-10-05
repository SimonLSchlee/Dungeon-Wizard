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
const Goat = @This();

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

    pub fn update(self: *Thing, room: *Room) Error!void {
        assert(self.spawn_state == .spawned);
        const nearest_target = getNearestTarget(self, room);
        const ai = &self.controller.enemy;

        ai.state = state: switch (ai.state) {
            .idle => {
                if (nearest_target) |t| {
                    ai.target = t.id;
                    ai.ticks_in_state = 0;
                    continue :state .pursue;
                }
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
                if (range < ai.attack_range) {
                    ai.ticks_in_state = 0;
                    continue :state .melee_attack;
                } else {
                    _ = self.animator.creature.play(.move, .{ .loop = true });
                    try self.findPath(room, target.pos);
                    const p = self.followPathGetNextPoint(10);
                    self.updateVel(p.sub(self.pos).normalizedOrZero(), .{});
                }
                break :state .pursue;
            },
            .melee_attack => {
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
                if (range < ai.attack_range) {
                    self.updateVel(.{}, .{});
                    if (dist > 0.001) {
                        self.dir = target.pos.sub(self.pos).normalized();
                    }
                    _ = self.animator.creature.play(.attack, .{ .loop = true });
                    //if (self.renderer.default.animator.play(.attack, .{ .loop = true })) {
                    //std.debug.print("hit targetu\n", .{});
                    //    _ = self.animator.creature.play(.idle, .{ .loop = true });
                    //}
                } else {
                    ai.ticks_in_state = 0;
                    continue :state .pursue;
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
    var animator = Thing.DebugCircleRenderer.DebugAnimator{};
    animator.anims = @TypeOf(animator.anims).init(.{
        .none = .{},
        .attack = .{
            .num_frames = 30,
        },
    });
    var ret = Thing{
        .kind = .troll,
        .spawn_state = .instance,
        .coll_radius = 20,
        .vision_range = 160,
        .coll_mask = Thing.CollMask.initMany(&.{ .creature, .tile }),
        .coll_layer = Thing.CollMask.initMany(&.{.creature}),
        .controller = .{ .enemy = .{} },
        .renderer = .{ .creature = .{
            .draw_color = .yellow,
            .draw_radius = 20,
        } },
        .animator = .{ .creature = .{
            .creature_kind = .troll,
        } },
    };
    try ret.init();
    return ret;
}
