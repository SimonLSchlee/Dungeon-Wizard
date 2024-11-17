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

pub const title = "Flare Dart";

pub const enum_name = "flare_dart";
pub const Controllers = [_]type{Projectile};

const base_ball_radius = 6.5;
const base_range = 250;

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .cast_time = .fast,
        .color = .orange,
        .targeting_data = .{
            .kind = .pos,
            .fixed_range = true,
            .max_range = base_range,
            .ray_to_mouse = .{
                .ends_at_coll_mask = Collision.Mask.initMany(&.{.tile}),
                .thickness = base_ball_radius * 2, // TODO use radius below?
                .cast_orig_dist = 20,
            },
        },
    },
);

hit_effect: Thing.HitEffect = .{
    .damage = 5,
    .status_stacks = StatusEffect.StacksArray.initDefault(0, .{ .lit = 1 }),
},
ball_radius: f32 = base_ball_radius,
range: f32 = base_range,
max_speed: f32 = 6,

pub const Projectile = struct {
    pub const controller_enum_name = enum_name ++ "_projectile";

    pub fn update(self: *Thing, room: *Room) Error!void {
        const spell_controller = &self.controller.spell;
        const spell = spell_controller.spell;
        const flare_dart = spell.kind.flare_dart;
        _ = flare_dart;
        const params = spell_controller.params;
        const target_pos = params.target.pos;
        _ = target_pos;
        const projectile: *@This() = &spell_controller.controller.flare_dart_projectile;
        _ = projectile;

        if (self.last_coll != null or !self.hitbox.?.active) {
            self.deferFree(room);
        } else {
            self.moveAndCollide(room);
        }
    }
};

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    assert(std.meta.activeTag(params.target) == Spell.TargetKind.pos);
    const flare_dart: @This() = self.kind.flare_dart;
    const target_pos = params.target.pos;
    const target_dir = if (target_pos.sub(caster.pos).normalizedChecked()) |d| d else V2f.right;

    const ball = Thing{
        .kind = .projectile,
        .dir = target_dir,
        .vel = target_dir.scale(flare_dart.max_speed),
        .coll_radius = flare_dart.ball_radius,
        .coll_mask = Thing.Collision.Mask.initMany(&.{.tile}),
        .accel_params = .{
            .accel = 0.5,
            .max_speed = 5,
        },
        .controller = .{ .spell = .{
            .spell = self.*,
            .params = params,
            .controller = .{
                .flare_dart_projectile = .{},
            },
        } },
        .renderer = .{
            .shape = .{
                .kind = .{ .circle = .{ .radius = flare_dart.ball_radius } },
                .poly_opt = .{ .fill_color = Colorf.orange },
            },
        },
        .hitbox = .{
            .active = true,
            .mask = Thing.Faction.opposing_masks.get(caster.faction),
            .deactivate_on_hit = true,
            .deactivate_on_update = false,
            .effect = flare_dart.hit_effect,
            .radius = flare_dart.ball_radius,
        },
    };
    _ = try room.queueSpawnThing(&ball, caster.pos);
}

pub const description =
    \\Fling a flaming flare!
    \\Makes enemies "lit", dealing
    \\additional damage. Each stack of
    \\"lit" does 1 damage per second
    \\for 4 seconds.
;

pub fn getDescription(self: *const Spell, buf: []u8) Error![]u8 {
    const flare_dart: @This() = self.kind.flare_dart;
    const fmt =
        \\Damage: {}
        \\
        \\{s}
        \\
    ;
    const ball_damage: i32 = utl.as(i32, flare_dart.hit_effect.damage);
    return std.fmt.bufPrint(buf, fmt, .{ ball_damage, description });
}

pub fn getTags(self: *const Spell) Spell.Tag.Array {
    const flare_dart: @This() = self.kind.flare_dart;
    const damage_str = utl.bufPrintLocal("{d:.0}", .{flare_dart.hit_effect.damage}) catch "";
    return Spell.Tag.makeArray(&.{
        &.{
            .{ .icon = .{ .sprite_enum = .target } },
            .{ .icon = .{ .sprite_enum = .mouse } },
        },
        &.{
            .{ .icon = .{ .sprite_enum = .fire } },
            .{ .label = Spell.Tag.Label.initTrunc(damage_str) },
        },
    });
}
