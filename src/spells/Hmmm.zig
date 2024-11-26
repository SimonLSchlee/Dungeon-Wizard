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

pub const title = "Hmmm";

pub const enum_name = "hmmm";

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .rarity = .interesting,
        .cast_time = .fast,
        .color = StatusEffect.proto_array.get(.protected).color,
        .targeting_data = .{
            .kind = .self,
        },
        .draw_immediate = true,
    },
);

stacks: i32 = 2,

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    params.validate(.self, caster);
    const hmmm: @This() = self.kind.hmmm;
    caster.statuses.getPtr(.quickdraw).addStacks(caster, hmmm.stacks);
    _ = room;
}

pub const description =
    \\The next 2 spells are drawn
    \\instantly.
    \\Draw next spell immediately.
;

pub fn getDescription(self: *const Spell, buf: []u8) Error![]u8 {
    const hmmm: @This() = self.kind.hmmm;
    _ = hmmm;
    const fmt =
        \\{s}
        \\
    ;

    const b = try std.fmt.bufPrint(buf, fmt, .{description});
    return b;
}

pub fn getTags(self: *const Spell) Spell.Tag.Array {
    const hmmm: @This() = self.kind.hmmm;
    _ = hmmm;
    return Spell.Tag.makeArray(&.{
        &.{
            .{ .icon = .{ .sprite_enum = .target } },
            .{ .icon = .{ .sprite_enum = .wizard, .tint = .orange } },
        },
        &.{
            .{ .icon = .{ .sprite_enum = .fast_forward } },
            .{ .icon = .{ .sprite_enum = .card } },
            .{ .icon = .{ .sprite_enum = .card } },
            .{ .icon = .{ .sprite_enum = .card } },
        },
    });
}
