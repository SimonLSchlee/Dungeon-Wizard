const std = @import("std");
const assert = std.debug.assert;
const utl = @import("util.zig");

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

const App = @import("App.zig");
const getPlat = App.getPlat;
const Data = @import("Data.zig");
const Thing = @import("Thing.zig");
const Room = @import("Room.zig");
const Spell = @import("Spell.zig");
const Item = @import("Item.zig");
const gameUI = @import("gameUI.zig");
const sprites = @import("sprites.zig");
const projectiles = @import("projectiles.zig");
const Action = @This();

// Loosely defined, an Action is a behavior that occurs over a predictable timespan
// E.g. Shooting an arrow, casting a spell, dashing...
// Walking to player is NOT a predictable timespan, too many variables. so not an Action.

pub const MeleeAttack = struct {
    pub const enum_name = "melee_attack";
    hitbox: Thing.HitBox,
    lunge_accel: ?Thing.AccelParams = null,
    hit_to_side_force: f32 = 0,
    range: f32 = 40,
    LOS_thiccness: f32 = 0,
};

pub const ProjectileAttack = struct {
    pub const enum_name = "projectile_attack";
    projectile: projectiles.ProjectileKind,
    range: f32 = 100,
    LOS_thiccness: f32 = 10,
    target_pos: V2f = .{},
};

pub const SpellCast = struct {
    pub const enum_name = "spell_cast";
    spell: Spell,
    cast_vfx: ?Thing.Id = null,
};

pub const RegenHp = struct {
    pub const enum_name = "regen_hp";
    amount_per_sec: f32 = 1,
    max_regen: f32 = 10,
    amount_regened: f32 = 0,
    timer: utl.TickCounter = utl.TickCounter.init(60),
};

pub const ActionTypes = [_]type{
    MeleeAttack,
    ProjectileAttack,
    SpellCast,
    RegenHp,
};

pub const Kind = utl.EnumFromTypes(&ActionTypes, "enum_name");
pub const KindData = utl.TaggedUnionFromTypes(&ActionTypes, "enum_name", Kind);

pub const Slot = enum {
    pub const Array = std.EnumArray(Slot, ?Action);

    melee_attack_1,
    projectile_attack_1,
    spell_cast_summon_1,
    spell_cast_thing_attack_1,
    spell_cast_aoe_attack_1,
    spell_cast_thing_buff_1,
    spell_cast_thing_debuff_1,
    ability_1,

    pub const attacks = &[_]Slot{
        .melee_attack_1,
        .projectile_attack_1,
        .spell_cast_thing_attack_1,
    };
};

pub const TargetKind = enum {
    self,
    thing,
    pos,
};

pub const Params = struct {
    target_kind: TargetKind,
    face_dir: ?V2f = null,
    cast_orig: ?V2f = null,
    thing: ?Thing.Id = null,
    pos: V2f = .{}, // pos should always be valid - the *original* target position (even if on a Thing that could move or disappear)

    pub fn validate(self: Params, expected_kind: TargetKind, actor: *Thing) void {
        assert(self.target_kind == expected_kind);
        switch (self.target_kind) {
            .self => {
                assert(self.thing != null);
                assert(actor.id.eql(self.thing.?));
            },
            .thing => {
                assert(self.thing != null);
            },
            .pos => {},
        }
    }
};

pub const Doing = struct {
    slot: Action.Slot,
    params: Params,
    can_turn: bool = true,
};
kind: KindData,
curr_tick: i64 = 0,
cooldown: utl.TickCounter = utl.TickCounter.initStopped(60),

pub fn begin(action: *Action, self: *Thing, room: *Room, doing: *Action.Doing) Error!void {
    const maybe_target_thing: ?*const Thing =
        if (doing.params.thing) |target_id|
        if (room.getConstThingById(target_id)) |t| t else null
    else
        null;
    // make sure we always have a pos in the params, if we have a Thing
    if (maybe_target_thing) |t| {
        doing.params.pos = t.pos;
    }
    // TODO other stuff - maybe set pos to self.pos by default? idk
    // face what we're doing
    self.dir = doing.params.pos.sub(self.pos).normalizedChecked() orelse self.dir;
    switch (action.kind) {
        .melee_attack => |*melee| {
            _ = melee;
        },
        .projectile_attack => |*proj| {
            proj.target_pos = doing.params.pos;
        },
        .spell_cast => |*sp| {
            _ = sp;
        },
        .regen_hp => |*r| {
            r.amount_regened = 0;
            r.timer.restart();
        },
    }
    action.curr_tick = 0;
}

// return true if done
pub fn update(action: *Action, self: *Thing, room: *Room, doing: *Action.Doing) Error!bool {
    const maybe_target_thing: ?*const Thing =
        if (doing.params.thing) |target_id|
        if (room.getConstThingById(target_id)) |t| t else null
    else
        null;

    switch (action.kind) {
        .melee_attack => |melee| {
            self.updateVel(.{}, .{});
            const events = self.animator.?.play(.attack, .{ .loop = true });
            if (events.contains(.commit)) {
                doing.can_turn = false;
                self.hitbox = melee.hitbox;
                const hitbox = &self.hitbox.?;
                const dir_ang = self.dir.toAngleRadians();
                hitbox.rel_pos = V2f.fromAngleRadians(dir_ang).scale(hitbox.rel_pos.length());
                if (hitbox.sweep_to_rel_pos) |*sw| {
                    sw.* = V2f.fromAngleRadians(dir_ang).scale(sw.length());
                }
                if (self.animator.?.getTicksUntilEvent(.hit)) |ticks_til_hit_event| {
                    hitbox.indicator = .{
                        .timer = utl.TickCounter.init(ticks_til_hit_event),
                    };
                }
            }
            // predict hit
            if (doing.can_turn) {
                if (maybe_target_thing) |target| {
                    if (!target.isInvisible()) {
                        if (self.animator.?.getTicksUntilEvent(.hit)) |ticks_til_hit_event| {
                            if (target.hurtbox) |hurtbox| {
                                const dist = target.pos.dist(self.pos);
                                const range = @max(dist - hurtbox.radius, 0);
                                var ticks_til_hit = utl.as(f32, ticks_til_hit_event);
                                if (melee.lunge_accel) |accel| {
                                    ticks_til_hit += range / accel.max_speed;
                                }
                                const target_pos = target.pos.add(target.vel.scale(ticks_til_hit));
                                self.dir = target_pos.sub(self.pos).normalizedChecked() orelse self.dir;
                            }
                        }
                    }
                }
            }
            // end and hit are mutually exclusive
            if (events.contains(.end)) {
                // deactivate hitbox
                self.hitbox.?.active = false;
                if (melee.lunge_accel) |accel_params| {
                    self.coll_mask.insert(.creature);
                    self.coll_layer.insert(.creature);
                    self.updateVel(.{}, .{ .friction = accel_params.max_speed });
                }
                return true;
            }

            if (events.contains(.hit)) {
                self.renderer.creature.draw_color = Colorf.red;
                const hitbox = &self.hitbox.?;
                //std.debug.print("hit targetu\n", .{});
                hitbox.mask = Thing.Faction.opposing_masks.get(self.faction);
                hitbox.active = true;
                if (maybe_target_thing) |target_thing| {
                    if (melee.hit_to_side_force > 0) {
                        const d = if (self.dir.cross(target_thing.pos.sub(self.pos)) > 0) self.dir.rotRadians(-utl.pi / 3) else self.dir.rotRadians(utl.pi / 3);
                        hitbox.effect.force = .{ .fixed = d.scale(melee.hit_to_side_force) };
                    }
                }
                // play sound
                if (App.get().data.sounds.get(.thwack)) |s| {
                    App.getPlat().playSound(s);
                }

                if (melee.lunge_accel) |accel_params| {
                    self.coll_mask.remove(.creature);
                    self.coll_layer.remove(.creature);
                    self.updateVel(self.dir, accel_params);
                }
            }
        },
        .projectile_attack => |*atk| {
            self.updateVel(.{}, .{});
            const events = self.animator.?.play(.attack, .{ .loop = true });
            if (events.contains(.commit)) {
                doing.can_turn = false;
            }
            // face/track target
            var projectile: Thing = atk.projectile.prototype();
            if (doing.can_turn) {
                // default to original target pos
                self.dir = doing.params.pos.sub(self.pos).normalizedChecked() orelse self.dir;
                atk.target_pos = doing.params.pos;

                if (maybe_target_thing) |target| {
                    if (!target.isInvisible()) {
                        if (self.animator.?.getTicksUntilEvent(.hit)) |ticks_til_hit_event| {
                            if (target.hurtbox) |hurtbox| { // TODO hurtbox pos?
                                const dist = target.pos.dist(self.pos);
                                const range = @max(dist - hurtbox.radius, 0);
                                var ticks_til_hit = utl.as(f32, ticks_til_hit_event);
                                switch (atk.projectile) {
                                    .arrow => {
                                        ticks_til_hit += range / projectile.accel_params.max_speed;
                                    },
                                    .bomb => {
                                        ticks_til_hit += utl.as(f32, projectile.controller.projectile.timer.num_ticks);
                                    },
                                }
                                const predicted_target_pos = target.pos.add(target.vel.scale(ticks_til_hit));
                                switch (atk.projectile) {
                                    .arrow => {
                                        // make sure we can actually still get past nearby walls with this new angle!
                                        if (room.tilemap.isLOSBetweenThicc(self.pos, predicted_target_pos, atk.LOS_thiccness)) {
                                            atk.target_pos = predicted_target_pos;
                                            self.dir = predicted_target_pos.sub(self.pos).normalizedChecked() orelse self.dir;
                                        } else if (room.tilemap.isLOSBetweenThicc(self.pos, target.pos, atk.LOS_thiccness)) {
                                            // otherwise just face target directly
                                            atk.target_pos = target.pos;
                                            self.dir = target.pos.sub(self.pos).normalizedChecked() orelse self.dir;
                                        }
                                    },
                                    .bomb => {
                                        atk.target_pos = predicted_target_pos;
                                        self.dir = predicted_target_pos.sub(self.pos).normalizedChecked() orelse self.dir;
                                    },
                                }
                            }
                        }
                    }
                }
            }
            if (events.contains(.end)) {
                //std.debug.print("attack end\n", .{});
                return true;
            }

            if (events.contains(.hit)) {
                self.renderer.creature.draw_color = Colorf.red;
                projectile.dir = self.dir;
                switch (atk.projectile) {
                    .arrow => {
                        projectile.hitbox.?.rel_pos = self.dir.scale(28);
                        projectile.hitbox.?.mask = Thing.Faction.opposing_masks.get(self.faction);
                    },
                    .bomb => {
                        const dist = atk.target_pos.dist(self.pos);
                        const ticks_til_hit = projectile.controller.projectile.timer.num_ticks;
                        projectile.accel_params.max_speed = dist / utl.as(f32, ticks_til_hit);
                        projectile.hitbox.?.mask = Thing.Faction.Mask.initFull();
                        projectile.hitbox.?.indicator = .{
                            .timer = utl.TickCounter.init(ticks_til_hit),
                        };
                        projectile.controller.projectile.target_pos = atk.target_pos;
                    },
                }
                _ = try room.queueSpawnThing(&projectile, self.pos);
            }
        },
        .spell_cast => |*spc| {
            if (action.curr_tick == 0) {
                const cast_proto = Thing.CastVFXController.castingProto(self);
                if (try room.queueSpawnThing(&cast_proto, cast_proto.pos)) |id| {
                    spc.cast_vfx = id;
                }
            }
            if (action.curr_tick == 30) {
                if (spc.cast_vfx) |id| {
                    if (room.getThingById(id)) |cast| {
                        cast.controller.cast_vfx.anim_to_play = .basic_cast;
                    }
                }
                spc.cast_vfx = null;
            }
            if (action.curr_tick == 60) {
                try spc.spell.cast(self, room, doing.params);
                return true;
            }
            self.updateVel(.{}, .{});
            _ = self.animator.?.play(.cast, .{ .loop = true });
        },
        .regen_hp => |*r| {
            if (r.timer.tick(true)) {
                if (self.hp) |*hp| {
                    var adjusted_amount = r.amount_per_sec;
                    if (self.statuses.get(.lit).stacks > 0) {
                        adjusted_amount *= 0.5;
                    }
                    hp.heal(adjusted_amount, self, room);
                }
                r.amount_regened += r.amount_per_sec;
                if (r.amount_regened >= r.max_regen) {
                    return true;
                }
            }
            self.updateVel(.{}, .{});
            _ = self.animator.?.play(.idle, .{ .loop = true });
        },
    }
    action.curr_tick += 1;

    return false;
}
