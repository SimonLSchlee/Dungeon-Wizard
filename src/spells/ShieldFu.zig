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

pub const title = "Shield Fu";

pub const enum_name = "shield_fu";
pub const Controllers = [_]type{};

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .cast_time = .fast,
        .obtainableness = std.EnumSet(Spell.Obtainableness).initOne(.starter),
        .color = StatusEffect.proto_array.get(.protected).color,
        .targeting_data = .{
            .kind = .self,
        },
    },
);

shield_amount: f32 = 9,
duration_secs: f32 = 5,

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    params.validate(.self, caster);
    const shield_fu: @This() = self.kind.shield_fu;
    if (caster.hp) |*hp| {
        hp.addShield(shield_fu.shield_amount, core.secsToTicks(shield_fu.duration_secs));
    }
    _ = room;
}

pub const description =
    \\Shield self from damage.
;

pub fn getDescription(self: *const Spell, buf: []u8) Error![]u8 {
    const shield_fu: @This() = self.kind.shield_fu;
    const fmt =
        \\Shield amount: {}
        \\Duration: {} secs
        \\
        \\{s}
        \\
    ;

    const b = try std.fmt.bufPrint(buf, fmt, .{ shield_fu.shield_amount, shield_fu.duration_secs, description });
    return b;
}

pub fn getTags(self: *const Spell) Spell.Tag.Array {
    const shield_fu: @This() = self.kind.shield_fu;
    return Spell.Tag.makeArray(&.{
        &.{
            .{ .icon = .{ .sprite_enum = .target } },
            .{ .icon = .{ .sprite_enum = .wizard, .tint = .orange } },
        },
        &.{
            .{ .icon = .{ .sprite_enum = .shield_empty } },
            .{ .label = Spell.Tag.fmtLabel("{d:.0}", .{shield_fu.shield_amount}) },
        },
    });
}
