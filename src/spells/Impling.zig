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

pub const title = "Invite Impling";
pub const description =
    \\Cordially request the presence of
    \\a minor demon to aid your
    \\endeavors.
;

pub const enum_name = "impling";
pub const Controllers = [_]type{};

const base_radius = 7;
const base_range = 200;

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .cast_time = 1,
        .color = draw.Coloru.rgb(194, 222, 49).toColorf(),
        .targeting_data = .{
            .kind = .pos,
            .target_mouse_pos = true,
        },
    },
);

pub fn implingProto() Error!Thing {
    return Thing{
        .kind = .creature,
        .creature_kind = .impling,
        .spawn_state = .instance,
        .coll_radius = 15,
        .vision_range = 160,
        .coll_mask = Thing.Collision.Mask.initMany(&.{ .creature, .tile }),
        .coll_layer = Thing.Collision.Mask.initMany(&.{.creature}),
        .accel_params = .{
            .accel = 0.07,
            .max_speed = 1.0,
        },
        .controller = .{ .enemy = .{
            .attack_range = 30,
            .attack_cooldown = utl.TickCounter.initStopped(50),
            .LOS_thiccness = 20,
        } },
        .renderer = .{ .creature = .{
            .draw_color = .yellow,
            .draw_radius = 15,
        } },
        .animator = .{ .creature = .{
            .creature_kind = .impling,
        } },
        .hitbox = .{
            .mask = Thing.Faction.opposing_masks.get(.ally),
            .radius = 20,
            .rel_pos = V2f.right.scale(30),
            .effect = .{ .damage = 12 },
        },
        .hurtbox = .{
            .radius = 15,
        },
        .selectable = .{
            .height = 13 * 4, // TODO pixellszslz
            .radius = 8 * 4,
        },
        .hp = Thing.HP.init(25),
        .faction = .ally,
    };
}

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    assert(std.meta.activeTag(params.target) == Spell.TargetKind.pos);
    _ = caster;
    const impling = self.kind.impling;
    _ = impling;
    const target_pos = params.target.pos;
    const spawner = Thing.SpawnerController.prototype(.impling);
    _ = try room.queueSpawnThing(&spawner, target_pos);
}
