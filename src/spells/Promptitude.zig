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

pub const title = "Promptitude";

pub const enum_name = "promptitude";
pub const Controllers = [_]type{};

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .cast_time = .slow,
        .mana_cost = Spell.ManaCost.num(2),
        .rarity = .interesting,
        .color = Spell.colors.magic,
        .targeting_data = .{
            .kind = .thing,
            .max_range = 100,
            .show_max_range_ring = true,
            .target_faction_mask = Thing.Faction.Mask.initMany(&.{
                .player,
                .ally,
            }),
        },
    },
);

num_stacks: i32 = 7,

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    params.validate(.thing, caster);
    const promptitude: @This() = self.kind.promptitude;
    if (room.getThingById(params.thing.?)) |thing| {
        thing.statuses.getPtr(.promptitude).addStacks(caster, promptitude.num_stacks);
    }
}

pub fn getTooltip(self: *const Spell, tt: *Spell.Tooltip) Error!void {
    const promptitude: @This() = self.kind.promptitude;
    const fmt =
        \\Target ally gains {any}promptitude for
        \\{d:.0} seconds.
    ;
    tt.desc = try Spell.Tooltip.Desc.fromSlice(
        try std.fmt.bufPrint(&tt.desc.buffer, fmt, .{
            StatusEffect.getIcon(.promptitude),
            @floor(StatusEffect.getDurationSeconds(.promptitude, promptitude.num_stacks).?),
        }),
    );
    tt.infos.appendAssumeCapacity(.{ .status = .promptitude });
}

pub fn getNewTags(self: *const Spell) Error!Spell.NewTag.Array {
    const promptitude: @This() = self.kind.promptitude;
    return Spell.NewTag.Array.fromSlice(&.{
        try Spell.NewTag.makeStatus(.promptitude, promptitude.num_stacks),
    }) catch unreachable;
}
