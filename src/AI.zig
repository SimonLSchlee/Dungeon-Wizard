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
const Spell = @import("Spell.zig");
const Action = @import("Action.zig");

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
        if (!other.isAttackableCreature()) continue;
        const dist = other.pos.dist(self.pos);
        if (dist < closest_dist) {
            closest_dist = dist;
            closest = other;
        }
    }
    return closest;
}

pub fn inAttackRange(self: *const Thing, room: *const Room, action: *const Action, params: Action.Params) bool {
    const atk: struct {
        range: f32,
        LOS_thiccness: f32,
    } = switch (action.kind) {
        .melee_attack => |a| .{
            .range = a.range,
            .LOS_thiccness = a.LOS_thiccness,
        },
        .projectile_attack => |a| .{
            .range = a.range,
            .LOS_thiccness = a.LOS_thiccness,
        },
        else => return false,
    };
    const target: *const Thing = if (params.thing) |id| if (room.getConstThingById(id)) |t| t else return false else return false;
    const dist = target.pos.dist(self.pos);
    const range = @max(dist - self.coll_radius - target.coll_radius, 0);
    if (range <= atk.range and room.tilemap.isLOSBetweenThicc(self.pos, target.pos, atk.LOS_thiccness)) {
        return true;
    }
    return false;
}

// TODO these could be thought of as 'behaviors' and be more specific - e.g. 'pursue' instead of 'move'
pub const Decision = union(enum) {
    idle,
    pursue_to_attack: struct {
        target_id: Thing.Id, // for sanity check
        attack_range: f32,
    },
    flee: struct {
        dist: f32,
        target_id: Thing.Id,
    },
    action: Action.Doing,
};

pub const AIAggro = struct {
    attack_action_idx: usize = 0,

    pub fn decide(ai: *AIAggro, self: *Thing, room: *Room) Decision {
        const controller = &self.controller.ai_actor;
        const nearest_enemy: ?*Thing = getNearestOpposingThing(self, room);
        if (nearest_enemy) |target| {
            const action = &controller.actions.buffer[ai.attack_action_idx];
            const params = Action.Params{ .target_kind = .thing, .thing = target.id };
            if (inAttackRange(self, room, action, params)) {
                if (action.cooldown.running) {
                    return .idle;
                } else {
                    return .{ .action = .{
                        .idx = ai.attack_action_idx,
                        .params = params,
                    } };
                }
            }
            const range = switch (action.kind) {
                .projectile_attack => |r| r.range,
                .melee_attack => |m| m.range,
                else => unreachable,
            };
            return .{ .pursue_to_attack = .{
                .target_id = target.id,
                .attack_range = range,
            } };
        }
        return .idle;
    }
};

pub const AIAcolyte = struct {
    cast_action_idx: usize = 0,

    pub fn decide(ai: *AIAcolyte, self: *Thing, room: *Room) Decision {
        const controller = &self.controller.ai_actor;
        const nearest_enemy: ?*Thing = getNearestOpposingThing(self, room);
        const action = &controller.actions.buffer[ai.cast_action_idx];

        if (nearest_enemy) |target| {
            if (!controller.flee_cooldown.running) {
                if (target.pos.dist(self.pos) <= controller.flee_range) {
                    return .{ .flee = .{
                        .dist = controller.flee_range,
                        .target_id = target.id,
                    } };
                }
            }
        }
        {
            // TODO track summons' ids?
            if (!action.cooldown.running and room.num_enemies_alive < 10) {
                const dir = (if (nearest_enemy) |e| e.pos.sub(self.pos) else self.pos.neg()).normalizedOrZero();
                const spawn_pos = self.pos.add(dir.scale(self.coll_radius * 2));
                const params = Action.Params{ .target_kind = .pos, .pos = spawn_pos };
                return .{ .action = .{
                    .idx = ai.cast_action_idx,
                    .params = params,
                } };
            }
        }
        return .idle;
    }
};

pub const ActorController = struct {
    pub const Kind = enum {
        aggro,
        acolyte,
    };
    pub const KindData = union(Kind) {
        aggro: AIAggro,
        acolyte: AIAcolyte,
    };

    actions: Action.Array = .{},
    ai: KindData = .{ .aggro = .{} },
    decision: Decision = .idle,
    flee_range: f32 = 250,
    flee_cooldown: utl.TickCounter = utl.TickCounter.initStopped(1 * core.fups_per_sec),
    // debug for flee
    hiding_places: HidingPlacesArray = .{},
    to_enemy: V2f = .{},

    pub fn update(self: *Thing, room: *Room) Error!void {
        assert(self.spawn_state == .spawned);
        const controller = &self.controller.ai_actor;

        // tick action cooldowns
        for (controller.actions.slice()) |*a| {
            _ = a.cooldown.tick(false);
        }
        _ = controller.flee_cooldown.tick(false);

        // tick ai
        switch (controller.ai) {
            inline else => |ai| {
                if (std.meta.hasMethod(@TypeOf(ai), "update")) {
                    try ai.update(self, room);
                }
            },
        }

        // decide what to do, if not doing an action (actions are committed to until done)
        if (std.meta.activeTag(controller.decision) != .action) switch (controller.ai) {
            inline else => |*ai| {
                controller.decision = ai.decide(self, room);
                if (std.meta.activeTag(controller.decision) == .action) {
                    const doing = &controller.decision.action;
                    try controller.actions.buffer[doing.idx].begin(self, room, doing);
                }
            },
        };

        switch (controller.decision) {
            .idle => {
                self.updateVel(.{}, .{});
                _ = self.animator.?.play(.idle, .{ .loop = true });
            },
            .action => |*doing| {
                if (try controller.actions.buffer[doing.idx].update(self, room, doing)) {
                    controller.decision = .idle;
                }
            },
            .pursue_to_attack => |s| {
                const _target = room.getThingById(s.target_id);
                assert(_target != null);
                const target = _target.?;
                const dist = target.pos.dist(self.pos);
                const range = @max(dist - target.hurtbox.?.radius, 0);
                _ = self.animator.?.play(.move, .{ .loop = true });
                const dist_til_in_range = range - s.attack_range;
                var target_pos = target.pos;
                // predictive movement if close enough
                if (range < 80) {
                    const time_til_reach = dist_til_in_range / self.accel_params.max_speed;
                    target_pos = target.pos.add(target.vel.scale(time_til_reach));
                }
                try self.findPath(room, target_pos);
                const p = self.followPathGetNextPoint(10);
                self.updateVel(p.sub(self.pos).normalizedOrZero(), self.accel_params);
                if (!self.vel.isAlmostZero()) {
                    self.dir = self.vel.normalized();
                }
            },
            .flee => |f| {
                if (controller.hiding_places.len == 0) {
                    const _thing = room.getThingById(f.target_id);
                    assert(_thing != null);
                    const thing = _thing.?;
                    const flee_from_pos = thing.pos;
                    controller.hiding_places = try getHidingPlaces(room, self.pos, flee_from_pos, f.dist);
                    controller.to_enemy = flee_from_pos.sub(self.pos);
                    if (controller.hiding_places.len > 0) {
                        var best_score: f32 = -std.math.inf(f32);
                        var best_pos: ?V2f = null;
                        for (controller.hiding_places.constSlice()) |h| {
                            const self_to_pos = h.pos.sub(self.pos).normalizedOrZero();
                            const len = @max(controller.to_enemy.length() - f.dist, 0);
                            const to_enemy_n = controller.to_enemy.setLengthOrZero(len);
                            const dir_f = self_to_pos.dot(to_enemy_n.neg());
                            const score = h.flee_from_dist + dir_f;
                            if (best_pos == null or score > best_score) {
                                best_score = score;
                                best_pos = h.pos;
                            }
                        }
                        if (best_pos) |pos| {
                            try self.findPath(room, pos);
                        }
                    }
                }
                _ = self.animator.?.play(.move, .{ .loop = true });
                const p = self.followPathGetNextPoint(10);
                self.updateVel(p.sub(self.pos).normalizedOrZero(), self.accel_params);
                if (!self.vel.isAlmostZero()) {
                    self.dir = self.vel.normalized();
                }
                if (self.path.len == 0) {
                    controller.flee_cooldown.restart();
                    controller.hiding_places.len = 0;
                }
            },
        }
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
            if (tilemap.gameTileCoordToConstGameTile(next)) |tile| {
                if (!tile.passable) continue;
            }
            if (seen.get(next)) |_| continue;
            try seen.put(next, {});
            queue.append(next) catch break;
        }
    }
    return places;
}
