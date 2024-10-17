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
pub const description =
    \\This little fish never misses!
    \\Just point and click. Does
    \\fish-type damage, of course.
;

pub const enum_name = "unherring";
pub const Controllers = [_]type{Projectile};

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .color = .red,
        .targeting_data = .{
            .kind = .thing,
            .target_faction_mask = Thing.Faction.Mask.initOne(.enemy),
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

    pub fn update(self: *Thing, room: *Room) Error!void {
        const spell_controller = &self.controller.spell;
        const spell = spell_controller.spell;
        const unherring = spell.kind.unherring;
        const params = spell_controller.params;
        const projectile = &spell_controller.controller.unherring_projectile;
        const target_id = params.target.thing;
        const _target = room.getThingById(target_id);
        var done = false;

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
            done = true;
            if (_target) |target| {
                if (target.hurtbox) |*hurtbox| {
                    hurtbox.hit(target, room, unherring.hit_effect);
                }
            }
        }

        if (done) {
            // explode/vfx?
            self.deferFree(room);
        } else {
            self.updateVel(v.normalized(), self.accel_params);
            self.updateDir(self.vel, .{ .ang_accel = 999, .max_ang_vel = 999 });
            self.moveAndCollide(room);
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
            .accel = 0.5,
            .max_speed = 5,
        },
        .controller = .{ .spell = .{
            .spell = self.*,
            .params = params,
            .controller = .{ .unherring_projectile = .{
                .target_pos = target.pos,
                .target_radius = target.coll_radius,
            } },
        } },
        .renderer = .{ .shape = .{
            .kind = .{ .circle = .{ .radius = 5 } },
            .poly_opt = .{ .fill_color = Colorf.white },
        } },
    };
    _ = try room.queueSpawnThing(&herring, caster.pos);
}
