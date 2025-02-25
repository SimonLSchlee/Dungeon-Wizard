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

const FlamePurge = @This();
pub const title = "Flame Burst";

pub const enum_name = "flame_purge";
pub const Controllers = [_]type{Projectile};

const base_explode_radius = 50;

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .mana_cost = Spell.ManaCost.num(1),
        .cast_time = .fast,
        .rarity = .pedestrian,
        .color = Spell.colors.fire,
        .targeting_data = .{
            .kind = .self,
            .radius_at_target = base_explode_radius,
        },
    },
);

explode_hit_effect: Thing.HitEffect = .{
    .damage = 6,
    .damage_kind = .fire,
    .status_stacks = StatusEffect.StacksArray.initDefault(0, .{ .lit = 1 }),
    .force = .{ .from_center = 2 },
},
explode_radius: f32 = base_explode_radius,
immune_stacks: i32 = 3,

const SoundRef = struct {
    var woosh = Data.Ref(Data.Sound).init("long-woosh");
};
const AnimRef = struct {
    var explode = Data.Ref(Data.SpriteAnim).init("big-explosion-50px-explode");
};

pub const Projectile = struct {
    pub const controller_enum_name = enum_name ++ "_projectile";

    pub fn update(self: *Thing, room: *Room) Error!void {
        const spell_controller = &self.controller.spell;
        const spell = spell_controller.spell;
        const flame_purge: FlamePurge = spell.kind.flame_purge;
        _ = flame_purge;
        const params = spell_controller.params;
        _ = params;

        if (self.renderer.sprite.playNormal(AnimRef.explode, .{}).contains(.end)) {
            self.deferFree(room);
        }
    }
};

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    params.validate(.self, caster);
    const flame_purge: @This() = self.kind.flame_purge;
    caster.statuses.getPtr(.lit).addStacks(caster, 1);

    var ball = Thing{
        .kind = .projectile,
        .controller = .{ .spell = .{
            .spell = self.*,
            .params = params,
            .controller = .{
                .flame_purge_projectile = .{},
            },
        } },
        .renderer = .{
            .sprite = .{
                .draw_under = true,
                .draw_normal = false,
            },
        },
        .hitbox = .{
            .mask = Thing.Faction.opposing_masks.get(caster.faction),
            .deactivate_on_update = true,
            .deactivate_on_hit = false,
            .effect = flame_purge.explode_hit_effect,
            .radius = flame_purge.explode_radius,
        },
    };
    ball.hitbox.?.activate(room);
    _ = AnimRef.explode.get();
    ball.renderer.sprite.setNormalAnim(AnimRef.explode);
    _ = try room.queueSpawnThing(&ball, caster.pos);
    _ = App.get().sfx_player.playSound(&SoundRef.woosh, .{});
}

pub fn getTooltip(self: *const Spell, tt: *Spell.Tooltip) Error!void {
    const flame_purge: @This() = self.kind.flame_purge;
    const hit_damage = Thing.Damage{
        .kind = .fire,
        .amount = flame_purge.explode_hit_effect.damage,
    };
    const fmt =
        \\Deal {any} damage and knock back
        \\surrounding enemies.
        \\Light yourself on fire! Ouch!
    ;
    tt.desc = try Spell.Tooltip.Desc.fromSlice(
        try std.fmt.bufPrint(&tt.desc.buffer, fmt, .{
            hit_damage,
        }),
    );
    tt.infos.appendAssumeCapacity(.{ .damage = .fire });
    tt.infos.appendAssumeCapacity(.{ .status = .lit });
}

pub fn getNewTags(self: *const Spell) Error!Spell.NewTag.Array {
    var buf: [64]u8 = undefined;
    const flame_purge: @This() = self.kind.flame_purge;
    return Spell.NewTag.Array.fromSlice(&.{
        try Spell.NewTag.makeDamage(.fire, flame_purge.explode_hit_effect.damage, true),
        .{
            .card_label = try Spell.NewTag.CardLabel.fromSlice(
                try std.fmt.bufPrint(&buf, "{any}{any}{any}{any}", .{
                    icon_text.Fmt{ .tint = .orange },
                    icon_text.Icon.wizard,
                    icon_text.Fmt{ .tint = .white },
                    icon_text.Icon.burn,
                }),
            ),
        },
    }) catch unreachable;
}
