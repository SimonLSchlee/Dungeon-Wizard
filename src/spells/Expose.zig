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
        .cast_time = .medium,
        .mana_cost = Spell.ManaCost.num(2),
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
    .damage = 7,
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
    params.validate(.pos, caster);
    const expose = self.kind.expose;
    const target_pos = params.pos;
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

pub fn getTooltip(self: *const Spell, tt: *Spell.Tooltip) Error!void {
    const expose: @This() = self.kind.expose;
    const hit_damage = Thing.Damage{
        .kind = .magic,
        .amount = expose.hit_effect.damage,
    };
    const fmt =
        \\Deal {any} damage and {any}expose
        \\enemies for {d:.0} seconds.
    ;
    tt.desc = try Spell.Tooltip.Desc.fromSlice(
        try std.fmt.bufPrint(&tt.desc.buffer, fmt, .{
            hit_damage,
            StatusEffect.getIcon(.exposed),
            StatusEffect.getDurationSeconds(.exposed, expose.hit_effect.status_stacks.get(.exposed)).?,
        }),
    );
    tt.infos.appendAssumeCapacity(.{ .status = .exposed });
}

pub fn getNewTags(self: *const Spell) Error!Spell.NewTag.Array {
    const expose: @This() = self.kind.expose;
    return Spell.NewTag.Array.fromSlice(&.{
        try Spell.NewTag.makeDamage(.magic, expose.hit_effect.damage, false),
        try Spell.NewTag.makeStatus(.exposed, expose.hit_effect.status_stacks.get(.exposed)),
    }) catch unreachable;
}
