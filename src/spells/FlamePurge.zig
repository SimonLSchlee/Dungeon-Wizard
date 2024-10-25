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

const Collision = @import("../Collision.zig");
const Spell = @import("../Spell.zig");
const TargetKind = Spell.TargetKind;
const TargetingData = Spell.TargetingData;
const Params = Spell.Params;

const FlamePurge = @This();
pub const title = "Flame Purge";

pub const enum_name = "flame_purge";
pub const Controllers = [_]type{Projectile};

const base_explode_radius = 100;

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .cast_secs = 0.5,
        .rarity = .pedestrian,
        .color = .red,
        .targeting_data = .{
            .kind = .self,
            .radius_at_target = base_explode_radius,
        },
    },
);

explode_hit_effect: Thing.HitEffect = .{
    .damage = 0,
    .status_stacks = StatusEffect.StacksArray.initDefault(0, .{ .lit = 1 }),
    .force = .{ .from_center = 4 },
},
explode_radius: f32 = base_explode_radius,

pub const Projectile = struct {
    pub const controller_enum_name = enum_name ++ "_projectile";

    explode_counter: utl.TickCounter = utl.TickCounter.init(10),

    pub fn update(self: *Thing, room: *Room) Error!void {
        const spell_controller = &self.controller.spell;
        const spell = spell_controller.spell;
        const flame_purge: FlamePurge = spell.kind.flame_purge;
        _ = flame_purge;
        const params = spell_controller.params;
        _ = params;
        const projectile: *@This() = &spell_controller.controller.flame_purge_projectile;

        if (projectile.explode_counter.tick(false)) {
            self.deferFree(room);
        }
    }
};

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    assert(std.meta.activeTag(params.target) == Spell.TargetKind.self);
    const flame_purge: @This() = self.kind.flame_purge;
    // purrgeu
    const caster_lit_status = caster.statuses.getPtr(.lit);
    const transferred_stacks: i32 = caster_lit_status.stacks;
    caster_lit_status.stacks = 0;
    var updated_hit_effect = flame_purge.explode_hit_effect;
    updated_hit_effect.status_stacks.getPtr(.lit).* += transferred_stacks;

    const ball = Thing{
        .kind = .projectile,
        .controller = .{ .spell = .{
            .spell = self.*,
            .params = params,
            .controller = .{
                .flame_purge_projectile = .{},
            },
        } },
        .renderer = .{
            .shape = .{
                .kind = .{ .circle = .{ .radius = flame_purge.explode_radius } },
                .poly_opt = .{ .fill_color = Colorf.orange },
            },
        },
        .hitbox = .{
            .active = true,
            .mask = Thing.Faction.opposing_masks.get(caster.faction),
            .deactivate_on_update = true,
            .effect = updated_hit_effect,
            .radius = flame_purge.explode_radius,
        },
    };
    _ = try room.queueSpawnThing(&ball, caster.pos);
}

pub const description =
    \\Fire explodes outwards from you,
    \\setting alight surrounding enemies
    \\and pushing them away.
    \\If you are already on fire, your
    \\'lit' stacks transfer onto all
    \\affected by the blast.
;

pub fn getDescription(self: *const Spell, buf: []u8) Error![]u8 {
    const flame_purge: @This() = self.kind.flame_purge;
    _ = flame_purge;
    const fmt =
        \\Lit stacks transferred: 1 + any more you have
        \\
        \\{s}
        \\
    ;
    return std.fmt.bufPrint(buf, fmt, .{description});
}
