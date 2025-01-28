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
const projectiles = @import("../projectiles.zig");
const Spell = @import("../Spell.zig");
const TargetKind = Spell.TargetKind;
const TargetingData = Spell.TargetingData;
const Params = Spell.Params;

pub const title = "Fire Boom";

pub const enum_name = "flamey_explodey";
pub const Controllers = [_]type{Projectile};

const base_explode_radius = 35;
const base_ball_radius = 5;
const base_range = 150;

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .cast_time = .medium,
        .mana_cost = Spell.ManaCost.num(3),
        .rarity = .interesting,
        .color = .red,
        .targeting_data = .{
            .kind = .pos,
            .fixed_range = false,
            .max_range = base_range,
            .ray_to_mouse = .{
                .ends_at_coll_mask = Collision.Mask.initMany(&.{.wall}),
                .thickness = base_ball_radius * 2, // TODO use radius below?
                .cast_orig_dist = 15,
            },
            .radius_at_target = base_explode_radius,
        },
    },
);

explode_hit_effect: Thing.HitEffect = .{
    .damage = 6,
    .damage_kind = .fire,
    .status_stacks = StatusEffect.StacksArray.initDefault(0, .{ .lit = 1 }),
},
ball_hit_effect: Thing.HitEffect = .{
    .damage = 4,
    .damage_kind = .fire,
},
ball_radius: f32 = base_ball_radius,
explode_radius: f32 = base_explode_radius,
fire_spawn_radius: f32 = base_explode_radius + 10,
range: f32 = base_range,
max_speed: f32 = 3,

pub fn spawnFiresInRadius(room: *Room, pos: V2f, radius: f32, comptime max_spawned: usize) Error!void {
    if (max_spawned > 100) {
        @compileError("too many firess");
    }
    const fire_proto: Thing = projectiles.proto(.fire_blaze);
    const top_left = pos.sub(V2f.splat(radius));
    const sq_size = radius * 2;
    const rnd = room.rng.random();
    const min_fire_dist = fire_proto.hitbox.?.radius * 2;

    var fire_spawn_positions = std.BoundedArray(V2f, max_spawned){};
    var failed_iters: usize = 0;
    while (fire_spawn_positions.len < fire_spawn_positions.buffer.len and failed_iters < max_spawned * 10) {
        const candidate_pos = v2f(
            rnd.floatNorm(f32) * sq_size,
            rnd.floatNorm(f32) * sq_size,
        ).add(top_left);
        const valid = blk: {
            if (candidate_pos.dist(pos) > radius) break :blk false;
            for (fire_spawn_positions.constSlice()) |existing_pos| {
                if (candidate_pos.dist(existing_pos) < min_fire_dist) break :blk false;
            }
            break :blk true;
        };
        if (!valid) {
            failed_iters += 1;
            continue;
        }
        fire_spawn_positions.append(candidate_pos) catch unreachable;
    }
    for (fire_spawn_positions.constSlice()) |fire_pos| {
        _ = try room.queueSpawnThing(&fire_proto, fire_pos);
    }
}

const AnimRef = struct {
    var ball_projectile = Data.Ref(Data.SpriteAnim).init("spell-projectile-fire-boom");
};
const SoundRef = struct {
    var woosh = Data.Ref(Data.Sound).init("long-woosh");
    var crackle = Data.Ref(Data.Sound).init("crackle");
};

pub const Projectile = struct {
    pub const controller_enum_name = enum_name ++ "_projectile";

    exploded: bool = false,
    explode_counter: utl.TickCounter = utl.TickCounter.init(10),

    pub fn update(self: *Thing, room: *Room) Error!void {
        const spell_controller = &self.controller.spell;
        const spell = spell_controller.spell;
        const flamey_explodey = spell.kind.flamey_explodey;
        const params = spell_controller.params;
        const target_pos = params.pos;
        const projectile: *@This() = &spell_controller.controller.flamey_explodey_projectile;

        if (!projectile.exploded) {
            const hitbox = &self.hitbox.?;
            _ = AnimRef.ball_projectile.get();
            _ = self.renderer.sprite.playNormal(AnimRef.ball_projectile, .{ .loop = true });
            if (!hitbox.active or self.pos.dist(target_pos) < self.vel.length() * 2 or self.last_coll != null) {
                projectile.exploded = true;
                hitbox.active = true;
                hitbox.deactivate_on_update = true;
                hitbox.deactivate_on_hit = false;
                hitbox.radius = flamey_explodey.explode_radius;
                hitbox.effect = flamey_explodey.explode_hit_effect;
                hitbox.mask = Thing.Faction.Mask.initFull();
                self.vel = .{};
                try spawnFiresInRadius(room, self.pos, flamey_explodey.explode_radius + 20, 20);
                self.renderer = .{
                    .shape = .{
                        .kind = .{ .circle = .{ .radius = flamey_explodey.explode_radius } },
                        .poly_opt = .{ .fill_color = Colorf.orange },
                    },
                };
                _ = App.get().sfx_player.playSound(&SoundRef.woosh, .{});
            }
        } else {
            self.vel = .{};
            if (projectile.explode_counter.tick(false)) {
                self.deferFree(room);
            }
        }
    }
};

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    params.validate(.pos, caster);
    const flamey_explodey = self.kind.flamey_explodey;
    const target_pos = params.pos;
    const target_dir = if (target_pos.sub(caster.pos).normalizedChecked()) |d| d else V2f.right;

    var ball = Thing{
        .kind = .projectile,
        .dir = target_dir,
        .vel = target_dir.scale(flamey_explodey.max_speed),
        .coll_radius = flamey_explodey.ball_radius,
        .coll_mask = Thing.Collision.Mask.initMany(&.{.wall}),
        .controller = .{ .spell = .{
            .spell = self.*,
            .params = params,
            .controller = .{
                .flamey_explodey_projectile = .{},
            },
        } },
        .renderer = .{
            .sprite = .{
                .draw_over = false,
                .draw_normal = true,
                .rotate_to_dir = true,
                .flip_x_to_dir = true,
                .rel_pos = v2f(0, -14),
            },
        },
        .hitbox = .{
            .active = true,
            .mask = Thing.Faction.opposing_masks.get(caster.faction),
            .deactivate_on_hit = true,
            .deactivate_on_update = false,
            .effect = flamey_explodey.ball_hit_effect,
            .radius = flamey_explodey.ball_radius,
        },
        .shadow_radius_x = flamey_explodey.ball_radius,
    };
    ball.renderer.sprite.setNormalAnim(AnimRef.ball_projectile);
    _ = try room.queueSpawnThing(&ball, params.cast_orig.?);
    _ = App.get().sfx_player.playSound(&SoundRef.crackle, .{});
}

pub fn getTooltip(self: *const Spell, tt: *Spell.Tooltip) Error!void {
    const flamey_explodey: @This() = self.kind.flamey_explodey;
    const ball_damage = flamey_explodey.ball_hit_effect.damage;
    const explode_damage = flamey_explodey.explode_hit_effect.damage;
    const hit_dmg = Thing.Damage{
        .kind = .fire,
        .amount = ball_damage,
    };
    const explode_dmg = Thing.Damage{
        .kind = .fire,
        .amount = explode_damage,
    };
    const fmt =
        \\Projectile which deals {any}
        \\damage on impact and explodes
        \\for {any}, leaving flames
        \\on the ground.
    ;
    tt.desc = try Spell.Tooltip.Desc.fromSlice(
        try std.fmt.bufPrint(&tt.desc.buffer, fmt, .{
            hit_dmg,
            explode_dmg,
        }),
    );
    tt.infos.appendAssumeCapacity(.{ .damage = .fire });
    tt.infos.appendAssumeCapacity(.{ .status = .lit });
}

pub fn getNewTags(self: *const Spell) Error!Spell.NewTag.Array {
    const flamey_explodey: @This() = self.kind.flamey_explodey;
    const ball_damage = flamey_explodey.ball_hit_effect.damage;
    const explode_damage = flamey_explodey.explode_hit_effect.damage;
    return Spell.NewTag.Array.fromSlice(&.{
        try Spell.NewTag.makeDamage(.fire, ball_damage, false),
        try Spell.NewTag.makeDamage(.fire, explode_damage, true),
    }) catch unreachable;
}
