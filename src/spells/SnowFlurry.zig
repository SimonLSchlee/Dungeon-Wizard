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
const projectiles = @import("../projectiles.zig");

const Spell = @import("../Spell.zig");
const TargetKind = Spell.TargetKind;
const TargetingData = Spell.TargetingData;
const Params = Spell.Params;

pub const title = "Snow Flurry";

pub const enum_name = "snow_flurry";
pub const Controllers = [_]type{Projectile};

const cone_radius = 200;
const cone_rads: f32 = utl.pi / 6;

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .cast_time = .medium,
        .mana_cost = Spell.ManaCost.num(1),
        .rarity = .pedestrian,
        .color = Spell.colors.ice,
        .targeting_data = .{
            .kind = .pos,
            .cone_from_self_to_mouse = .{
                .radius = cone_radius,
                .radians = cone_rads,
            },
        },
    },
);

hit_effect: Thing.HitEffect = .{
    .damage = 3,
    .damage_kind = .ice,
    .status_stacks = StatusEffect.StacksArray.initDefault(0, .{ .cold = 1 }),
},
radius: f32 = cone_radius,
arc_rads: f32 = cone_rads,
num_projectiles: usize = 3,

pub const Projectile = struct {
    pub const controller_enum_name = enum_name ++ "_projectile";

    delay_timer: utl.TickCounter,
    num_fired: usize = 0,
    target_mask: Thing.Faction.Mask,

    pub fn update(self: *Thing, room: *Room) Error!void {
        const spell_controller = &self.controller.spell;
        const spell = spell_controller.spell;
        const snow_flurry = spell.kind.snow_flurry;
        const params = spell_controller.params;
        const target_pos = params.pos;
        const projectile: *@This() = &spell_controller.controller.snow_flurry_projectile;

        if (projectile.delay_timer.tick(true)) {
            var target_dir = if (target_pos.sub(self.pos).normalizedChecked()) |d| d else V2f.right;
            target_dir = target_dir.rotRadians(room.rng.random().float(f32) * cone_rads - cone_rads * 0.5);
            var ball = projectiles.Snowball.proto(room);
            ball.dir = target_dir;
            ball.hitbox.?.mask = projectile.target_mask;
            _ = try room.queueSpawnThing(&ball, self.pos);
            projectile.num_fired += 1;
        }
        if (projectile.num_fired >= snow_flurry.num_projectiles) {
            self.deferFree(room);
        }
    }
};

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    params.validate(.pos, caster);
    const snow_flurry = self.kind.snow_flurry;
    _ = snow_flurry;

    const baller = Thing{
        .kind = .projectile,
        .controller = .{ .spell = .{
            .spell = self.*,
            .params = params,
            .controller = .{
                .snow_flurry_projectile = .{
                    .delay_timer = utl.TickCounter.initStopped(15),
                    .target_mask = Thing.Faction.opposing_masks.get(caster.faction),
                },
            },
        } },
    };
    _ = try room.queueSpawnThing(&baller, caster.pos);
}

pub fn getTooltip(self: *const Spell, tt: *Spell.Tooltip) Error!void {
    const snow_flurry: @This() = self.kind.snow_flurry;
    const hit_dmg = Thing.Damage{
        .kind = .ice,
        .amount = snow_flurry.hit_effect.damage,
    };
    const fmt =
        \\Fling 3 snowballs, each dealing
        \\{any} damage.
    ;
    tt.desc = try Spell.Tooltip.Desc.fromSlice(
        try std.fmt.bufPrint(&tt.desc.buffer, fmt, .{
            hit_dmg,
        }),
    );
    tt.infos.appendAssumeCapacity(.{ .damage = .ice });
    tt.infos.appendAssumeCapacity(.{ .status = .cold });
    tt.infos.appendAssumeCapacity(.{ .status = .frozen });
}

pub fn getNewTags(self: *const Spell) Error!Spell.NewTag.Array {
    var buf: [64]u8 = undefined;
    const snow_flurry: @This() = self.kind.snow_flurry;
    return Spell.NewTag.Array.fromSlice(&.{
        .{
            .card_label = try Spell.NewTag.CardLabel.fromSlice(
                try std.fmt.bufPrint(&buf, "3x", .{}),
            ),
            .start_on_new_line = true,
        },
        try Spell.NewTag.makeDamage(.ice, snow_flurry.hit_effect.damage, true),
        try Spell.NewTag.makeStatus(.cold, snow_flurry.hit_effect.status_stacks.get(.cold)),
    }) catch unreachable;
}
