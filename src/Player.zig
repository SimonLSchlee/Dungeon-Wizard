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
        trot,
        leap,
    };

    state: State = .none,
    ticks_in_state: i64 = 0,
    last_leaped_tick: i64 = 0,
    leap_cd_ticks: i64 = 20,
    leap_ticks: i64 = 10,
};

call_range: f32 = 200,
call_ticks: i64 = 100,
call_pos: V2f = .{},
last_command_id: i32 = -1,

bork_range: f32 = 200,
bork_ticks: i64 = 45,
bork_pos: V2f = .{},

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
    switch (player.curr_action) {
        .call => {
            const f: f32 = 1 - (u.as(f32, player.action_tick) / u.as(f32, player.call_ticks));
            const opt = draw.PolyOpt{
                .fill_color = null,
                .outline_color = Colorf.green.fade(f),
            };
            getPlat().circlef(player.call_pos, player.call_range + self.coll_radius, opt);
        },
        .bork => {
            const f: f32 = 1 - (u.as(f32, player.action_tick) / u.as(f32, player.bork_ticks));
            const opt = draw.PolyOpt{
                .fill_color = null,
                .outline_color = Colorf.orange.fade(f),
            };
            getPlat().circlef(player.bork_pos, player.bork_range + self.coll_radius, opt);
        },
        else => {},
    }
}

pub fn update(_: *const Player, self: *Thing, room: *Room) Error!void {
    assert(self.spawn_state == .spawned);
    const plat = getPlat();
    var player = &self.kind.player;

    if (false) {
        if (player.curr_action) |a| {
            if (player.action_ticks_left > 0) {
                switch (a) {
                    .call => {
                        player.call_pos = self.pos;
                    },
                    .bork => {},
                }
            } else {
                player.curr_action = null;
            }
        }
        if (player.curr_action == null) {
            if (plat.input_buffer.mouseBtnIsJustPressed(.right)) {
                player.action_ticks_left = player.call_cd_ticks;
                player.curr_action = .call;
                player.last_command_id = room.next_command_id;
                room.next_command_id += 1;
            } else if (plat.input_buffer.mouseBtnIsJustPressed(.right)) {
                player.action_ticks_left = player.call_cd_ticks;
                player.curr_action = .bork;
                player.bork_pos = self.pos;
            }
        }
    }

    player.action_tick += 1;
    player.curr_action = action_state: switch (player.curr_action) {
        .none => {
            if (plat.input_buffer.mouseBtnIsJustPressed(.right)) {
                player.action_tick = 0;
                continue :action_state .call;
            } else if (plat.input_buffer.mouseBtnIsJustPressed(.left)) {
                player.action_tick = 0;
                continue :action_state .bork;
            }
            break :action_state .none;
        },
        .call => {
            if (player.action_tick == 0) {
                player.last_command_id = room.next_command_id;
                room.next_command_id += 1;
            } else if (player.action_tick < player.call_ticks) {} else {
                player.action_tick = 0;
                continue :action_state .none;
            }
            player.call_pos = self.pos;
            break :action_state .call;
        },
        .bork => {
            if (player.action_tick == 0) {
                const mouse_pos = plat.screenPosToCamPos(room.camera, plat.input_buffer.getCurrMousePos());
                const vec = mouse_pos.sub(self.pos).clampLength(player.bork_range - self.coll_radius);
                player.bork_pos = self.pos.add(vec);
            } else if (player.action_tick < player.bork_ticks) {} else {
                player.action_tick = 0;
                continue :action_state .none;
            }
            break :action_state .bork;
        },
    };

    // move
    const leap_pressed: bool = plat.keyIsDown(.space);
    var input_dir: V2f = .{};
    if (plat.keyIsDown(Key.left) or plat.keyIsDown(.a)) {
        input_dir.x = -1;
    } else if (plat.keyIsDown(Key.right) or plat.keyIsDown(.d)) {
        input_dir.x = 1;
    }
    if (plat.keyIsDown(Key.up) or plat.keyIsDown(.w)) {
        input_dir.y = -1;
    } else if (plat.keyIsDown(Key.down) or plat.keyIsDown(.s)) {
        input_dir.y = 1;
    }
    input_dir = input_dir.normalizedOrZero();

    {
        var accel_dir: V2f = input_dir;
        // non-leap accel params
        var accel_params: Thing.AccelParams = .{
            .accel = 0.15,
            .friction = 0.09,
            .max_speed = 2,
        };
        var desired_dir: V2f = input_dir;
        const movement = &player.movement;
        const can_leap = room.curr_tick >= movement.last_leaped_tick + movement.leap_cd_ticks;

        movement.state = move_state: switch (movement.state) {
            .none => {
                if (can_leap and leap_pressed) {
                    movement.ticks_in_state = 0;
                    continue :move_state .leap;
                } else if (!input_dir.isZero()) {
                    movement.ticks_in_state = 0;
                    continue :move_state .trot;
                }
                break :move_state .none;
            },
            .trot => {
                if (can_leap and leap_pressed) {
                    movement.ticks_in_state = 0;
                    continue :move_state .leap;
                } else if (input_dir.isZero()) {
                    movement.ticks_in_state = 0;
                    continue :move_state .none;
                }
                break :move_state .trot;
            },
            .leap => {
                if (movement.ticks_in_state >= movement.leap_ticks) {
                    movement.ticks_in_state = 0;
                    continue :move_state .none;
                }
                if (movement.ticks_in_state == 0) {
                    movement.last_leaped_tick = room.curr_tick;
                    accel_params = .{ .accel = 5, .friction = 0.2, .max_speed = 5 };
                } else {
                    accel_params = .{ .accel = 0, .friction = 0.2 };
                }
                accel_dir = self.dir;
                desired_dir = input_dir;
                break :move_state .leap;
            },
        };
        const min_dir_accel_params: Thing.DirAccelParams = .{
            .ang_accel = u.pi * 0.0005,
            .max_ang_vel = u.pi * 0.02,
        };
        const max_dir_accel_params: Thing.DirAccelParams = .{
            .ang_accel = u.pi * 0.006,
            .max_ang_vel = u.pi * 0.06,
        };
        const vel_t: f32 = 1 - u.clampf(self.vel.length() / accel_params.max_speed, 0, 1);
        const dir_accel_params: Thing.DirAccelParams = .{
            .ang_accel = u.remapClampf(0, 1, min_dir_accel_params.ang_accel, max_dir_accel_params.ang_accel, vel_t),
            .max_ang_vel = u.remapClampf(0, 1, min_dir_accel_params.max_ang_vel, max_dir_accel_params.max_ang_vel, vel_t),
        };

        self.updateVel(accel_dir, accel_params);
        self.updateDir(desired_dir, dir_accel_params);
        movement.ticks_in_state += 1;
    }

    try self.moveAndCollide(room);
}
