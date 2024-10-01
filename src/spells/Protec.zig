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

const Spell = @import("../Spell.zig");
const TargetKind = Spell.TargetKind;
const TargetingData = Spell.TargetingData;
const Params = Spell.Params;
const ThingData = Spell.ThingData;

pub const enum_name = "protec";
pub const Controllers = [_]type{};

pub const proto = Spell.makeProto(
    .protec,
    .{
        .color = .red,
        .targeting_data = .{
            .kind = .self,
        },
    },
);

pub fn render(self: *const Thing, room: *const Room) Error!void {
    _ = self;
    _ = room;
}
pub fn update(self: *Thing, room: *Room) Error!void {
    _ = self;
    _ = room;
}
pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    _ = self;
    _ = caster;
    _ = room;
    _ = params;
}
