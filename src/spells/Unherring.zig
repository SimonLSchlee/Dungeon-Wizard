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

const Spell = @import("../Spell.zig");
const TargetKind = Spell.TargetKind;
const TargetingData = Spell.TargetingData;
const Params = Spell.Params;

pub const title = "Unherring Missile";

pub const enum_name = "unherring";
pub const Controllers = [_]type{Projectile};

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .cast_time = .medium,
        .obtainableness = std.EnumSet(Spell.Obtainableness).initOne(.starter),
        .color = .red,
        .targeting_data = .{
            .kind = .thing,
            .target_faction_mask = Thing.Faction.Mask.initOne(.enemy),
            .max_range = 175,
            .show_max_range_ring = true,
            .ray_to_mouse = .{ .thickness = 1 },
            .requires_los_to_thing = true,
        },
    },
);

hit_effect: Thing.HitEffect = .{
    .damage = 6,
},

pub const Projectile = struct {
    pub const controller_enum_name = enum_name ++ "_projectile";

    target_pos: V2f = .{},
    target_radius: f32 = 10,
    state: enum {
        loop,
        end,
    } = .loop,

    pub fn update(self: *Thing, room: *Room) Error!void {
        const spell_controller = &self.controller.spell;
        const spell = spell_controller.spell;
        const unherring = spell.kind.unherring;
        const params = spell_controller.params;
        const projectile: *Projectile = &spell_controller.controller.unherring_projectile;
        const target_id = params.target.thing;
        const _target = room.getThingById(target_id);
        const animator = &self.animator.?;

        switch (projectile.state) {
            .loop => {
                _ = animator.play(.loop, .{ .loop = true });
                if (_target) |target| {
                    projectile.target_pos = target.pos;
                    projectile.target_radius = target.coll_radius;
                    if (target.hurtbox) |*hurtbox| {
                        projectile.target_pos = target.pos.add(hurtbox.rel_pos);
                        projectile.target_radius = hurtbox.radius;
                    }
                }

                const v = projectile.target_pos.sub(self.pos);
                if (v.length() < self.coll_radius + projectile.target_radius) {
                    projectile.state = .end;
                    if (_target) |target| {
                        if (target.hurtbox) |*hurtbox| {
                            hurtbox.hit(target, room, unherring.hit_effect, self);
                        }
                    }
                }
                self.updateVel(v.normalized(), self.accel_params);
                if (self.vel.normalizedChecked()) |n| {
                    self.dir = n;
                }
                self.moveAndCollide(room);
            },
            .end => {
                self.renderer.vfx.draw_normal = false;
                self.renderer.vfx.draw_over = true;
                self.updateVel(.{}, .{});
                if (animator.play(.end, .{}).contains(.end)) {
                    self.deferFree(room);
                }
                if (animator.curr_anim_frame == 1) {
                    self.renderer.vfx.rotate_to_dir = false;
                }
            },
        }
    }
};

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    assert(std.meta.activeTag(params.target) == Spell.TargetKind.thing);
    assert(utl.unionTagEql(params.target, .{ .thing = .{} }));

    const _target = room.getThingById(params.target.thing);
    if (_target == null) {
        // fizzle
        return;
    }
    const target = _target.?;

    const herring = Thing{
        .kind = .projectile,
        .coll_radius = 5,
        .accel_params = .{
            .accel = 99,
            .max_speed = 7.5,
        },
        .controller = .{ .spell = .{
            .spell = self.*,
            .params = params,
            .controller = .{ .unherring_projectile = .{
                .target_pos = target.pos,
                .target_radius = target.coll_radius,
            } },
        } },
        .renderer = .{
            .vfx = .{
                .draw_over = false,
                .draw_normal = true,
                .rotate_to_dir = true,
                .flip_x_to_dir = true,
            },
        },
        .animator = .{ .kind = .{ .vfx = .{ .sheet_name = .herring } } },
    };
    _ = try room.queueSpawnThing(&herring, caster.pos);
}

pub const description =
    \\This little fish never misses!
    \\Just point and click. Does
    \\fish-type damage, of course.
;

pub fn getDescription(self: *const Spell, buf: []u8) Error![]u8 {
    const unherring: @This() = self.kind.unherring;
    const fmt =
        \\Damage: {}
        \\
        \\{s}
        \\
    ;
    const damage: i32 = utl.as(i32, unherring.hit_effect.damage);
    return std.fmt.bufPrint(buf, fmt, .{ damage, description });
}
