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
pub const description =
    \\Conjure a ball of fire which flies
    \\to the target point, and explodes.
    \\It will also trigger on impact.
    \\Careful!
;

pub const enum_name = "flamey_explodey";
pub const Controllers = [_]type{Projectile};

const base_explode_radius = 70;
const base_ball_radius = 12;
const base_range = 300;

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .cast_time = 2,
        .color = .red,
        .targeting_data = .{
            .kind = .pos,
            .fixed_range = false,
            .max_range = base_range,
            .ray_to_mouse = .{
                .ends_at_coll_mask = Collision.Mask.initMany(&.{ .creature, .tile }),
                .thickness = base_ball_radius * 2, // TODO use radius below?
            },
            .radius_under_mouse = base_explode_radius,
        },
    },
);

explode_hit_effect: Thing.HitEffect = .{
    .damage = 12,
},
ball_hit_effect: Thing.HitEffect = .{
    .damage = 9,
},
ball_radius: f32 = base_ball_radius,
explode_radius: f32 = base_explode_radius,
range: f32 = base_range,
max_speed: f32 = 6,

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
