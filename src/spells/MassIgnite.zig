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

pub const title = "Mass Ignite";

pub const enum_name = "mass_ignite";

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .cast_time = .fast,
        .color = .orange,
        .rarity = .exceptional,
        .targeting_data = .{
            .kind = .self,
            .target_faction_mask = Thing.Faction.Mask.initOne(.enemy),
        },
        .mana_cost = .{ .number = 1 },
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
    params.validate(.self, caster);
    const mass_ignite: @This() = self.kind.mass_ignite;
    var it = room.things.iterator();
    while (it.next()) |target| {
        if (!(target.isAttackableCreature() and target.isEnemy())) {
            continue;
        }
        if (target.hurtbox) |*hurtbox| {
            const lit_stacks = target.statuses.get(.lit).stacks;
            var hit_effect = mass_ignite.hit_effect;
            if (lit_stacks > 0) {
                hit_effect = mass_ignite.bonus_hit_effect;
                hit_effect.damage *= utl.as(f32, lit_stacks);
                hit_effect.status_stacks.getPtr(.stunned).* *= lit_stacks;
            }
            hurtbox.hit(target, room, hit_effect, null);
        }
    }
}

pub const description =
    \\Set ALL enemies ablaze.
    \\If an enemy is already ablaze,
    \\also stun them and do bonus
    \\damage per ablaze stack.
;

pub fn getDescription(self: *const Spell, buf: []u8) Error![]u8 {
    const mass_ignite: @This() = self.kind.mass_ignite;
    _ = mass_ignite;
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
    const mass_ignite: @This() = self.kind.mass_ignite;
    return Spell.Tag.makeArray(&.{
        &.{
            .{ .icon = .{ .sprite_enum = .target } },
            .{ .icon = .{ .sprite_enum = .skull } },
            .{ .icon = .{ .sprite_enum = .skull } },
            .{ .icon = .{ .sprite_enum = .skull } },
        },
        &.{
            .{ .icon = .{ .sprite_enum = .fire } },
        },
        &.{
            .{ .label = Spell.Tag.Label.fromSlice("Bonus:") catch unreachable },
        },
        &.{
            .{ .icon = .{ .sprite_enum = .fire } },
            .{ .label = Spell.Tag.fmtLabel("{d:.0}", .{mass_ignite.bonus_hit_effect.damage}) },
        },
        &.{
            .{ .icon = .{ .sprite_enum = .spiral, .tint = draw.Coloru.rgb(255, 235, 147).toColorf() } },
            .{ .icon = .{ .sprite_enum = .ouchy_skull } },
        },
    });
}
