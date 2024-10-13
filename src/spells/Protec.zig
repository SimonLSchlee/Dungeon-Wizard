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
pub const description =
    \\Become invincible to the next
    \\instance of damage your receive.
    \\Lasts 5 seconds.
;

pub const enum_name = "protec";
pub const Controllers = [_]type{};

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .color = StatusEffect.proto_array.get(.protected).color,
        .targeting_data = .{
            .kind = .self,
        },
    },
);

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    assert(params.target == .self);
    caster.statuses.getPtr(.protected).stacks += 1;

    _ = self;
    _ = room;
}
