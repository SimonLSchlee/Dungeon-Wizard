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

const Spell = @import("../Spell.zig");
const TargetKind = Spell.TargetKind;
const TargetingData = Spell.TargetingData;
const Params = Spell.Params;

pub const enum_name = "mint";
pub const Controllers = [_]type{Projectile};

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .cast_time = 1,
        .color = StatusEffect.proto_array.get(.mint).color,
        .targeting_data = .{
            .kind = .pos,
            .ray_to_mouse = .{
                .fixed_range = true,
                .max_range = 200,
                .thickness = 7, // TODO use radius below
            },
        },
    },
);

damage: f32 = 6,
mint_stacks: i32 = 10,
radius: f32 = 7,
range: f32 = 200,
max_speed: f32 = 3,

pub const Projectile = struct {
    pub const controller_enum_name = enum_name ++ "_projectile";

    end_pos: V2f,

    pub fn update(self: *Thing, room: *Room) Error!void {
        const spell_controller = &self.controller.spell;
        const spell = spell_controller.spell;
        const mint = spell.kind.mint;
        _ = mint;
        const params = spell_controller.params;
        _ = params;
        const projectile: *@This() = &spell_controller.controller.mint_projectile;
        if (self.hitbox) |hitbox| {
            if (!hitbox.active) {
                self.deferFree(room);
            }
        }
        if (self.pos.dist(projectile.end_pos) < self.vel.length() * 2) {
            self.deferFree(room);
        }
        self.moveAndCollide(room);
    }
};

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    assert(std.meta.activeTag(params.target) == Spell.TargetKind.pos);
    const mint = self.kind.mint;
    const target_pos = params.target.pos;
    const target_dir = if (target_pos.sub(caster.pos).normalizedChecked()) |d| d else V2f.right;

    var coin = Thing{
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
                .mint_projectile = .{
                    .end_pos = caster.pos.add(target_dir.scale(mint.range)),
                },
            },
        } },
        .renderer = .{
            .shape = .{
                .kind = .{
                    .circle = .{
                        .radius = mint.radius,
                    },
                },
                .poly_opt = .{ .fill_color = self.color },
            },
        },
        .hitbox = .{
            .active = true,
            .mask = Thing.Faction.opposing_masks.get(caster.faction),
            .deactivate_on_hit = true,
            .deactivate_on_update = false,
            .damage = mint.damage,
            .radius = mint.radius,
        },
    };
    try coin.init();
    defer coin.deinit();
    _ = try room.queueSpawnThing(&coin, caster.pos);
}
