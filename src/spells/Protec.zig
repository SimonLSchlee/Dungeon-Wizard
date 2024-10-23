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
        .cast_secs = 0.5,
        .obtainableness = std.EnumSet(Spell.Obtainableness).initOne(.starter),
        .color = StatusEffect.proto_array.get(.protected).color,
        .targeting_data = .{
            .kind = .self,
        },
    },
);

num_stacks: i32 = 1,
max_stacks: i32 = 5,

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    assert(params.target == .self);
    const protec: @This() = self.kind.protec;
    caster.statuses.getPtr(.protected).stacks += protec.num_stacks;

    _ = room;
}

pub const description =
    \\Conjure a personal shield
    \\that renders you invulnerable
    \\to the next hit.
;

pub fn getDescription(self: *const Spell, buf: []u8) Error![]u8 {
    const protec: @This() = self.kind.protec;
    const fmt =
        \\Duration: {} secs
        \\
        \\{s}
        \\Stacks up to {} times.
        \\
    ;
    const dur_secs: i32 = protec.num_stacks * utl.as(i32, @divFloor(StatusEffect.proto_array.get(.protected).cooldown.num_ticks, core.fups_per_sec));
    const b = try std.fmt.bufPrint(buf, fmt, .{ dur_secs, description, protec.max_stacks });
    return b;
}
