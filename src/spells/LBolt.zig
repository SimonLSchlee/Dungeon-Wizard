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

pub const title = "Le Bolt";

pub const enum_name = "l_bolt";
pub const Controllers = [_]type{Projectile};

const base_bolt_radius = 4.5;
const base_range = 150;
const base_duration_ticks = core.secsToTicks(2);

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .cast_time = .fast,
        .color = Spell.colors.lightning,
        .targeting_data = .{
            .kind = .pos,
            .fixed_range = true,
            .max_range = base_range,
            .ray_to_mouse = .{
                .ends_at_coll_mask = Collision.Mask.initMany(&.{.wall}),
                .thickness = base_bolt_radius * 2, // TODO use radius below?
                .cast_orig_dist = 15,
            },
        },
    },
);

hit_effect: Thing.HitEffect = .{
    .damage = 7,
    .damage_kind = .lightning,
    .status_stacks = StatusEffect.StacksArray.initDefault(0, .{ .stunned = 1 }),
},
range: f32 = base_range,
duration_ticks: i64 = base_duration_ticks,
max_speed: f32 = 2.5,

const AnimRef = struct {
    var projectile_loop = Data.Ref(Data.SpriteAnim).init("spell-projectile-flare-dart");
};
const SoundRef = struct {
    var woosh = Data.Ref(Data.Sound).init("long-woosh");
    var crackle = Data.Ref(Data.Sound).init("crackle");
};

pub const Projectile = struct {
    pub const controller_enum_name = enum_name ++ "_projectile";
    origin: V2f,
    bounces: usize = 0,
    state: enum {
        moving,
        expiring,
    } = .moving,
    expire_timer: utl.TickCounter,
    lightning_timer: utl.TickCounter = utl.TickCounter.init(3),
    hitbox_extended: bool = false,

    pub fn update(self: *Thing, room: *Room) Error!void {
        const spell_controller = &self.controller.spell;
        const spell = spell_controller.spell;
        const l_bolt = spell.kind.l_bolt;
        const params = spell_controller.params;
        const target_pos = params.pos;
        _ = target_pos;
        const projectile: *@This() = &spell_controller.controller.l_bolt_projectile;
        const renderer = &self.renderer.lightning;
        //_ = AnimRef.projectile_loop.get();
        //_ = self.renderer.sprite.playNormal(AnimRef.projectile_loop, .{ .loop = true });

        var do_free = false;
        switch (projectile.state) {
            .moving => {
                if (self.last_coll) |coll| {
                    projectile.bounces += 1;
                    self.vel = self.vel.sub(coll.normal.scale(2 * self.vel.dot(coll.normal)));
                }
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
                const dist_from_origin = self.pos.dist(projectile.origin);
                if (projectile.hitbox_extended) {
                    self.hitbox.?.sweep_to_rel_pos = self.vel.normalized().neg().scale(self.hitbox.?.sweep_to_rel_pos.?.length());
                } else {
                    var len = dist_from_origin;
                    if (dist_from_origin >= 15) {
                        len = 15;
                        projectile.hitbox_extended = true;
                    }
                    self.hitbox.?.sweep_to_rel_pos = self.vel.normalized().neg().scale(len);
                }
                if ((projectile.bounces == 0 and dist_from_origin > l_bolt.range) or
                    projectile.expire_timer.tick(false) or
                    !self.hitbox.?.active)
                {
                    self.hitbox.?.active = false;
                    projectile.expire_timer = utl.TickCounter.init(15);
                    projectile.state = .expiring;
                    self.vel = .{};
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
};

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    params.validate(.pos, caster);
    const l_bolt: @This() = self.kind.l_bolt;
    const target_pos = params.pos;
    const target_dir = if (target_pos.sub(caster.pos).normalizedChecked()) |d| d else V2f.right;
    const origin = caster.pos.add(target_dir.scale(self.targeting_data.ray_to_mouse.?.cast_orig_dist));

    var ball = Thing{
        .kind = .projectile,
        .dir = target_dir,
        .vel = target_dir.scale(l_bolt.max_speed),
        .coll_radius = base_bolt_radius,
        .coll_mask = Thing.Collision.Mask.initMany(&.{.wall}),
        .controller = .{ .spell = .{
            .spell = self.*,
            .params = params,
            .controller = .{
                .l_bolt_projectile = .{
                    .origin = origin,
                    .expire_timer = utl.TickCounter.init(l_bolt.duration_ticks),
                },
            },
        } },
        .renderer = .{
            .lightning = .{},
        },
        .hitbox = .{
            .mask = Thing.Faction.opposing_masks.get(caster.faction),
            .deactivate_on_hit = true,
            .deactivate_on_update = false,
            .effect = l_bolt.hit_effect,
            .radius = base_bolt_radius,
        },
    };
    ball.hitbox.?.activate(room);
    //ball.renderer.sprite.setNormalAnim(AnimRef.projectile_loop);
    _ = try room.queueSpawnThing(&ball, origin);
    _ = App.get().sfx_player.playSound(&SoundRef.crackle, .{});
}

pub fn getTooltip(self: *const Spell, tt: *Spell.Tooltip) Error!void {
    const l_bolt: @This() = self.kind.l_bolt;
    const hit_dmg = Thing.Damage{
        .kind = l_bolt.hit_effect.damage_kind,
        .amount = l_bolt.hit_effect.damage,
    };
    const fmt =
        \\Projectile which bounces off walls
        \\and deals {any} damage if it hits
        \\an enemy creature.
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
    const l_bolt: @This() = self.kind.l_bolt;
    return Spell.NewTag.Array.fromSlice(&.{
        try Spell.NewTag.makeDamage(.lightning, l_bolt.hit_effect.damage, false),
        try Spell.NewTag.makeStatus(.stunned, l_bolt.hit_effect.status_stacks.get(.stunned)),
    }) catch unreachable;
}
