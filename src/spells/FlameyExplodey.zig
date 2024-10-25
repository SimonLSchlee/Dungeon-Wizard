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

const Collision = @import("../Collision.zig");
const Spell = @import("../Spell.zig");
const TargetKind = Spell.TargetKind;
const TargetingData = Spell.TargetingData;
const Params = Spell.Params;

pub const title = "Flamey Explodey";

pub const enum_name = "flamey_explodey";
pub const Controllers = [_]type{Projectile};

const base_explode_radius = 70;
const base_ball_radius = 12;
const base_range = 300;

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .cast_secs = 1.5,
        .color = .red,
        .targeting_data = .{
            .kind = .pos,
            .fixed_range = false,
            .max_range = base_range,
            .ray_to_mouse = .{
                .ends_at_coll_mask = Collision.Mask.initMany(&.{ .creature, .tile }),
                .thickness = base_ball_radius * 2, // TODO use radius below?
            },
            .radius_at_target = base_explode_radius,
        },
    },
);

explode_hit_effect: Thing.HitEffect = .{
    .damage = 10,
    .status_stacks = StatusEffect.StacksArray.initDefault(0, .{ .lit = 1 }),
},
ball_hit_effect: Thing.HitEffect = .{
    .damage = 7,
},
ball_radius: f32 = base_ball_radius,
explode_radius: f32 = base_explode_radius,
fire_spawn_radius: f32 = base_explode_radius + 20,
range: f32 = base_range,
max_speed: f32 = 6,

pub fn spawnFiresInRadius(room: *Room, pos: V2f, radius: f32, comptime max_spawned: usize) Error!void {
    if (max_spawned > 100) {
        @compileError("too many firess");
    }
    const fire_proto: Thing = Spell.GetKindType(.trailblaze).fireProto();
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

pub const Projectile = struct {
    pub const controller_enum_name = enum_name ++ "_projectile";

    exploded: bool = false,
    explode_counter: utl.TickCounter = utl.TickCounter.init(10),

    pub fn update(self: *Thing, room: *Room) Error!void {
        const spell_controller = &self.controller.spell;
        const spell = spell_controller.spell;
        const flamey_explodey = spell.kind.flamey_explodey;
        const params = spell_controller.params;
        const target_pos = params.target.pos;
        const projectile: *@This() = &spell_controller.controller.flamey_explodey_projectile;

        if (!projectile.exploded) {
            const hitbox = &self.hitbox.?;
            if (!hitbox.active or self.pos.dist(target_pos) < self.vel.length() * 2 or self.last_coll != null) {
                projectile.exploded = true;
                hitbox.active = true;
                hitbox.deactivate_on_update = true;
                hitbox.deactivate_on_hit = false;
                hitbox.radius = flamey_explodey.explode_radius;
                hitbox.effect = flamey_explodey.explode_hit_effect;
                hitbox.mask = Thing.Faction.Mask.initFull();
                self.renderer.shape.kind.circle.radius = flamey_explodey.explode_radius;
                self.vel = .{};
                try spawnFiresInRadius(room, self.pos, flamey_explodey.explode_radius + 20, 20);
            }
        } else {
            if (projectile.explode_counter.tick(false)) {
                self.deferFree(room);
            }
        }
        self.moveAndCollide(room);
    }
};

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    assert(std.meta.activeTag(params.target) == Spell.TargetKind.pos);
    const flamey_explodey = self.kind.flamey_explodey;
    const target_pos = params.target.pos;
    const target_dir = if (target_pos.sub(caster.pos).normalizedChecked()) |d| d else V2f.right;

    const ball = Thing{
        .kind = .projectile,
        .dir = target_dir,
        .vel = target_dir.scale(flamey_explodey.max_speed),
        .coll_radius = flamey_explodey.ball_radius,
        .coll_mask = Thing.Collision.Mask.initMany(&.{.tile}),
        .accel_params = .{
            .accel = 0.5,
            .max_speed = 5,
        },
        .controller = .{ .spell = .{
            .spell = self.*,
            .params = params,
            .controller = .{
                .flamey_explodey_projectile = .{},
            },
        } },
        .renderer = .{
            .shape = .{
                .kind = .{ .circle = .{ .radius = flamey_explodey.ball_radius } },
                .poly_opt = .{ .fill_color = Colorf.orange },
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
    };
    _ = try room.queueSpawnThing(&ball, caster.pos);
}

pub const description =
    \\Conjure a ball of fire which flies
    \\to the target point, and explodes,
    \\damaging all creatures in the blast
    \\and setting them alight.
    \\It will also trigger on impact with
    \\an enemy.
    \\Careful!
;

pub fn getDescription(self: *const Spell, buf: []u8) Error![]u8 {
    const flamey_explodey: @This() = self.kind.flamey_explodey;
    const fmt =
        \\Direct hit damage: {}
        \\Explosion damage: {}
        \\
        \\{s}
        \\
    ;
    const ball_damage: i32 = utl.as(i32, flamey_explodey.ball_hit_effect.damage);
    const explode_damage: i32 = utl.as(i32, flamey_explodey.explode_hit_effect.damage);
    return std.fmt.bufPrint(buf, fmt, .{ ball_damage, explode_damage, description });
}
