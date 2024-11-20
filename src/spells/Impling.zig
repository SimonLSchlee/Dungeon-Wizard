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

pub const title = "Impling";

pub const enum_name = "impling";
pub const Controllers = [_]type{};

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .cast_time = .slow,
        .mana_cost = Spell.ManaCost.num(2),
        .rarity = .exceptional,
        .color = draw.Coloru.rgb(194, 222, 49).toColorf(),
        .targeting_data = .{
            .kind = .pos,
            .target_mouse_pos = true,
            .max_range = 200,
            .show_max_range_ring = true,
        },
        .mislay = true,
    },
);

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    params.validate(.pos, caster);
    const impling = self.kind.impling;
    _ = impling;
    const target_pos = params.pos;
    const spawner = Thing.SpawnerController.prototype(.impling);
    _ = try room.queueSpawnThing(&spawner, target_pos);
}

pub const description =
    \\Cordially request the presence of
    \\a minor demon to aid your
    \\endeavors.
;

pub fn getDescription(self: *const Spell, buf: []u8) Error![]u8 {
    const impling: @This() = self.kind.impling;
    _ = impling;
    const fmt =
        \\Impling hp: {}
        \\Impling damage: {}
        \\
        \\{s}
        \\
    ;
    const summonProto = App.get().data.creature_protos.getPtr(.impling);
    const hp: i32 = utl.as(i32, summonProto.hp.?.max);
    const damage: i32 = utl.as(i32, summonProto.hitbox.?.effect.damage);
    return std.fmt.bufPrint(buf, fmt, .{ hp, damage, description });
}

pub fn getTags(self: *const Spell) Spell.Tag.Array {
    _ = self;
    return Spell.Tag.makeArray(&.{
        &.{
            .{ .icon = .{ .sprite_enum = .target } },
            .{ .icon = .{ .sprite_enum = .mouse } },
        },
        &.{
            .{ .icon = .{ .sprite_enum = .doorway } },
            .{ .icon = .{ .sprite_enum = .arrow_right } },
            .{ .icon = .{ .sprite_enum = .monster_with_sword } },
        },
    });
}
