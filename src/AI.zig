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

pub fn inAttackRangeAndLOS(self: *const Thing, room: *const Room, action: *const Action, params: Action.Params) bool {
    const target: *const Thing = if (params.thing) |id| if (room.getConstThingById(id)) |t| t else return false else return false;
    if (target.hurtbox == null) return false;

    const range = target.getRangeToHurtBox(self.pos);
    switch (action.kind) {
        .melee_attack => |melee| {
            const in_range = range <= melee.range;
            var in_LOS = true;
            if (melee.LOS_thiccness > 0) {
                in_LOS = room.tilemap.isLOSBetweenThicc(self.pos, target.pos, melee.LOS_thiccness);
            }
            return in_range and in_LOS;
        },
        .projectile_attack => |proj| {
            return switch (proj.projectile) {
                .arrow => range <= proj.range and room.tilemap.isLOSBetweenThicc(self.pos, target.pos, proj.LOS_thiccness),
                .bomb => range <= proj.range,
            };
        },
        .spell_cast => |spc| {
            const spell: Spell = spc.spell;
            const in_range = range <= spell.targeting_data.max_range;
            // TODO more here?
            return in_range;
        },
        else => return false,
    }
}

// A decision is the answer to "what am I doing right now?"
// and "how long should I do it for until I decide again?"
pub const Decision = union(enum) {
    idle: struct {
        at_least_secs: f32 = 0,
    },
    pursue_to_attack: struct {
        target_id: Thing.Id, // for sanity check
        attack_range: f32,
        at_least_secs: f32 = 0.1,
    },
    flee: struct {
        min_dist: f32 = 0,
        max_dist: f32 = 9999,
        target_id: Thing.Id,
        at_least_secs: f32 = 1, // flee for at least this long (unless we reach the destination)
        cooldown_secs: f32 = 1,
    },
    action: Action.Doing,
};

pub const AIIdle = struct {
    pub fn decide(_: *AIIdle, _: *Thing, _: *Room) Decision {
        return Decision{ .idle = .{} };
    }
};

pub const AIAggro = struct {
    pub fn decide(_: *AIAggro, self: *Thing, room: *Room) Decision {
        var ret: Decision = .{ .idle = .{} };
        const controller = &self.controller.ai_actor;
        const nearest_enemy: ?*Thing = getNearestOpposingThing(self, room);
        if (nearest_enemy == null) {
            return ret;
        }
        const target = nearest_enemy.?;
        const params = Action.Params{ .target_kind = .thing, .thing = target.id };
        // get (best?) attack with lowest cooldown (or off cooldown)
        const slot = blk: {
            var best_slot: ?Action.Slot = null;
            var best_cd: i64 = undefined;
            for (Action.Slot.attacks) |atk_slot| {
                if (controller.actions.getPtr(atk_slot).*) |*action| {
                    const ticks_left = action.cooldown.ticksLeft();
                    if (ticks_left == 0) {
                        best_slot = atk_slot;
                        break; // TODO find best? priority?
                    } else if (best_slot == null or ticks_left < best_cd) {
                        best_slot = atk_slot;
                        best_cd = ticks_left;
                    }
                }
            }
            if (best_slot) |s| break :blk s else return ret;
        };
        const action = &controller.actions.getPtr(slot).*.?;

        if (inAttackRangeAndLOS(self, room, action, params)) {
            if (!action.cooldown.running) {
                ret = .{ .action = .{
                    .slot = slot,
                    .params = params,
                } };
            }
        } else {
            const range = switch (action.kind) {
                .projectile_attack => |r| r.range,
                .melee_attack => |m| m.range,
                .spell_cast => |spc| spc.spell.targeting_data.max_range,
                else => unreachable,
            };
            ret = .{ .pursue_to_attack = .{
                .target_id = target.id,
                .attack_range = range,
            } };
        }

        return ret;
    }
};

pub const AITroll = struct {
    ai_aggro: AIAggro = .{},

    pub fn decide(ai: *AITroll, self: *Thing, room: *Room) Decision {
        const controller = &self.controller.ai_actor;
        if (self.hp) |*hp| {
            if (hp.curr < hp.max * 0.5) {
                const action = &controller.actions.getPtr(.ability_1).*.?;
                if (!action.cooldown.running) {
                    return .{ .action = .{
                        .slot = .ability_1,
                        .params = .{
                            .target_kind = .self,
                            .thing = self.id,
                        },
                    } };
                }
            }
        }
        return ai.ai_aggro.decide(self, room);
    }
};

pub const AIGobbomber = struct {
    ai_ranged_flee: AIRangedFlee = .{},
    shield_wait_timer: utl.TickCounter = utl.TickCounter.init(core.secsToTicks(3)),

    pub fn decide(ai: *AIGobbomber, self: *Thing, room: *Room) Decision {
        const controller = &self.controller.ai_actor;
        if (self.hp) |*hp| {
            if (hp.shields.len == 0 and !ai.shield_wait_timer.running) {
                ai.shield_wait_timer.restart();
                const action = &controller.actions.getPtr(.ability_1).*.?;
                if (!action.cooldown.running) {
                    return .{ .action = .{
                        .slot = .ability_1,
                        .params = .{
                            .target_kind = .self,
                            .thing = self.id,
                        },
                    } };
                }
            }
        }
        return ai.ai_ranged_flee.decide(self, room);
    }

    pub fn update(ai: *AIGobbomber, self: *Thing, room: *Room) Error!void {
        _ = room;
        const controller = &self.controller.ai_actor;
        // check if doing the shield already
        switch (controller.decision) {
            .action => |doing| {
                if (doing.slot == .ability_1) return;
            },
            else => {},
        }
        if (self.hp) |*hp| {
            if (hp.shields.len == 0) {
                _ = ai.shield_wait_timer.tick(false);
            }
        }
    }
};

pub const AIRangedFlee = struct {
    ai_aggro: AIAggro = .{},
    pub fn decide(ai: *AIRangedFlee, self: *Thing, room: *Room) Decision {
        const controller = &self.controller.ai_actor;
        const nearest_enemy: ?*Thing = getNearestOpposingThing(self, room);
        const aggro_decision = ai.ai_aggro.decide(self, room);
        const already_pursuing = std.meta.activeTag(controller.decision) == .pursue_to_attack;
        // we've been fleeing, set cooldown
        if (std.meta.activeTag(controller.decision) == .flee) {
            controller.flee_cooldown = utl.TickCounter.init(core.secsToTicks(1));
        }
        // action (attack) takes priority
        if (std.meta.activeTag(aggro_decision) == .action) {
            return aggro_decision;
        } else if (!already_pursuing) { // if pursuing, keep pursuing until attack, otherwise flee if too close and LOS
            if (nearest_enemy) |target| {
                if (!controller.flee_cooldown.running) {
                    // flee if too close and have LOS
                    if (target.pos.dist(self.pos) <= controller.flee_range) { // and room.tilemap.isLOSBetween(self.pos, target.pos)) {
                        return .{ .flee = .{
                            .min_dist = 50,
                            .max_dist = 150,
                            .target_id = target.id,
                            .at_least_secs = 3,
                            .cooldown_secs = 1,
                        } };
                    }
                }
            }
        }
        // otherwise pursue, or idle
        return aggro_decision;
    }
};

pub const AIAcolyte = struct {
    pub fn decide(_: *AIAcolyte, self: *Thing, room: *Room) Decision {
        const controller = &self.controller.ai_actor;
        const nearest_enemy: ?*Thing = getNearestOpposingThing(self, room);
        const action = &controller.actions.getPtr(.spell_cast_summon_1).*.?;
        // we've been fleeing, set cooldown
        if (std.meta.activeTag(controller.decision) == .flee) {
            controller.flee_cooldown = utl.TickCounter.init(core.secsToTicks(1));
        }
        // prioritize summoning
        // TODO track summons' ids?
        if (!action.cooldown.running and room.num_enemies_alive < 10) {
            const dir = (if (nearest_enemy) |e| e.pos.sub(self.pos) else self.pos.neg()).normalizedOrZero();
            const spawn_pos = self.pos.add(dir.scale(self.coll_radius * 2));
            const params = Action.Params{ .target_kind = .pos, .pos = spawn_pos };
            return .{ .action = .{
                .slot = .spell_cast_summon_1,
                .params = params,
            } };
        }
        // otherwise fleee! (or idle)
        if (nearest_enemy) |target| {
            if (!controller.flee_cooldown.running) {
                if (target.pos.dist(self.pos) <= controller.flee_range) {
                    return .{
                        .flee = .{
                            .min_dist = 50,
                            .max_dist = controller.flee_range,
                            .target_id = target.id,
                            .at_least_secs = core.fups_to_secsf(action.cooldown.num_ticks),
                        },
                    };
                }
            }
        }
        return .{ .idle = .{} };
    }
};

pub const ActorController = struct {
    pub const Kind = enum {
        idle,
        aggro,
        acolyte,
        troll,
        ranged_flee,
        gobbomber,
    };
    pub const KindData = union(Kind) {
        idle: AIIdle,
        aggro: AIAggro,
        acolyte: AIAcolyte,
        troll: AITroll,
        ranged_flee: AIRangedFlee,
        gobbomber: AIGobbomber,
    };

    actions: Action.Slot.Array = Action.Slot.Array.initFill(null),
    ai: KindData = .{ .aggro = .{} },
    decision: Decision = .{ .idle = .{} },
    // Continue the current decision for this long before making a new one
    // Doesn't apply to Actions! Which can't be interrupted by a new Decision anyway.
    // This can be futzed with at runtime by the specific AIs..
    non_action_decision_cooldown: utl.TickCounter = utl.TickCounter.initStopped(0),

    // range at which we should flee
    flee_range: f32 = 125,
    // dont flee again for this long (TODO for all Decisions?)
    flee_cooldown: utl.TickCounter = utl.TickCounter.initStopped(1 * core.fups_per_sec),
    // debug for flee
    hiding_places: HidingPlacesArray = .{},
    to_enemy: V2f = .{},

    pub fn update(self: *Thing, room: *Room) Error!void {
        assert(self.spawn_state == .spawned);
        const controller = &self.controller.ai_actor;

        // tick action cooldowns
        for (&controller.actions.values) |*action| {
            if (action.*) |*a| {
                _ = a.cooldown.tick(false);
            }
        }
        _ = controller.flee_cooldown.tick(false);

        // tick ai
        switch (controller.ai) {
            inline else => |*ai| {
                if (std.meta.hasMethod(@TypeOf(ai), "update")) {
                    try ai.update(self, room);
                }
            },
        }

        // decide what to do, if not doing an action (actions are committed to until done)
        if (std.meta.activeTag(controller.decision) != .action and controller.non_action_decision_cooldown.tick(false)) {
            switch (controller.ai) {
                inline else => |*ai| {
                    controller.decision = ai.decide(self, room);
                    switch (controller.decision) {
                        .idle => |idle| {
                            controller.non_action_decision_cooldown = utl.TickCounter.init(core.secsToTicks(idle.at_least_secs));
                        },
                        .pursue_to_attack => |pursue| {
                            controller.non_action_decision_cooldown = utl.TickCounter.init(core.secsToTicks(pursue.at_least_secs));
                        },
                        .flee => |flee| {
                            controller.hiding_places.len = 0;
                            controller.non_action_decision_cooldown = utl.TickCounter.init(core.secsToTicks(flee.at_least_secs));
                        },
                        .action => {
                            const doing = &controller.decision.action;
                            try controller.actions.getPtr(doing.slot).*.?.begin(self, room, doing);
                        },
                    }
                },
            }
        }

        switch (controller.decision) {
            .idle => {
                self.updateVel(.{}, .{});
                if (self.animator) |*a| {
                    _ = a.play(.idle, .{ .loop = true });
                } else {
                    if (App.getData().getCreatureDirAnim(self.creature_kind.?, .idle)) |anim| {
                        _ = self.renderer.sprite.playDir(anim.data_ref, .{ .loop = true, .dir = self.dir });
                    }
                }
            },
            .action => |*doing| {
                const action = &controller.actions.getPtr(doing.slot).*.?;
                if (try action.update(self, room, doing)) {
                    action.cooldown.restart();
                    controller.decision = .{ .idle = .{} };
                    // make sure we make a new decision next update
                    controller.non_action_decision_cooldown.stop();
                }
            },
            .pursue_to_attack => |s| {
                const _target = room.getThingById(s.target_id);
                assert(_target != null);
                const target = _target.?;
                const range = target.getRangeToHurtBox(self.pos);
                _ = self.animator.?.play(.move, .{ .loop = true });
                const dist_til_in_range = range - s.attack_range;
                var target_pos = target.pos;
                // predictive movement if close enough
                if (range < 40) {
                    const time_til_reach = dist_til_in_range / self.accel_params.max_speed;
                    target_pos = target.pos.add(target.vel.scale(time_til_reach));
                }
                try self.findPath(room, target_pos);
                const p = self.followPathGetNextPoint(5);
                self.updateVel(p.sub(self.pos).normalizedOrZero(), self.accel_params);
                if (!self.vel.isAlmostZero()) {
                    self.dir = self.vel.normalized();
                }
            },
            .flee => |flee| {
                if (controller.hiding_places.len == 0) {
                    const _thing = room.getThingById(flee.target_id);
                    assert(_thing != null);
                    const thing = _thing.?;
                    const flee_from_pos = thing.pos;
                    controller.hiding_places = try getHidingPlaces(
                        room,
                        TileMap.PathLayer.Mask.initOne(self.pathing_layer),
                        self.pos,
                        flee_from_pos,
                        flee.min_dist,
                        flee.max_dist,
                    );
                    controller.to_enemy = flee_from_pos.sub(self.pos);
                    if (controller.hiding_places.len > 0) {
                        var best_score: f32 = -std.math.inf(f32);
                        var best_pos: ?V2f = null;
                        for (controller.hiding_places.constSlice()) |h| {
                            const self_to_pos = h.pos.sub(self.pos).normalizedOrZero();
                            const len = @max(controller.to_enemy.length() - flee.min_dist, 0);
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
                const p = self.followPathGetNextPoint(5);
                self.updateVel(p.sub(self.pos).normalizedOrZero(), self.accel_params);
                if (!self.vel.isAlmostZero()) {
                    self.dir = self.vel.normalized();
                }
                if (self.path.len == 0) {
                    // make sure we make a new decision now we've arrived
                    controller.non_action_decision_cooldown.stop();
                    // in general the specialized ai will set this, but always set it if we reached the end of the path
                    controller.flee_cooldown = utl.TickCounter.init(core.secsToTicks(flee.cooldown_secs));
                }
            },
        }
    }
};

pub const HidingPlacesArray = std.BoundedArray(struct { pos: V2f, fleer_dist: f32, flee_from_dist: f32 }, 32);
pub fn getHidingPlaces(room: *const Room, mask: TileMap.PathLayer.Mask, fleer_pos: V2f, flee_from_pos: V2f, min_flee_dist: f32, max_flee_dist: f32) Error!HidingPlacesArray {
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
        if (fleer_dist >= min_flee_dist and fleer_dist < max_flee_dist) {
            places.append(.{ .pos = pos, .fleer_dist = fleer_dist, .flee_from_dist = flee_from_dist }) catch {};
        }
        if (places.len >= places.buffer.len) break;

        for (TileMap.neighbor_dirs) |dir| {
            const dir_v = TileMap.neighbor_dirs_coords.get(dir);
            const next = curr.add(dir_v);
            //std.debug.print("neighbor {}, {}\n", .{ next.p.x, next.p.y });
            if (!tilemap.tileCoordIsPathable(mask, next)) {
                continue;
            }
            if (seen.get(next)) |_| continue;
            try seen.put(next, {});
            queue.append(next) catch break;
        }
    }
    return places;
}
