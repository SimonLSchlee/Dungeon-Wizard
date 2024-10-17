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
pub const description =
    \\Cast a projectile which applies
    \\temporary "mint" stacks on enemies.
    \\Killing an enemy with "mint" stacks
    \\yields that much gold.
;

pub const enum_name = "mint";
pub const Controllers = [_]type{Projectile};

const base_radius = 7;
const base_range = 200;

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .cast_time = 1,
        .color = StatusEffect.proto_array.get(.mint).color,
        .targeting_data = .{
            .kind = .pos,
            .fixed_range = true,
            .max_range = base_range,
            .ray_to_mouse = .{
                .ends_at_coll_mask = Collision.Mask.initOne(.creature),
                .thickness = base_radius, // TODO use radius below?
            },
        },
    },
);

hit_effect: Thing.HitEffect = .{
    .damage = 9,
    .status_stacks = StatusEffect.StacksArray.initDefault(0, .{ .mint = 10 }),
},
radius: f32 = base_radius,
range: f32 = base_range,
max_speed: f32 = 6,

pub const Projectile = struct {
    pub const controller_enum_name = enum_name ++ "_projectile";

    pub fn update(self: *Thing, room: *Room) Error!void {
        const spell_controller = &self.controller.spell;
        const spell = spell_controller.spell;
        const mint = spell.kind.mint;
        _ = mint;
        const params = spell_controller.params;
        const target_pos = params.target.pos;
        const projectile: *@This() = &spell_controller.controller.mint_projectile;
        _ = projectile;

        if (self.hitbox) |hitbox| {
            if (!hitbox.active) {
                self.deferFree(room);
            } else if (self.pos.dist(target_pos) < self.vel.length() * 2) {
                self.deferFree(room);
            }
        }
        self.moveAndCollide(room);
    }
};

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    assert(std.meta.activeTag(params.target) == Spell.TargetKind.pos);
    const mint = self.kind.mint;
    const target_pos = params.target.pos;
    const target_dir = if (target_pos.sub(caster.pos).normalizedChecked()) |d| d else V2f.right;

    const coin = Thing{
        .kind = .projectile,
        .dir = target_dir,
        .vel = target_dir.scale(mint.max_speed),
        .coll_radius = 5,
        .accel_params = .{
            .accel = 0.5,
            .max_speed = 5,
        },
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
            .active = true,
            .mask = Thing.Faction.opposing_masks.get(caster.faction),
            .deactivate_on_hit = true,
            .deactivate_on_update = false,
            .effect = mint.hit_effect,
            .radius = mint.radius,
        },
    };
    _ = try room.queueSpawnThing(&coin, caster.pos);
}
