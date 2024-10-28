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

pub const title = "Frost Vomit";

pub const enum_name = "frost_vom";
pub const Controllers = [_]type{Projectile};

const cone_radius = 200;
const cone_rads: f32 = utl.pi / 3;

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .cast_time = .medium,
        .rarity = .interesting,
        .color = StatusEffect.proto_array.get(.frozen).color,
        .targeting_data = .{
            .kind = .pos,
            .cone_from_self_to_mouse = .{
                .radius = 200,
                .radians = cone_rads,
            },
        },
    },
);

hit_effect: Thing.HitEffect = .{
    .damage = 9,
    .status_stacks = StatusEffect.StacksArray.initDefault(0, .{ .frozen = 3 }),
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
    assert(std.meta.activeTag(params.target) == Spell.TargetKind.pos);
    const frost_vom = self.kind.frost_vom;
    const target_pos = params.target.pos;
    const target_dir = if (target_pos.sub(caster.pos).normalizedChecked()) |d| d else V2f.right;
    const start_rads = target_dir.toAngleRadians() - frost_vom.arc_rads * 0.5;
    const end_rads = start_rads + frost_vom.arc_rads;

    const vom = Thing{
        .kind = .projectile,
        .dir = target_dir,
        .coll_radius = 5,
        .accel_params = .{
            .accel = 0.5,
            .max_speed = 5,
        },
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

pub const description =
    \\"Hurl" a cone of ice which
    \\freezes enemies.
;

pub fn getDescription(self: *const Spell, buf: []u8) Error![]u8 {
    const frost_vom: @This() = self.kind.frost_vom;
    const fmt =
        \\Damage: {}
        \\Freeze duration: {} secs
        \\
        \\{s}
        \\
    ;
    const dur_secs: i32 = frost_vom.hit_effect.status_stacks.get(.frozen) * utl.as(i32, @divFloor(StatusEffect.proto_array.get(.frozen).cooldown.num_ticks, core.fups_per_sec));
    const damage: i32 = utl.as(i32, frost_vom.hit_effect.damage);
    return std.fmt.bufPrint(buf, fmt, .{ damage, dur_secs, description });
}
