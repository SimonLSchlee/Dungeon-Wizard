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

pub const title = "Expose";

pub const enum_name = "expose";
pub const Controllers = [_]type{Projectile};

const base_radius = 50;

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .cast_time = .slow,
        .obtainableness = std.EnumSet(Spell.Obtainableness).initOne(.starter),
        .color = StatusEffect.proto_array.get(.exposed).color,
        .targeting_data = .{
            .kind = .pos,
            .target_faction_mask = Thing.Faction.Mask.initOne(.enemy),
            .max_range = 200,
            .show_max_range_ring = true,
            .radius_at_target = base_radius,
        },
    },
);

hit_effect: Thing.HitEffect = .{
    .damage = 8,
    .status_stacks = StatusEffect.StacksArray.initDefault(0, .{ .exposed = 5 }),
},
radius: f32 = base_radius,

pub const Projectile = struct {
    pub const controller_enum_name = enum_name ++ "_projectile";

    state: enum {
        expanding,
        fading,
    } = .expanding,
    timer: utl.TickCounter = utl.TickCounter.init(15),

    pub fn update(self: *Thing, room: *Room) Error!void {
        const spell_controller = &self.controller.spell;
        const spell = spell_controller.spell;
        const expose = spell.kind.expose;
        const params = spell_controller.params;
        _ = params;
        const projectile: *Projectile = &spell_controller.controller.expose_projectile;

        _ = projectile.timer.tick(false);
        switch (projectile.state) {
            .expanding => {
                if (!projectile.timer.running) {
                    projectile.timer = utl.TickCounter.init(45);
                    projectile.state = .fading;
                    self.hitbox.?.active = true;
                    self.renderer.shape.kind.circle.radius = expose.radius;
                } else {
                    self.renderer.shape.kind.circle.radius = expose.radius * projectile.timer.remapTo0_1();
                }
            },
            .fading => {
                if (!projectile.timer.running) {
                    self.deferFree(room);
                }
                self.renderer.shape.poly_opt.fill_color = spell.color.fade(1 - projectile.timer.remapTo0_1());
            },
        }
    }
};

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    assert(std.meta.activeTag(params.target) == Spell.TargetKind.pos);
    const expose = self.kind.expose;
    const target_pos = params.target.pos;
    const hit_circle = Thing{
        .kind = .projectile,
        .accel_params = .{
            .accel = 0.5,
            .max_speed = 5,
        },
        .controller = .{ .spell = .{
            .spell = self.*,
            .params = params,
            .controller = .{ .expose_projectile = .{} },
        } },
        .hitbox = .{
            .deactivate_on_hit = false,
            .deactivate_on_update = true,
            .effect = expose.hit_effect,
            .mask = Thing.Faction.opposing_masks.get(caster.faction),
            .radius = expose.radius,
        },
        .renderer = .{ .shape = .{
            .kind = .{ .circle = .{ .radius = 5 } },
            .draw_normal = false,
            .draw_under = true,
            .poly_opt = .{ .fill_color = proto.color },
        } },
    };
    _ = try room.queueSpawnThing(&hit_circle, target_pos);
}

pub const description =
    \\Add "exposed" stacks to enemies in
    \\a small area. Exposed enemies take
    \\30% additional damage from all
    \\sources.
;
// TODO percentage could change? ^

pub fn getDescription(self: *const Spell, buf: []u8) Error![]u8 {
    const expose: @This() = self.kind.expose;
    const fmt =
        \\Damage: {}
        \\Duration: {} secs
        \\
        \\{s}
        \\
    ;
    const dur_secs: i32 = expose.hit_effect.status_stacks.get(.exposed) * utl.as(i32, @divFloor(StatusEffect.proto_array.get(.exposed).cooldown.num_ticks, core.fups_per_sec));
    const damage: i32 = utl.as(i32, expose.hit_effect.damage);
    return std.fmt.bufPrint(buf, fmt, .{ damage, dur_secs, description });
}
