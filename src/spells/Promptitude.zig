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
        .cast_secs = 1.5,
        .rarity = .exceptional,
        .color = StatusEffect.proto_array.get(.promptitude).color,
        .targeting_data = .{
            .kind = .self,
        },
    },
);

num_stacks: i32 = 7,

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    assert(params.target == .self);
    const promptitude: @This() = self.kind.promptitude;
    caster.statuses.getPtr(.promptitude).addStacks(promptitude.num_stacks);

    _ = room;
}

pub const description =
    \\Move and cast spells 2x faster.
    \\Memory (slot cooldown) unaffected.
;

pub fn getDescription(self: *const Spell, buf: []u8) Error![]u8 {
    const promptitude: @This() = self.kind.promptitude;
    const fmt =
        \\Duration: {} secs
        \\
        \\{s}
        \\
    ;
    const dur_secs: i32 = promptitude.num_stacks * utl.as(i32, @divFloor(StatusEffect.proto_array.get(.promptitude).cooldown.num_ticks, core.fups_per_sec));
    return std.fmt.bufPrint(buf, fmt, .{ dur_secs, description });
}
