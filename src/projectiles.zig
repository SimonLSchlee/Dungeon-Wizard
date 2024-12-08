const std = @import("std");
const assert = std.debug.assert;
const utl = @import("util.zig");

pub const Platform = @import("raylib.zig");
const core = @import("core.zig");
const Error = core.Error;
const Key = core.Key;
const draw = @import("draw.zig");
const Colorf = draw.Colorf;
const geom = @import("geometry.zig");
const V2f = @import("V2f.zig");
const v2f = V2f.v2f;
const V2i = @import("V2i.zig");
const v2i = V2i.v2i;

const App = @import("App.zig");
const getPlat = App.getPlat;
const Data = @import("Data.zig");
const Thing = @import("Thing.zig");
const Room = @import("Room.zig");
const Spell = @import("Spell.zig");
const Item = @import("Item.zig");
const gameUI = @import("gameUI.zig");
const sprites = @import("sprites.zig");
const Action = @This();

pub const ProjectileKind = enum {
    arrow,
    bomb,

    pub fn prototype(self: ProjectileKind) Thing {
        switch (self) {
            .arrow => return gobbowArrow(),
            .bomb => return gobbomberBomb(),
        }
        unreachable;
    }
};

fn gobbowArrow() Thing {
    const arrow = Thing{
        .kind = .projectile,
        .coll_radius = 2.5,
        .accel_params = .{
            .accel = 2,
            .friction = 0,
            .max_speed = 2,
        },
        .coll_mask = Thing.Collision.Mask.initMany(&.{.tile}),
        .controller = .{ .projectile = .{
            .kind = .arrow,
        } },
        .renderer = .{ .shape = .{
            .kind = .{ .arrow = .{
                .length = 17.5,
                .thickness = 1.5,
            } },
            .poly_opt = .{ .fill_color = draw.Coloru.rgb(220, 172, 89).toColorf() },
        } },
        .hitbox = .{
            .active = true,
            .deactivate_on_hit = true,
            .deactivate_on_update = false,
            .effect = .{ .damage = 7 },
            .radius = 2,
            .rel_pos = V2f.right.scale(14),
        },
    };
    return arrow;
}

fn gobbomberBomb() Thing {
    const flight_ticks = core.secsToTicks(2);
    const max_y: f32 = 150;
    const v0: f32 = 2 * max_y / utl.as(f32, flight_ticks);
    const g = -2 * v0 / utl.as(f32, flight_ticks);
    const bomb = Thing{
        .kind = .projectile,
        .accel_params = .{
            .accel = 2,
            .friction = 0,
            .max_speed = 1,
        },
        .controller = .{ .projectile = .{
            .kind = .bomb,
            .timer = utl.TickCounter.init(flight_ticks),
            .z_vel = v0,
            .z_accel = g,
        } },
        .renderer = .{ .shape = .{
            .kind = .{ .circle = .{
                .radius = 4,
            } },
            .poly_opt = .{ .fill_color = Colorf.rgb(0.2, 0.18, 0.2) },
        } },
        .hitbox = .{
            .active = false,
            .deactivate_on_hit = false,
            .deactivate_on_update = true,
            .effect = .{ .damage = 10 },
            .radius = 17.5,
        },
    };
    return bomb;
}

pub const Controller = struct {
    kind: ProjectileKind,
    state: enum {
        in_flight,
        hitting,
        destroyed,
    } = .in_flight,
    target_pos: V2f = .{},
    timer: utl.TickCounter = .{},
    z_vel: f32 = 0,
    z_accel: f32 = 0,

    pub fn update(self: *Thing, room: *Room) Error!void {
        assert(self.spawn_state == .spawned);
        var controller = &self.controller.projectile;
        switch (controller.kind) {
            .arrow => {
                switch (controller.state) {
                    .in_flight => {
                        const done = self.last_coll != null or if (self.hitbox) |h| !h.active else false;
                        if (done) {
                            controller.state = .hitting;
                            self.vel = .{};
                            return;
                        }
                        self.updateVel(self.dir, self.accel_params);
                    },
                    .hitting => {
                        // TODO anim
                        self.deferFree(room);
                        return;
                    },
                    .destroyed => {
                        // TODO anim
                        self.deferFree(room);
                        return;
                    },
                }
            },
            .bomb => {
                switch (controller.state) {
                    .in_flight => {
                        if (self.hitbox) |*h| {
                            h.rel_pos = controller.target_pos.sub(self.pos);
                        }
                        _ = controller.timer.tick(false);
                        controller.z_vel += controller.z_accel;
                        self.renderer.shape.rel_pos.y += -controller.z_vel;
                        if (self.pos.dist(controller.target_pos) < self.accel_params.max_speed) {
                            self.vel = .{};
                            if (self.hitbox) |*h| {
                                h.active = true;
                            }
                            controller.state = .hitting;
                        } else {
                            self.updateVel(self.dir, self.accel_params);
                        }
                    },
                    .hitting => {
                        const done = if (self.hitbox) |h| !h.active else false;
                        if (done) {
                            self.deferFree(room);
                            return;
                        }
                    },
                    else => {
                        self.deferFree(room);
                        return;
                    },
                }
            },
        }
    }
};
