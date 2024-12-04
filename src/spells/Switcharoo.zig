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
const icon_text = @import("../icon_text.zig");

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

pub fn getTooltip(self: *const Spell, tt: *Spell.Tooltip) Error!void {
    const switcharoo: @This() = self.kind.switcharoo;
    const hit_damage = Thing.Damage{
        .kind = .magic,
        .amount = switcharoo.hit_effect.damage,
    };
    const fmt =
        \\Switch your position with another
        \\creature. Deal {any} damage.
    ;
    tt.desc = try Spell.Tooltip.Desc.fromSlice(
        try std.fmt.bufPrint(&tt.desc.buffer, fmt, .{
            hit_damage,
        }),
    );
}

pub fn getNewTags(self: *const Spell) Error!Spell.NewTag.Array {
    var buf: [64]u8 = undefined;
    const switcharoo: @This() = self.kind.switcharoo;
    return Spell.NewTag.Array.fromSlice(&.{
        .{
            .card_label = try Spell.NewTag.CardLabel.fromSlice(
                try std.fmt.bufPrint(&buf, "{any}{any}{any}{any}{any}", .{
                    icon_text.Fmt{ .tint = .orange },
                    icon_text.Icon.wizard,
                    icon_text.Fmt{ .tint = .white },
                    icon_text.Icon.arrows_opp,
                    icon_text.Icon.skull,
                }),
            ),
        },
        try Spell.NewTag.makeDamage(.magic, switcharoo.hit_effect.damage, false),
    }) catch unreachable;
}
