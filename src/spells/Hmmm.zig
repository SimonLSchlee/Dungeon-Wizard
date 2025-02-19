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
        .color = Spell.colors.magic,
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

pub fn getTooltip(self: *const Spell, tt: *Spell.Tooltip) Error!void {
    const hmmm: @This() = self.kind.hmmm;
    const fmt =
        \\Gain {} {any}quickdraw.
    ;
    tt.desc = try Spell.Tooltip.Desc.fromSlice(
        try std.fmt.bufPrint(&tt.desc.buffer, fmt, .{
            hmmm.stacks + 1,
            StatusEffect.getIcon(.quickdraw),
        }),
    );
    tt.infos.appendAssumeCapacity(.{ .status = .quickdraw });
}

pub fn getNewTags(self: *const Spell) Error!Spell.NewTag.Array {
    const hmmm: @This() = self.kind.hmmm;
    return Spell.NewTag.Array.fromSlice(&.{
        Spell.NewTag.fromFmt("{any}{}", .{ StatusEffect.getIcon(.quickdraw), hmmm.stacks + 1 }),
    }) catch unreachable;
}
