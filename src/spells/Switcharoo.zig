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

pub const title = "Switcharoo";

pub const enum_name = "switcharoo";

const base_range = 300;

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .cast_time = .fast,
        .mana_cost = Spell.ManaCost.num(1),
        .rarity = .interesting,
        .color = StatusEffect.proto_array.get(.mint).color,
        .targeting_data = .{
            .kind = .thing,
            .target_faction_mask = Thing.Faction.Mask.initMany(&.{ .ally, .bezerk, .enemy, .neutral }),
            .max_range = base_range,
            .ray_to_mouse = .{},
            .show_max_range_ring = true,
        },
    },
);

hit_effect: Thing.HitEffect = .{
    .damage = 5,
},

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    params.validate(.thing, caster);
    const switcharoo = self.kind.switcharoo;
    const target_pos = params.pos;
    const caster_pos = caster.pos;
    caster.pos = target_pos;

    if (room.getThingById(params.thing.?)) |target| {
        target.pos = caster_pos;
        if (target.hurtbox) |*hurtbox| {
            hurtbox.hit(target, room, switcharoo.hit_effect, caster);
        }
    }
}

pub const description =
    \\Switch your position with another
    \\creature. The creature takes
    \\damage.
;

pub fn getDescription(self: *const Spell, buf: []u8) Error![]u8 {
    const switcharoo: @This() = self.kind.switcharoo;
    const fmt =
        \\Damage: {}
        \\
        \\{s}
        \\
    ;
    const damage: i32 = utl.as(i32, switcharoo.hit_effect.damage);
    return std.fmt.bufPrint(buf, fmt ++ "\n", .{ damage, description });
}

pub fn getTags(self: *const Spell) Spell.Tag.Array {
    const switcharoo: @This() = self.kind.switcharoo;
    return Spell.Tag.makeArray(&.{
        &.{
            .{ .icon = .{ .sprite_enum = .target } },
            .{ .icon = .{ .sprite_enum = .skull } },
        },
        &.{
            .{ .icon = .{ .sprite_enum = .wizard, .tint = .orange } },
            .{ .icon = .{ .sprite_enum = .arrows_opp } },
            .{ .icon = .{ .sprite_enum = .ouchy_skull } },
        },
        &.{
            .{ .icon = .{ .sprite_enum = .magic } },
            .{ .label = Spell.Tag.fmtLabel("{d:.0}", .{switcharoo.hit_effect.damage}) },
        },
    });
}
