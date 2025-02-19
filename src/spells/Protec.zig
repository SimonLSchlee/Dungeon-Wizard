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

pub const title = "Protec";

pub const enum_name = "protec";
pub const Controllers = [_]type{};

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .cast_time = .fast,
        .color = Spell.colors.shield,
        .targeting_data = .{
            .kind = .thing,
            .max_range = 100,
            .show_max_range_ring = true,
            .target_faction_mask = Thing.Faction.Mask.initFull(),
        },
    },
);

num_stacks: i32 = 7,

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    params.validate(.thing, caster);
    const protec: @This() = self.kind.protec;
    if (room.getThingById(params.thing.?)) |thing| {
        thing.statuses.getPtr(.protected).addStacks(thing, protec.num_stacks);
    }
}

pub fn getTooltip(self: *const Spell, tt: *Spell.Tooltip) Error!void {
    const protec: @This() = self.kind.protec;
    const fmt =
        \\Protect{any} the target creature
        \\from the next attack. Lasts {} seconds.
    ;
    tt.desc = try Spell.Tooltip.Desc.fromSlice(
        try std.fmt.bufPrint(&tt.desc.buffer, fmt, .{
            StatusEffect.getIcon(.protected),
            protec.num_stacks,
        }),
    );
    tt.infos.appendAssumeCapacity(.{ .status = .protected });
}

pub fn getNewTags(self: *const Spell) Error!Spell.NewTag.Array {
    const protec: @This() = self.kind.protec;
    return Spell.NewTag.Array.fromSlice(&.{
        try Spell.NewTag.makeStatus(.protected, utl.as(i32, protec.num_stacks)),
    }) catch unreachable;
}
