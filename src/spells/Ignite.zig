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
            .max_range = 100,
            .show_max_range_ring = true,
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
    .damage_kind = .fire,
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

pub fn getTooltip(self: *const Spell, tt: *Spell.Tooltip) Error!void {
    const ignite: @This() = self.kind.ignite;
    const bonus_dmg = Thing.Damage{
        .kind = .fire,
        .amount = ignite.bonus_hit_effect.damage,
    };
    const fmt =
        \\{any}Light an enemy on fire.
        \\For each existing stack of
        \\{any}lit, deal an additional
        \\{any} damage and {any}stun
        \\for {d:.0} seconds.
    ;
    tt.desc = try Spell.Tooltip.Desc.fromSlice(
        try std.fmt.bufPrint(&tt.desc.buffer, fmt, .{
            StatusEffect.getIcon(.lit),
            StatusEffect.getIcon(.lit),
            bonus_dmg,
            StatusEffect.getIcon(.stunned),
            StatusEffect.getDurationSeconds(.stunned, ignite.bonus_hit_effect.status_stacks.get(.stunned)).?,
        }),
    );
    tt.infos.appendAssumeCapacity(.{ .damage = .fire });
    tt.infos.appendAssumeCapacity(.{ .status = .lit });
    tt.infos.appendAssumeCapacity(.{ .status = .stunned });
}

pub fn getNewTags(self: *const Spell) Error!Spell.NewTag.Array {
    var buf: [64]u8 = undefined;
    const ignite: @This() = self.kind.ignite;
    return Spell.NewTag.Array.fromSlice(&.{
        try Spell.NewTag.makeStatus(.lit, 1),
        .{
            .card_label = try Spell.NewTag.CardLabel.fromSlice(
                try std.fmt.bufPrint(&buf, "Bonus/{any}:", .{StatusEffect.getIcon(.lit)}),
            ),
            .start_on_new_line = true,
        },
        try Spell.NewTag.makeDamage(.fire, ignite.bonus_hit_effect.damage, false),
        try Spell.NewTag.makeStatus(.stunned, ignite.bonus_hit_effect.status_stacks.get(.stunned)),
    }) catch unreachable;
}
