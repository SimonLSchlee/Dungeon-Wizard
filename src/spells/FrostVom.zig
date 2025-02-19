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

pub const title = "Frost Cone";

pub const enum_name = "frost_vom";
pub const Controllers = [_]type{Projectile};

const cone_radius = 100;
const cone_rads: f32 = utl.pi / 3;

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .cast_time = .medium,
        .mana_cost = Spell.ManaCost.num(2),
        .rarity = .interesting,
        .color = Spell.colors.ice,
        .targeting_data = .{
            .kind = .pos,
            .cone_from_self_to_mouse = .{
                .radius = cone_radius,
                .radians = cone_rads,
            },
        },
    },
);

hit_effect: Thing.HitEffect = .{
    .damage = 7,
    .damage_kind = .ice,
    .status_stacks = StatusEffect.StacksArray.initDefault(0, .{ .cold = 2 }),
},
radius: f32 = cone_radius,
arc_rads: f32 = cone_rads,
expand_dur_ticks: i64 = 30,
fade_dur_ticks: i64 = 60,

pub const Projectile = struct {
    pub const controller_enum_name = enum_name ++ "_projectile";

    counter: utl.TickCounter,
    state: enum {
        expand,
        fade,
    } = .expand,

    pub fn update(self: *Thing, room: *Room) Error!void {
        const spell_controller = &self.controller.spell;
        const spell = spell_controller.spell;
        const frost_vom = spell.kind.frost_vom;
        const params = spell_controller.params;
        _ = params;
        const projectile: *@This() = &spell_controller.controller.frost_vom_projectile;
        const shape = &self.renderer.shape;

        const counter_up = projectile.counter.tick(false);
        projectile.state = state: switch (projectile.state) {
            .expand => {
                shape.kind.sector.radius = utl.remapClampf(
                    0,
                    utl.as(f32, projectile.counter.num_ticks),
                    0,
                    frost_vom.radius,
                    utl.as(f32, projectile.counter.curr_tick),
                );
                if (counter_up) {
                    projectile.counter = utl.TickCounter.init(frost_vom.fade_dur_ticks);
                    shape.kind.sector.radius = frost_vom.radius;
                    for (&room.things.items) |*thing| {
                        if (!thing.isActive()) continue;
                        if (thing.faction == .player) continue;
                        if (thing.hurtbox) |*hurtbox| {
                            const target_pos = thing.pos.add(hurtbox.rel_pos);
                            if (geom.pointIsInSector(
                                target_pos,
                                self.pos,
                                frost_vom.radius,
                                shape.kind.sector.start_ang_rads,
                                shape.kind.sector.end_ang_rads,
                            )) {
                                hurtbox.hit(thing, room, frost_vom.hit_effect, self);
                            }
                        }
                    }
                    break :state .fade;
                }
                break :state .expand;
            },
            .fade => {
                shape.poly_opt.fill_color.?.a = utl.remapClampf(
                    0,
                    utl.as(f32, projectile.counter.num_ticks),
                    0.5,
                    0,
                    utl.as(f32, projectile.counter.curr_tick),
                );
                if (counter_up) {
                    self.deferFree(room);
                }
                break :state .fade;
            },
        };
    }
};

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    params.validate(.pos, caster);
    const frost_vom = self.kind.frost_vom;
    const target_pos = params.pos;
    const target_dir = if (target_pos.sub(caster.pos).normalizedChecked()) |d| d else V2f.right;
    const start_rads = target_dir.toAngleRadians() - frost_vom.arc_rads * 0.5;
    const end_rads = start_rads + frost_vom.arc_rads;

    const vom = Thing{
        .kind = .projectile,
        .dir = target_dir,
        .controller = .{ .spell = .{
            .spell = self.*,
            .params = params,
            .controller = .{
                .frost_vom_projectile = .{
                    .counter = utl.TickCounter.init(frost_vom.expand_dur_ticks),
                },
            },
        } },
        .renderer = .{
            .shape = .{
                .draw_under = true,
                .draw_normal = false,
                .kind = .{
                    .sector = .{
                        .start_ang_rads = start_rads,
                        .end_ang_rads = end_rads,
                        .radius = 0,
                    },
                },
                .poly_opt = .{ .fill_color = self.color },
            },
        },
    };
    _ = try room.queueSpawnThing(&vom, caster.pos);
}

pub fn getTooltip(self: *const Spell, tt: *Spell.Tooltip) Error!void {
    const frost_vom: @This() = self.kind.frost_vom;
    const hit_dmg = Thing.Damage{
        .kind = .ice,
        .amount = frost_vom.hit_effect.damage,
    };
    const fmt =
        \\Deal {any} damage and apply {} {any}cold
        \\to all creatures in a cone.
    ;
    tt.desc = try Spell.Tooltip.Desc.fromSlice(
        try std.fmt.bufPrint(&tt.desc.buffer, fmt, .{
            hit_dmg,
            frost_vom.hit_effect.status_stacks.get(.cold),
            StatusEffect.getIcon(.cold),
        }),
    );
    tt.infos.appendAssumeCapacity(.{ .damage = .ice });
    tt.infos.appendAssumeCapacity(.{ .status = .cold });
    tt.infos.appendAssumeCapacity(.{ .status = .frozen });
}

pub fn getNewTags(self: *const Spell) Error!Spell.NewTag.Array {
    const frost_vom: @This() = self.kind.frost_vom;
    return Spell.NewTag.Array.fromSlice(&.{
        try Spell.NewTag.makeDamage(.ice, frost_vom.hit_effect.damage, true),
        try Spell.NewTag.makeStatus(.cold, frost_vom.hit_effect.status_stacks.get(.cold)),
    }) catch unreachable;
}
