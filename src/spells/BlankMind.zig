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

pub const title = "Blank Mind";

pub const enum_name = "blank_mind";
pub const Controllers = [_]type{};

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .cast_time = .fast,
        .after_cast_slot_cooldown_secs = 0,
        .draw_immediate = true,
        .color = StatusEffect.proto_array.get(.protected).color,
        .targeting_data = .{
            .kind = .self,
        },
    },
);

shield_amount: f32 = 15,
duration_secs: f32 = 5,

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    assert(params.target == .self);
    const blank_mind: @This() = self.kind.blank_mind;
    if (caster.hp) |*hp| {
        hp.addShield(blank_mind.shield_amount, core.secsToTicks(blank_mind.duration_secs));
    }
    _ = room;
}

pub const description =
    \\Shield self from damage.
    \\Draw next spell immediately.
;

pub fn getDescription(self: *const Spell, buf: []u8) Error![]u8 {
    const blank_mind: @This() = self.kind.blank_mind;
    const fmt =
        \\Shield amount: {}
        \\Duration: {} secs
        \\
        \\{s}
        \\
    ;

    const b = try std.fmt.bufPrint(buf, fmt, .{ blank_mind.shield_amount, blank_mind.duration_secs, description });
    return b;
}
