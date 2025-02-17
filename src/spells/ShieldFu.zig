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
duration_secs: f32 = 7,

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    params.validate(.self, caster);
    const shield_fu: @This() = self.kind.shield_fu;
    if (caster.hp) |*hp| {
        hp.addShield(shield_fu.shield_amount, core.secsToTicks(shield_fu.duration_secs));
    }
    _ = room;
}

pub fn getTooltip(self: *const Spell, tt: *Spell.Tooltip) Error!void {
    const shield_fu: @This() = self.kind.shield_fu;
    const fmt =
        \\Gain {any}{d:.0} shield for {d:.0} seconds.
    ;
    tt.desc = try Spell.Tooltip.Desc.fromSlice(
        try std.fmt.bufPrint(&tt.desc.buffer, fmt, .{
            StatusEffect.getIcon(.shield),
            @floor(shield_fu.shield_amount),
            @floor(shield_fu.duration_secs),
        }),
    );
    tt.infos.appendAssumeCapacity(.{ .status = .shield });
}

pub fn getNewTags(self: *const Spell) Error!Spell.NewTag.Array {
    const shield_fu: @This() = self.kind.shield_fu;
    return Spell.NewTag.Array.fromSlice(&.{
        try Spell.NewTag.makeStatus(.shield, utl.as(i32, shield_fu.shield_amount)),
    }) catch unreachable;
}
