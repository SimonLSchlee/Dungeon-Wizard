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

pub const title = "Ignite";

pub const enum_name = "ignite";

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .cast_time = .fast,
        .color = .orange,
        .targeting_data = .{
            .kind = .thing,
            .target_faction_mask = Thing.Faction.Mask.initOne(.enemy),
            .max_range = 200,
            .show_max_range_ring = true,
            .ray_to_mouse = .{ .thickness = 1 },
            .requires_los_to_thing = false,
        },
        .mana_cost = .{ .number = 0 },
    },
);

hit_effect: Thing.HitEffect = .{
    .damage = 0,
    .status_stacks = StatusEffect.StacksArray.initDefault(0, .{
        .lit = 1,
    }),
},
bonus_hit_effect: Thing.HitEffect = .{
    .damage = 3,
    .status_stacks = StatusEffect.StacksArray.initDefault(0, .{
        .stunned = 2,
        .lit = 1,
    }),
},

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    params.validate(.thing, caster);
    const ignite: @This() = self.kind.ignite;
    const _target = room.getThingById(params.thing.?);
    if (_target == null) {
        // fizzle
        return;
    }
    const target = _target.?;
    if (target.hurtbox) |*hurtbox| {
        const lit_stacks = target.statuses.get(.lit).stacks;
        var hit_effect = ignite.hit_effect;
        if (lit_stacks > 0) {
            hit_effect = ignite.bonus_hit_effect;
            hit_effect.damage *= utl.as(f32, lit_stacks);
            hit_effect.status_stacks.getPtr(.stunned).* *= lit_stacks;
        }
        hurtbox.hit(target, room, hit_effect, null);
    }
}

pub const description =
    \\Set an enemy ablaze.
    \\If the enemy is already ablaze,
    \\also stun them and do bonus
    \\damage per ablaze stack.
;

pub fn getDescription(self: *const Spell, buf: []u8) Error![]u8 {
    const ignite: @This() = self.kind.ignite;
    _ = ignite;
    const fmt =
        \\Stun duration: 2 secs per ablaze stack
        \\Bonus damage: 3 per ablaze stack
        \\
        \\{s}
        \\
    ;
    return std.fmt.bufPrint(buf, fmt, .{description});
}

pub fn getTags(self: *const Spell) Spell.Tag.Array {
    const ignite: @This() = self.kind.ignite;
    return Spell.Tag.makeArray(&.{
        &.{
            .{ .icon = .{ .sprite_enum = .target } },
            .{ .icon = .{ .sprite_enum = .skull } },
        },
        &.{
            .{ .icon = .{ .sprite_enum = .fire } },
        },
        &.{
            .{ .label = Spell.Tag.Label.fromSlice("?") catch unreachable },
            .{ .icon = .{ .sprite_enum = .fire } },
            .{ .icon = .{ .sprite_enum = .arrow_right } },
            .{ .icon = .{ .sprite_enum = .spiral, .tint = draw.Coloru.rgb(255, 235, 147).toColorf() } },
            .{ .icon = .{ .sprite_enum = .ouchy_skull } },
            .{ .icon = .{ .sprite_enum = .fire } },
            .{ .label = Spell.Tag.fmtLabel("{d:.0}", .{ignite.bonus_hit_effect.damage}) },
        },
    });
}
