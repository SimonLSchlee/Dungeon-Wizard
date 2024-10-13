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

pub const title = "Blackmail";
pub const description =
    \\Intimidate an enemy into becoming
    \\your ally. For a while, at least.
;

pub const enum_name = "blackmail";
pub const Controllers = [_]type{};

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .cast_time = 4,
        .color = StatusEffect.proto_array.get(.blackmailed).color,
        .targeting_data = .{
            .kind = .thing,
            .target_faction_mask = Thing.Faction.Mask.initOne(.enemy),
        },
    },
);

num_stacks: i32 = 7,

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    assert(std.meta.activeTag(params.target) == Spell.TargetKind.thing);
    assert(utl.unionTagEql(params.target, .{ .thing = .{} }));
    _ = caster;
    const _target = room.getThingById(params.target.thing);
    if (_target == null) {
        // fizzle
        return;
    }
    const target = _target.?;
    const blackmail = self.kind.blackmail;
    target.faction = .ally;
    target.statuses.getPtr(.blackmailed).stacks = blackmail.num_stacks;
}
