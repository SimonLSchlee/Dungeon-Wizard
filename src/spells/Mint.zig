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

pub const title = "Mint 'Em";

pub const enum_name = "mint";
pub const Controllers = [_]type{Projectile};

const base_radius = 3.25;
const base_range = 100;

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .cast_time = .fast,
        .rarity = .interesting,
        .obtainableness = Spell.Obtainableness.Mask.initEmpty(), // TODO reenable?
        .color = StatusEffect.proto_array.get(.mint).color,
        .targeting_data = .{
            .kind = .pos,
            .fixed_range = true,
            .max_range = base_range,
            .ray_to_mouse = .{
                .thickness = base_radius, // TODO use radius below?
                .cast_orig_dist = 10,
            },
        },
        .mislay = true,
    },
);

hit_effect: Thing.HitEffect = .{
    .damage = 10,
    .status_stacks = StatusEffect.StacksArray.initDefault(0, .{ .mint = 10 }),
},
radius: f32 = base_radius,
range: f32 = base_range,
max_speed: f32 = 3,
gold_cost: i32 = 1,

pub const Projectile = struct {
    pub const controller_enum_name = enum_name ++ "_projectile";

    pub fn update(self: *Thing, room: *Room) Error!void {
        const spell_controller = &self.controller.spell;
        const spell = spell_controller.spell;
        const mint = spell.kind.mint;
        _ = mint;
        const params = spell_controller.params;
        const target_pos = params.pos;
        const projectile: *@This() = &spell_controller.controller.mint_projectile;
        _ = projectile;

        if (self.hitbox) |hitbox| {
            if (!hitbox.active) {
                self.deferFree(room);
            } else if (self.pos.dist(target_pos) < self.vel.length() * 2) {
                self.deferFree(room);
            }
        }
    }
};

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    params.validate(.pos, caster);
    const mint = self.kind.mint;
    const target_pos = params.pos;
    const target_dir = if (target_pos.sub(caster.pos).normalizedChecked()) |d| d else V2f.right;
    var run = App.get().run;
    if (run.gold <= 0) {
        // fizzle
        return;
    }
    run.gold -= 1;

    const coin = Thing{
        .kind = .projectile,
        .dir = target_dir,
        .vel = target_dir.scale(mint.max_speed),
        .controller = .{ .spell = .{
            .spell = self.*,
            .params = params,
            .controller = .{
                .mint_projectile = .{},
            },
        } },
        .renderer = .{
            .shape = .{
                .kind = .{ .circle = .{ .radius = mint.radius } },
                .poly_opt = .{ .fill_color = self.color },
            },
        },
        .hitbox = .{
            .mask = Thing.Faction.opposing_masks.get(caster.faction),
            .deactivate_on_hit = true,
            .deactivate_on_update = false,
            .effect = mint.hit_effect,
            .radius = mint.radius,
        },
    };
    coin.hitbox.?.activate(room);
    _ = try room.queueSpawnThing(&coin, caster.pos);
}

pub const description =
    \\Enchant a coin and throw it. It
    \\applies "mint" stacks on enemies,
    \\which decay at a rate of 1 per sec.
    \\Killing an enemy with "mint" stacks
    \\yields that much gold.
    \\If you can't pay, the spell fizzles.
;

pub fn getDescription(self: *const Spell, buf: []u8) Error![]u8 {
    const mint: @This() = self.kind.mint;
    const fmt =
        \\Gold cost: {}
        \\Damage: {}
        \\Mint stacks: {}
        \\
        \\{s}
        \\
    ;
    const stacks: i32 = mint.hit_effect.status_stacks.get(.mint);
    const damage: i32 = utl.as(i32, mint.hit_effect.damage);
    return std.fmt.bufPrint(buf, fmt, .{ mint.gold_cost, damage, stacks, description });
}
