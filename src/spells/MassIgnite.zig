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
const Data = @import("../Data.zig");

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
        .mana_cost = Spell.ManaCost.num(2),
        .cast_time = .fast,
        .color = Spell.colors.fire,
        .rarity = .exceptional,
        .targeting_data = .{
            .kind = .self,
            .target_faction_mask = Thing.Faction.Mask.initOne(.enemy),
        },
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

const SoundRef = struct {
    var crackle = Data.Ref(Data.Sound).init("crackle");
};

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
    _ = App.get().sfx_player.playSound(&SoundRef.crackle, .{});
}

pub fn getTooltip(self: *const Spell, tt: *Spell.Tooltip) Error!void {
    const mass_ignite: @This() = self.kind.mass_ignite;
    const bonus_dmg = Thing.Damage{
        .kind = .fire,
        .amount = mass_ignite.bonus_hit_effect.damage,
    };
    const fmt =
        \\{any}Light ALL enemies on fire.
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
            StatusEffect.getDurationSeconds(.stunned, mass_ignite.bonus_hit_effect.status_stacks.get(.stunned)).?,
        }),
    );
    tt.infos.appendAssumeCapacity(.{ .damage = .fire });
    tt.infos.appendAssumeCapacity(.{ .status = .lit });
    tt.infos.appendAssumeCapacity(.{ .status = .stunned });
}

pub fn getNewTags(self: *const Spell) Error!Spell.NewTag.Array {
    var buf: [64]u8 = undefined;
    const mass_ignite: @This() = self.kind.mass_ignite;
    return Spell.NewTag.Array.fromSlice(&.{
        .{
            .card_label = try Spell.NewTag.CardLabel.fromSlice(
                try std.fmt.bufPrint(&buf, "{any}{any}{any}{any}", .{ icon_text.Icon.target, icon_text.Icon.skull, icon_text.Icon.skull, icon_text.Icon.skull }),
            ),
        },
        try Spell.NewTag.makeStatus(.lit, 1),
        .{
            .card_label = try Spell.NewTag.CardLabel.fromSlice(
                try std.fmt.bufPrint(&buf, "Bonus/{any}:", .{StatusEffect.getIcon(.lit)}),
            ),
            .start_on_new_line = true,
        },
        try Spell.NewTag.makeDamage(.fire, mass_ignite.bonus_hit_effect.damage, false),
        try Spell.NewTag.makeStatus(.stunned, mass_ignite.bonus_hit_effect.status_stacks.get(.stunned)),
    }) catch unreachable;
}
