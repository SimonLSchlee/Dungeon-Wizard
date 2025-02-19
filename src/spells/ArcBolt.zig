const std = @import("std");
const utl = @import("../util.zig");

pub const Platform = @import("../raylib.zig");
const core = @import("../core.zig");
const Error = core.Error;
const Key = core.Key;
const debug = @import("../debug.zig");
const assert = debug.assert;
const draw = @import("../draw.zig");
const Colorf = draw.Colorf;
const geom = @import("../geometry.zig");
const V2f = @import("../V2f.zig");
const v2f = V2f.v2f;
const V2i = @import("../V2i.zig");
const v2i = V2i.v2i;

const App = @import("../App.zig");
const getPlat = App.getPlat;
const Room = @import("../Room.zig");
const Thing = @import("../Thing.zig");
const TileMap = @import("../TileMap.zig");
const StatusEffect = @import("../StatusEffect.zig");
const Data = @import("../Data.zig");

const Collision = @import("../Collision.zig");
const Spell = @import("../Spell.zig");
const TargetKind = Spell.TargetKind;
const TargetingData = Spell.TargetingData;
const Params = Spell.Params;

pub const title = "Arc Bolt";

pub const enum_name = "arc_bolt";
pub const Controllers = [_]type{Projectile};

const base_bolt_radius = 4.5;
const base_range = 100;
const base_chain_range = 75;
const base_duration_ticks = core.secsToTicks(2);

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .cast_time = .fast,
        .mana_cost = Spell.ManaCost.num(1),
        .color = draw.Coloru.rgb(255, 253, 231).toColorf(),
        .rarity = .interesting,
        .targeting_data = .{
            .kind = .thing,
            .target_faction_mask = Thing.Faction.opposing_masks.get(.player),
            .max_range = base_range,
            .show_max_range_ring = true,
            .radius_at_target = base_chain_range,
        },
    },
);

hit_effect: Thing.HitEffect = .{
    .damage = 5,
    .damage_kind = .lightning,
    .status_stacks = StatusEffect.StacksArray.initDefault(0, .{ .stunned = 1 }),
},
range: f32 = base_range,
chain_range: f32 = base_chain_range,
duration_ticks: i64 = base_duration_ticks,
max_speed: f32 = 2.5,
max_chains: usize = 4,

const AnimRef = struct {
    var projectile_loop = Data.Ref(Data.SpriteAnim).init("spell-projectile-flare-dart");
};
const SoundRef = struct {
    var woosh = Data.Ref(Data.Sound).init("long-woosh");
    var crackle = Data.Ref(Data.Sound).init("crackle");
};

pub const Projectile = struct {
    pub const controller_enum_name = enum_name ++ "_projectile";
    caster: Thing.Id,
    chains: usize = 0,
    target_mask: Thing.Faction.Mask,
    state: enum {
        moving,
        expiring,
    } = .moving,
    expire_timer: utl.TickCounter = utl.TickCounter.init(15),
    lightning_timer: utl.TickCounter = utl.TickCounter.init(3),

    pub fn update(self: *Thing, room: *Room) Error!void {
        const spell_controller = &self.controller.spell;
        const spell = &spell_controller.spell;
        const arc_bolt = spell.kind.arc_bolt;
        const params = &spell_controller.params;
        const target_thing_id = params.thing.?;
        const maybe_target_thing = room.getThingById(target_thing_id);
        if (maybe_target_thing) |thing| {
            params.pos = thing.pos;
        }
        const target_dir = if (params.pos.sub(self.pos).normalizedChecked()) |d| d else V2f.right;
        const projectile: *@This() = &spell_controller.controller.arc_bolt_projectile;
        const renderer = &self.renderer.lightning;
        //_ = AnimRef.projectile_loop.get();
        //_ = self.renderer.sprite.playNormal(AnimRef.projectile_loop, .{ .loop = true });

        var do_free = false;
        switch (projectile.state) {
            .moving => {
                self.updateVel(target_dir, self.accel_params);
                self.accel_params.accel += 0.01;
                if (projectile.lightning_timer.tick(true)) {
                    const rang = utl.tau * room.rng.random().float(f32);
                    const rdst = 2 + 4 * room.rng.random().float(f32);
                    const dir = V2f.fromAngleRadians(rang);
                    const point = self.pos.add(dir.scale(rdst));
                    if (renderer.points.len >= 10) {
                        renderer.points.buffer[renderer.points_start] = point;
                        renderer.points_start = (renderer.points_start + 1) % 10;
                    } else {
                        renderer.points.appendAssumeCapacity(point);
                    }
                }
                const dist_to_target = self.pos.dist(params.pos);
                if (dist_to_target <= @max(10, self.accel_params.accel)) {
                    if (maybe_target_thing) |target| {
                        if (target.hurtbox) |*hurtbox| {
                            hurtbox.hit(target, room, arc_bolt.hit_effect, room.getThingById(projectile.caster));
                        }
                    }
                    projectile.state = .expiring;
                    self.vel = .{};
                    if (projectile.chains < arc_bolt.max_chains) {
                        if (room.getClosestThingToPoint(params.pos, target_thing_id, projectile.target_mask)) |new_target| {
                            if (new_target.pos.dist(params.pos) <= arc_bolt.chain_range) {
                                const new_params = Params{
                                    .target_kind = .thing,
                                    .thing = new_target.id,
                                    .pos = new_target.pos,
                                };
                                try spawn(spell, room, projectile.caster, params.pos, new_params, projectile.target_mask, projectile.chains + 1);
                            }
                        }
                    }
                }
            },
            .expiring => {
                if (projectile.lightning_timer.tick(true)) {
                    if (renderer.points.len > 0) {
                        renderer.points_start = renderer.points_start % renderer.points.len;
                        _ = renderer.points.orderedRemove(renderer.points_start);
                    }
                }
                if (projectile.expire_timer.tick(false)) {
                    do_free = true;
                } else {
                    const f = projectile.expire_timer.remapTo0_1();
                    renderer.color = Colorf.rgba(1, 1, 1, 1 - f);
                }
            },
        }

        // done?
        if (do_free) {
            self.deferFree(room);
        }
    }
    pub fn spawn(spell: *const Spell, room: *Room, caster: Thing.Id, origin: V2f, params: Params, target_mask: Thing.Faction.Mask, chains: usize) Error!void {
        const to_target = params.pos.sub(origin);
        const dist = to_target.length();
        const target_dir = if (to_target.normalizedChecked()) |d| d else V2f.right;
        const accel = dist / 20 / 20;
        const arc_bolt = spell.kind.arc_bolt;

        var ball = Thing{
            .kind = .projectile,
            .dir = target_dir,
            .vel = target_dir.add(target_dir.rot90CCW()).normalized().scale(arc_bolt.max_speed),
            .accel_params = .{ .accel = accel, .max_speed = arc_bolt.max_speed, .friction = 0.01 },
            .controller = .{ .spell = .{
                .spell = spell.*,
                .params = params,
                .controller = .{
                    .arc_bolt_projectile = .{
                        .caster = caster,
                        .chains = chains,
                        .target_mask = target_mask,
                    },
                },
            } },
            .renderer = .{
                .lightning = .{},
            },
        };
        //ball.renderer.sprite.setNormalAnim(AnimRef.projectile_loop);
        _ = try room.queueSpawnThing(&ball, origin);
        _ = App.get().sfx_player.playSound(&SoundRef.crackle, .{});
    }
};

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    params.validate(.thing, caster);
    try Projectile.spawn(
        self,
        room,
        caster.id,
        caster.pos,
        params,
        Thing.Faction.opposing_masks.get(caster.faction),
        0,
    );
}

pub fn getTooltip(self: *const Spell, tt: *Spell.Tooltip) Error!void {
    const arc_bolt: @This() = self.kind.arc_bolt;
    const hit_dmg = Thing.Damage{
        .kind = .lightning,
        .amount = arc_bolt.hit_effect.damage,
    };
    const fmt =
        \\Lightning arc which deals {any} damage
        \\to an enemy, and then bounces between
        \\enemies up to 4 more times.
    ;
    tt.desc = try Spell.Tooltip.Desc.fromSlice(
        try std.fmt.bufPrint(&tt.desc.buffer, fmt, .{
            hit_dmg,
        }),
    );
    tt.infos.appendAssumeCapacity(.{ .damage = .lightning });
    tt.infos.appendAssumeCapacity(.{ .status = .stunned });
}

pub fn getNewTags(self: *const Spell) Error!Spell.NewTag.Array {
    const arc_bolt: @This() = self.kind.arc_bolt;
    return Spell.NewTag.Array.fromSlice(&.{
        try Spell.NewTag.makeDamage(.lightning, arc_bolt.hit_effect.damage, false),
        try Spell.NewTag.makeStatus(.stunned, arc_bolt.hit_effect.status_stacks.get(.stunned)),
    }) catch unreachable;
}
