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

const FlamePurge = @This();
pub const title = "Flame Purge";

pub const enum_name = "flame_purge";
pub const Controllers = [_]type{Projectile};

const base_explode_radius = 100;

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .cast_time = .fast,
        .rarity = .pedestrian,
        .color = .red,
        .targeting_data = .{
            .kind = .self,
            .radius_at_target = base_explode_radius,
        },
    },
);

explode_hit_effect: Thing.HitEffect = .{
    .damage = 6,
    .status_stacks = StatusEffect.StacksArray.initDefault(0, .{ .lit = 1 }),
    .force = .{ .from_center = 4 },
},
bonus_damage_per_lit: f32 = 2,
explode_radius: f32 = base_explode_radius,
immune_stacks: i32 = 3,

pub const Projectile = struct {
    pub const controller_enum_name = enum_name ++ "_projectile";

    explode_counter: utl.TickCounter = utl.TickCounter.init(10),

    pub fn update(self: *Thing, room: *Room) Error!void {
        const spell_controller = &self.controller.spell;
        const spell = spell_controller.spell;
        const flame_purge: FlamePurge = spell.kind.flame_purge;
        _ = flame_purge;
        const params = spell_controller.params;
        _ = params;
        const projectile: *@This() = &spell_controller.controller.flame_purge_projectile;

        if (projectile.explode_counter.tick(false)) {
            self.deferFree(room);
        }
    }
};

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    params.validate(.self, caster);
    const flame_purge: @This() = self.kind.flame_purge;
    // purrgeu
    const caster_lit_status = caster.statuses.getPtr(.lit);
    const transferred_stacks: i32 = caster_lit_status.stacks;
    caster_lit_status.stacks = 0;
    var updated_hit_effect = flame_purge.explode_hit_effect;
    //updated_hit_effect.status_stacks.getPtr(.lit).* += transferred_stacks;
    updated_hit_effect.damage += utl.as(f32, transferred_stacks) * flame_purge.bonus_damage_per_lit;

    const ball = Thing{
        .kind = .projectile,
        .controller = .{ .spell = .{
            .spell = self.*,
            .params = params,
            .controller = .{
                .flame_purge_projectile = .{},
            },
        } },
        .renderer = .{
            .shape = .{
                .kind = .{ .circle = .{ .radius = flame_purge.explode_radius } },
                .poly_opt = .{ .fill_color = Colorf.orange },
            },
        },
        .hitbox = .{
            .active = true,
            .mask = Thing.Faction.opposing_masks.get(caster.faction),
            .deactivate_on_update = true,
            .deactivate_on_hit = false,
            .effect = updated_hit_effect,
            .radius = flame_purge.explode_radius,
        },
    };
    _ = try room.queueSpawnThing(&ball, caster.pos);

    caster.statuses.getPtr(.moist).addStacks(caster, flame_purge.immune_stacks);
}

pub fn getToolTip(self: *const Spell, tt: *Spell.ToolTip) Error!void {
    const flame_purge: @This() = self.kind.flame_purge;
    const hit_damage = Thing.Damage{
        .kind = .fire,
        .amount = flame_purge.explode_hit_effect.damage,
    };
    const bonus_damage = Thing.Damage{
        .kind = .fire,
        .amount = flame_purge.bonus_damage_per_lit,
    };
    const fmt =
        \\Deal {any} damage and knock back
        \\surrounding enemies.
        \\Deal an additional {any} for each
        \\{any}lit stack you have.
        \\Gain {any}moist for {} seconds.
    ;
    const desc = try std.fmt.bufPrint(&tt.desc.buffer, fmt, .{
        hit_damage,
        bonus_damage,
        StatusEffect.getIcon(.lit),
        StatusEffect.getIcon(.moist),
        StatusEffect.getDurationSeconds(.moist, flame_purge.immune_stacks).?,
    });
    try tt.desc.resize(desc.len);
    tt.infos.appendAssumeCapacity(.{ .damage = .fire });
    tt.infos.appendAssumeCapacity(.{ .status = .lit });
    tt.infos.appendAssumeCapacity(.{ .status = .moist });
}

pub fn getNewTags(self: *const Spell) Error!Spell.NewTag.Array {
    var buf: [64]u8 = undefined;
    const flame_purge: @This() = self.kind.flame_purge;
    return Spell.NewTag.Array.fromSlice(&.{
        try Spell.NewTag.makeDamage(.fire, flame_purge.explode_hit_effect.damage, false),
        try Spell.NewTag.makeStatus(.moist, flame_purge.immune_stacks),
        .{
            .card_label = try Spell.NewTag.CardLabel.fromSlice(
                try std.fmt.bufPrint(&buf, "Bonus/{any}:", .{icon_text.Icon.burn}),
            ),
            .tooltip_label = try Spell.NewTag.TooltipLabel.fromSlice(
                try std.fmt.bufPrint(&buf, "Bonus per {any}lit:", .{icon_text.Icon.burn}),
            ),
        },
        try Spell.NewTag.makeStatus(.lit, 1),
        try Spell.NewTag.makeDamage(.fire, flame_purge.bonus_damage_per_lit, false),
    }) catch unreachable;
}
