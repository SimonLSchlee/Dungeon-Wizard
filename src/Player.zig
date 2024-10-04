const std = @import("std");
const assert = std.debug.assert;
const u = @import("util.zig");

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
const Thing = @import("Thing.zig");
const Room = @import("Room.zig");
const Spell = @import("Spell.zig");
const Player = @This();

pub const enum_name = "player";

pub fn protoype() Error!Thing {
    var ret = Thing{
        .kind = .player,
        .spawn_state = .instance,
        .coll_radius = 20,
        .vision_range = 300,
        .coll_mask = Thing.CollMask.initMany(&.{ .creature, .tile }),
        .coll_layer = Thing.CollMask.initMany(&.{.creature}),
        .controller = .{ .player = .{} },
        .renderer = .{ .creature = .{
            .draw_color = .cyan,
            .draw_radius = 20,
        } },
        .animator = .{ .creature = .{
            .creature_kind = .wizard,
        } },
    };
    try ret.init();
    return ret;
}

pub const InputController = struct {
    pub const Movement = struct {
        const State = enum {
            none,
            walk,
        };

        state: State = .none,
        ticks_in_state: i64 = 0,
    };
    movement: Movement = .{},

    pub fn update(self: *Thing, room: *Room) Error!void {
        assert(self.spawn_state == .spawned);
        const plat = getPlat();

        if (plat.input_buffer.mouseBtnIsDown(.right)) {
            const mouse_pos = plat.screenPosToCamPos(room.camera, plat.input_buffer.getCurrMousePos());
            try self.findPath(room, mouse_pos);
        }
        if (plat.input_buffer.mouseBtnIsJustPressed(.left)) {
            const mouse_pos = plat.screenPosToCamPos(room.camera, plat.input_buffer.getCurrMousePos());
            if (room.getThingByPos(mouse_pos)) |thing| {
                var spell = Spell.getProto(.unherring);
                try spell.cast(self, room, .{ .target = .{ .thing = thing.id } });
            }
        }
        // move
        {
            const p = self.followPathGetNextPoint(20);
            const input_dir = p.sub(self.pos).normalizedOrZero();

            const accel_dir: V2f = input_dir;
            // non-leap accel params
            const accel_params: Thing.AccelParams = .{
                .accel = 0.15,
                .friction = 0.09,
                .max_speed = 2,
            };
            const movement = &self.controller.player.movement;

            movement.state = move_state: switch (movement.state) {
                .none => {
                    if (!input_dir.isZero()) {
                        movement.ticks_in_state = 0;
                        continue :move_state .walk;
                    }
                    _ = self.animator.creature.play(.idle, .{ .loop = true });
                    break :move_state .none;
                },
                .walk => {
                    if (input_dir.isZero()) {
                        movement.ticks_in_state = 0;
                        continue :move_state .none;
                    }
                    _ = self.animator.creature.play(.move, .{ .loop = true });
                    break :move_state .walk;
                },
            };

            movement.ticks_in_state += 1;
            self.updateVel(accel_dir, accel_params);
            if (!self.vel.isZero()) {
                self.dir = self.vel.normalized();
            }
        }

        try self.moveAndCollide(room);
    }
};
