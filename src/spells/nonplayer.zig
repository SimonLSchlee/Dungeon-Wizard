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

pub const spells = [_]type{
    struct {
        pub const title = "Summon Bat";
        pub const enum_name = "summon_bat";
        pub const proto = Spell.makeProto(
            std.meta.stringToEnum(Spell.Kind, enum_name).?,
            .{
                .cast_time = .slow,
                .obtainableness = Spell.Obtainableness.Mask.initEmpty(),
                .targeting_data = .{
                    .kind = .pos,
                    .target_mouse_pos = true,
                    .max_range = 50,
                    .show_max_range_ring = true,
                },
            },
        );
        pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
            params.validate(.pos, caster);
            _ = self;
            const target_pos = params.pos;
            var spawner = Thing.SpawnerController.prototype(.bat);
            spawner.faction = caster.faction;
            _ = try room.queueSpawnThing(&spawner, target_pos);
        }
    },
};
