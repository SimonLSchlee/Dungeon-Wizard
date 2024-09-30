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
const Player = @import("Player.zig");

const Movement = struct {
    const State = enum {
        none,
        walk,
    };

    state: State = .none,
    ticks_in_state: i64 = 0,
    last_leaped_tick: i64 = 0,
    leap_cd_ticks: i64 = 20,
    leap_ticks: i64 = 10,
};

action_tick: i64 = 0,
curr_action: enum {
    none,
    call,
    bork,
} = .none,

movement: Movement = .{},

pub fn protoype() Error!Thing {
    var ret = Thing{
        .kind = .{ .player = .{} },
        .spawn_state = .instance,
        .coll_radius = 20,
        .draw_color = Colorf.cyan,
        .vision_range = 300,
    };
    try ret.init();
    return ret;
}

pub fn render(_: *const Player, self: *const Thing, room: *const Room) Error!void {
    try Thing.defaultRender(self, room);
    const player = &self.kind.player;
    _ = player;
}

pub fn update(_: *const Player, self: *Thing, room: *Room) Error!void {
    assert(self.spawn_state == .spawned);
    const plat = getPlat();
    var player = &self.kind.player;

    if (plat.input_buffer.mouseBtnIsJustPressed(.right)) {
        const mouse_pos = plat.screenPosToCamPos(room.camera, plat.input_buffer.getCurrMousePos());
        try self.findPath(room, mouse_pos);
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
        const movement = &player.movement;

        movement.state = move_state: switch (movement.state) {
            .none => {
                if (!input_dir.isZero()) {
                    movement.ticks_in_state = 0;
                    continue :move_state .walk;
                }
                break :move_state .none;
            },
            .walk => {
                if (input_dir.isZero()) {
                    movement.ticks_in_state = 0;
                    continue :move_state .none;
                }
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
