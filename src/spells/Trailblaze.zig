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

pub const title = "Trailblaze";

pub const enum_name = "trailblaze";

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .cast_time = .medium,
        .mana_cost = Spell.ManaCost.num(2),
        .rarity = .interesting,
        .color = StatusEffect.proto_array.get(.promptitude).color,
        .targeting_data = .{
            .kind = .self,
        },
    },
);

num_stacks: i32 = 5,

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    params.validate(.self, caster);
    _ = room;
    const trailblaze: @This() = self.kind.trailblaze;
    const status = caster.statuses.getPtr(.trailblaze);
    status.addStacks(caster, trailblaze.num_stacks);
    status.timer.num_ticks = 20;
    status.prev_pos = caster.pos;
    caster.accel_params = .{
        .accel = 0.3,
        .friction = 0.15,
        .max_speed = 1.25,
    };
}

pub fn getTooltip(self: *const Spell, tt: *Spell.Tooltip) Error!void {
    _ = self;
    const fmt =
        \\Gain {any}trailblaze.
    ;
    tt.desc = try Spell.Tooltip.Desc.fromSlice(
        try std.fmt.bufPrint(&tt.desc.buffer, fmt, .{
            StatusEffect.getIcon(.trailblaze),
        }),
    );
    tt.infos.appendAssumeCapacity(.{ .status = .trailblaze });
}

pub fn getNewTags(self: *const Spell) Error!Spell.NewTag.Array {
    const trailblaze: @This() = self.kind.trailblaze;
    return Spell.NewTag.Array.fromSlice(&.{
        try Spell.NewTag.makeStatus(.trailblaze, trailblaze.num_stacks),
    }) catch unreachable;
}
