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
const icon_text = @import("../icon_text.zig");
const Data = @import("../Data.zig");

const Spell = @import("../Spell.zig");
const TargetKind = Spell.TargetKind;
const TargetingData = Spell.TargetingData;
const Params = Spell.Params;

pub const title = "Impling";

pub const enum_name = "impling";
pub const Controllers = [_]type{};

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .cast_time = .slow,
        .mana_cost = Spell.ManaCost.num(3),
        .rarity = .exceptional,
        .color = draw.Coloru.rgb(194, 222, 49).toColorf(),
        .targeting_data = .{
            .kind = .pos,
            .target_mouse_pos = true,
            .max_range = 100,
            .show_max_range_ring = true,
        },
        .mislay = true,
    },
);

const SoundRef = struct {
    var chime = Data.Ref(Data.Sound).init("creep-chime");
};

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    params.validate(.pos, caster);
    const impling = self.kind.impling;
    _ = impling;
    const target_pos = params.pos;
    const spawner = Thing.SpawnerController.prototypeSummon(.impling);
    _ = try room.queueSpawnThing(&spawner, target_pos);
    _ = App.get().sfx_player.playSound(&SoundRef.chime, .{});
}

pub const description =
    \\Cordially request the presence of
    \\a minor demon to aid your
    \\endeavors.
;

pub fn getTooltip(self: *const Spell, tt: *Spell.Tooltip) Error!void {
    _ = self;
    const fmt =
        \\{any}Summon an {any}.
        \\{any}.
    ;
    tt.desc = try Spell.Tooltip.Desc.fromSlice(
        try std.fmt.bufPrint(&tt.desc.buffer, fmt, .{
            icon_text.Icon.summon,
            Thing.CreatureKind.impling,
            Spell.Keyword.mislay,
        }),
    );
    tt.infos.appendAssumeCapacity(.{ .creature = .impling });
    tt.infos.appendAssumeCapacity(.{ .keyword = .mislay });
}

pub fn getNewTags(self: *const Spell) Error!Spell.NewTag.Array {
    _ = self;
    return Spell.NewTag.Array.fromSlice(&.{
        .{
            .card_label = try Spell.NewTag.CardLabel.fromSlice(
                try utl.bufPrintLocal("{any}{any}", .{
                    icon_text.Icon.summon,
                    icon_text.Icon.impling,
                }),
            ),
        },
        .{
            .card_label = try Spell.NewTag.CardLabel.fromSlice(
                try utl.bufPrintLocal("{any}", .{
                    Spell.Keyword.mislay.getIcon(),
                }),
            ),
        },
    }) catch unreachable;
}
