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
const Data = @import("../Data.zig");

const Collision = @import("../Collision.zig");
const Spell = @import("../Spell.zig");
const TargetKind = Spell.TargetKind;
const TargetingData = Spell.TargetingData;
const Params = Spell.Params;

pub const title = "Rimefrost";

pub const enum_name = "rimefrost";

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .cast_time = .fast,
        .color = draw.Coloru.rgb(119, 158, 241).toColorf(),
        .targeting_data = .{
            .kind = .thing,
            .target_faction_mask = Thing.Faction.Mask.initFull(),
            .max_range = 100,
            .show_max_range_ring = true,
            .requires_los_to_thing = false,
        },
        .mana_cost = .{ .number = 0 },
    },
);

hit_effect: Thing.HitEffect = .{
    .damage = 0,
    .status_stacks = StatusEffect.StacksArray.initDefault(0, .{
        .cold = 1,
    }),
},
shield_amount: f32 = 5,
duration_secs: f32 = 7,

const SoundRef = struct {
    var crackle = Data.Ref(Data.Sound).init("crackle");
};

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    params.validate(.thing, caster);
    const rimefrost: @This() = self.kind.rimefrost;
    const target = room.getThingById(params.thing.?) orelse return;
    if (target.hurtbox) |*hurtbox| {
        hurtbox.hit(target, room, rimefrost.hit_effect, caster);
    }
    if (target.hp) |*hp| {
        hp.addShield(rimefrost.shield_amount, core.secsToTicks(rimefrost.duration_secs));
    }
    _ = App.get().sfx_player.playSound(&SoundRef.crackle, .{});
}

pub fn getTooltip(self: *const Spell, tt: *Spell.Tooltip) Error!void {
    const rimefrost: @This() = self.kind.rimefrost;
    const fmt =
        \\Make a creature {any}cold
        \\and give it {any}{d:.0} shield
        \\for {d:.0} seconds.
    ;
    tt.desc = try Spell.Tooltip.Desc.fromSlice(
        try std.fmt.bufPrint(&tt.desc.buffer, fmt, .{
            StatusEffect.getIcon(.cold),
            StatusEffect.getIcon(.shield),
            rimefrost.shield_amount,
            rimefrost.duration_secs,
        }),
    );
    tt.infos.appendAssumeCapacity(.{ .status = .cold });
    tt.infos.appendAssumeCapacity(.{ .status = .shield });
    tt.infos.appendAssumeCapacity(.{ .status = .frozen });
}

pub fn getNewTags(self: *const Spell) Error!Spell.NewTag.Array {
    const rimefrost: @This() = self.kind.rimefrost;
    return Spell.NewTag.Array.fromSlice(&.{
        try Spell.NewTag.makeStatus(.cold, 1),
        try Spell.NewTag.makeStatus(.shield, utl.as(i32, rimefrost.shield_amount)),
    }) catch unreachable;
}
