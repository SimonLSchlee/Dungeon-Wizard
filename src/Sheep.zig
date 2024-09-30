const std = @import("std");
const utl = @import("util.zig");

pub const Platform = @import("raylib.zig");
const core = @import("core.zig");
const Error = core.Error;
const Key = core.Key;
const debug = @import("debug.zig");
const assert = debug.assert;
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
const Sheep = @This();

const AiState = enum {
    idle,
    follow_herd,
    push,
};

const idle_params: Thing.BoidParams = .{ .s_sep = 0.5 };
const follow_params: Thing.BoidParams = .{
    .s_cohere = 1,
    .s_sep = 2,
    .s_align = 0.9,
    .s_avoid = 0.0,
    .s_follow = 1,
    .sep_thing_range = 10,
    .sep_wall_range = 8,
};

// followLastCmdId()
unconfidence: f32 = std.math.inf(f32),
last_command_id: i32 = -1,
completed_last_command: bool = true,
command_arrive_range: f32 = 12,

// idle()
total_push_ticks: i64 = 60,
push_ticks_left: i64 = 0,
push_range: f32 = 60,
push_vec: V2f = .{},
s_align: f32 = 0,
follow_range: f32 = 100,

ai_steering: Thing.BoidParams = idle_params,
ai_state_tick: i64 = 0,
ai_state: AiState = .idle,

pub fn protoype() Error!Thing {
    var ret = Thing{
        .kind = .{ .sheep = .{} },
        .spawn_state = .instance,
        .coll_radius = 20,
        .draw_color = Colorf.magenta,
        .vision_range = 160,
    };
    try ret.init();
    return ret;
}

pub fn render(sheep: *const Sheep, self: *const Thing, room: *const Room) Error!void {
    const plat = getPlat();

    try Thing.defaultRender(self, room);
    if (false) {
        const bar_dims = v2f(40, 8);
        const bar_topleft = self.pos.sub(v2f(bar_dims.x / 2, -30));
        const bar_fill_dims = v2f(bar_dims.x * self.kind.sheep.confidence, bar_dims.y);
        plat.rectf(bar_topleft, bar_dims, .{ .fill_color = Colorf.yellow });
        plat.rectf(bar_topleft, bar_fill_dims, .{ .fill_color = Colorf.blue });
    }
    if (debug.show_sheep_ai) {
        if (false) {
            {
                const txt_topleft = self.pos.add(v2f(self.coll_radius, -self.coll_radius - 10));
                try plat.textf(txt_topleft, "{}", .{self.kind.sheep.last_command_id}, .{ .color = Colorf.red });
            }
            {
                const txt_topleft = self.pos.add(v2f(self.coll_radius, -self.coll_radius + 10));
                try plat.textf(txt_topleft, "{d:.1}", .{self.kind.sheep.unconfidence}, .{ .color = Colorf.white });
            }
            {
                plat.circlef(self.pos, self.coll_radius + self.vision_range, .{ .fill_color = null, .outline_color = Colorf.yellow.fade(0.5) });
            }
        }
        {
            plat.circlef(self.pos, self.coll_radius + sheep.push_range, .{ .fill_color = null, .outline_color = Colorf.orange.fade(0.5) });
            plat.circlef(self.pos, self.coll_radius + sheep.follow_range, .{ .fill_color = null, .outline_color = Colorf.yellow.fade(0.5) });
        }
    }
    if (debug.show_boid_vecs) {
        const f = self.coll_radius * 5;
        const S = struct {
            pub fn boidArrow(pos: V2f, raw_v: V2f, len: f32, color: Colorf) void {
                const p = getPlat();
                if (raw_v.isAlmostZero()) return;
                const v = raw_v.scale(len);
                const end = pos.add(v);
                p.arrowf(pos, end, 3, color);
                p.textf(pos.add(v.scale(0.5)), "{d:0.2}", .{raw_v.length()}, .{ .center = true, .color = Colorf.white, .size = 16 }) catch {};
            }
        };
        S.boidArrow(self.pos, self.dbg.boid_cohere, f, Colorf.cyan);
        S.boidArrow(self.pos, self.dbg.boid_sep, f, Colorf.purple);
        S.boidArrow(self.pos, self.dbg.boid_wall_sep, f, Colorf.purple);
        S.boidArrow(self.pos, self.dbg.boid_align, f, Colorf.blue);
        S.boidArrow(self.pos, self.dbg.boid_desired_vel, f, Colorf.yellow);
        S.boidArrow(self.pos, self.dbg.boid_avoid, f, Colorf.red);
        S.boidArrow(self.pos, self.dbg.boid_follow, f, Colorf.green);
    }
}

pub fn followLastCmdId(self: *Thing, room: *Room) Error!void {
    const sheep = &self.kind.sheep;
    var follow_vec = V2f{};

    var things_in_view: std.BoundedArray(*Thing, 16) = .{};
    const Followable = struct {
        arrived: bool,
        cmd_id: i32,
        pos: V2f,
        unconfidence: f32,
        dist: f32,
        range: f32,
        call_range: f32,
    };
    var followable_in_view: std.BoundedArray(Followable, 32) = .{};
    const best_command_id_so_far = if (room.getConstPlayer()) |p| p.kind.player.last_command_id else -1;

    // get all the nearby followables
    for (&room.things.items) |*thing| {
        if (!thing.isActive()) continue;
        if (thing.id.eql(self.id)) continue;

        const dist = thing.pos.dist(self.pos);
        const range = @max(dist - self.coll_radius - thing.coll_radius, 0);

        if (range < self.vision_range) {
            things_in_view.append(thing) catch break;
        }

        const f: Followable = switch (thing.kind) {
            .player => |player| if (player.is_calling) .{
                .arrived = false,
                .cmd_id = player.last_command_id,
                .pos = player.call_pos,
                .unconfidence = 0,
                .dist = dist,
                .range = range,
                .call_range = player.call_range,
            } else continue,
            .sheep => |s| .{
                .arrived = s.completed_last_command,
                .cmd_id = s.last_command_id,
                .pos = thing.pos,
                .unconfidence = s.unconfidence,
                .dist = dist,
                .range = range,
                .call_range = self.vision_range,
            },
            .goat => |goat| .{
                .arrived = false,
                .cmd_id = best_command_id_so_far,
                .pos = thing.pos,
                .unconfidence = goat.unconfidence,
                .dist = dist,
                .range = range,
                .call_range = goat.call_range,
            },
        };
        if (range < f.call_range) {
            followable_in_view.append(f) catch break;
        }
    }

    // get the best command id we can see, to be used for filtering
    var best_cmd_id: i32 = sheep.last_command_id;
    for (followable_in_view.constSlice()) |f| {
        if (f.cmd_id > best_cmd_id) {
            best_cmd_id = f.cmd_id;
        }
    }
    // best cmd id is >= sheep cmd id.
    // but if sheep is 'arrived', only care about strictly greater
    const best_cmd_id_valid = best_cmd_id > sheep.last_command_id or !sheep.completed_last_command;
    if (best_cmd_id_valid) {
        //self.dbg.boid_desired_vel = V2f.right;
    } else {
        //self.dbg.boid_desired_vel = .{};
    }

    var best_followable: ?Followable = null;
    if (best_cmd_id_valid and followable_in_view.len > 0) blk: { // check best cmd id isn't just me
        // remove lower cmd ids
        var i: usize = 0;
        while (i < followable_in_view.len) {
            const f = followable_in_view.buffer[i];
            if (f.cmd_id != best_cmd_id) {
                _ = followable_in_view.swapRemove(i);
            } else {
                i += 1;
            }
        }
        assert(followable_in_view.len > 0);

        i = 0;
        while (i < followable_in_view.len) {
            const f = followable_in_view.buffer[i];
            if (f.arrived) {
                if (f.range < sheep.command_arrive_range) {
                    sheep.completed_last_command = true;
                    best_followable = null;
                    self.path.len = 0;
                    break :blk;
                } else {
                    _ = followable_in_view.swapRemove(i);
                }
            } else {
                i += 1;
            }
        }

        // get best unconfidence, keeping in mind all followables have valid cmd_id now
        var new_unconfidence: f32 = std.math.inf(f32);
        for (followable_in_view.constSlice()) |f| {
            const u = f.unconfidence + f.dist;
            if (u < new_unconfidence) {
                new_unconfidence = u;
            }
        }

        // update our sheepy's cmd_id and unconfidence
        if (sheep.last_command_id == best_cmd_id) {
            if (new_unconfidence < sheep.unconfidence) {
                sheep.unconfidence = new_unconfidence;
            }
        } else {
            sheep.unconfidence = new_unconfidence;
        }
        sheep.last_command_id = best_cmd_id;

        // now just find the closest followable with a higher confidence
        // or, if we're close enough to an arrived followable, stop
        for (followable_in_view.constSlice()) |f| {
            if (f.unconfidence < sheep.unconfidence - self.coll_radius) {
                if (best_followable == null or best_followable.?.dist > f.dist) {
                    best_followable = f;
                }
            }
        }
    } else {
        // no best cmd_id means we're the leader of all the sheep we can see
        // keep doing what we're doing
    }

    var params = idle_params;

    if (best_followable) |best| {
        sheep.completed_last_command = false;
        // following a followable
        if (debug.show_sheep_ai) {
            self.draw_color = Colorf.orange;
        }
        // near followable, stay still
        if (best.range < sheep.command_arrive_range) {
            // idle boid behavior
            self.path.len = 0;
            // note if we're in range to 'arrive' we would have above
        } else {
            try self.findPath(room, best.pos);
            //if (room.getPlayer()) |p| {
            //    try self.findPath(room, p.kind.player.call_pos);
            //} else {
            //
            //}
            params = follow_params;
        }
    } else if (self.path.len > 0) {
        if (self.path.len > 2) {
            self.path.len = 2;
        }
        if (debug.show_sheep_ai) {
            self.draw_color = Colorf.magenta;
        }
        // TODO this might improve something, but needs to only happen if we've been in this situation for > 1 frame ?
        //sheep.unconfidence = self.path.buffer[self.path.len - 1].dist(self.pos);
        params = follow_params;
    } else {
        sheep.completed_last_command = true;
        if (debug.show_sheep_ai) {
            self.draw_color = Colorf.purple;
        }
    }

    const next_pos = self.followPathGetNextPoint(self.coll_radius + params.sep_thing_range + 20);
    follow_vec = next_pos.sub(self.pos).normalizedOrZero();

    try self.steerSum(room, things_in_view.slice(), follow_vec, params);
}

pub fn idle(self: *Thing, room: *Room) Error!void {
    const sheep = &self.kind.sheep;
    const sheep_proto = try protoype();

    var params: Thing.BoidParams = .{
        .s_sep = 1.1,
    };

    if (room.getConstPlayer()) |p| {
        const v = p.pos.sub(self.pos);
        const dist = v.length();
        const range = @max(dist - self.coll_radius - p.coll_radius, 0);
        if (range < sheep.push_range) {
            //const inv = @max(sheep.push_range - range, 0);
            sheep.push_vec = v.normalizedOrZero().neg(); //.scale(inv);
            sheep.push_ticks_left = sheep.total_push_ticks;
        }
    }

    var sheep_in_view: std.BoundedArray(*Thing, 16) = .{};
    for (&room.things.items) |*thing| {
        if (!thing.isActive()) continue;
        if (thing.id.eql(self.id)) continue;
        if (!utl.unionTagEql(self.kind, thing.kind)) continue;

        const dist = thing.pos.dist(self.pos);
        const range = @max(dist - self.coll_radius - thing.coll_radius, 0);

        if (range < self.vision_range) {
            sheep_in_view.append(thing) catch break;
        }
    }

    self.accel_params = sheep_proto.accel_params;
    if (sheep.push_ticks_left > 0) {
        params.s_follow = 1;
        params.s_cohere = 1;
        sheep.push_ticks_left -= 1;
    } else {
        var neighbor_pushed = false;
        var highest_align: f32 = 0;
        for (sheep_in_view.slice()) |thing| {
            const t = thing.kind.sheep.push_ticks_left;
            if (t > 0) {
                neighbor_pushed = true;
            }
            const dist = thing.pos.dist(self.pos);
            const range = @max(dist - self.coll_radius - thing.coll_radius, 0);
            if (range <= sheep.follow_range) {
                const n: f32 = range / sheep.follow_range; // falloff based on dist
                const d_align = @max(thing.kind.sheep.s_align - n * 0.8, 0);
                if (d_align > highest_align) {
                    highest_align = d_align;
                }
            }
        }
        if (neighbor_pushed) {
            highest_align = 0.8;
        }
        if (highest_align > 0) {
            params.s_cohere = highest_align;
            params.s_align = highest_align;
            self.accel_params.accel = params.s_align * sheep_proto.accel_params.accel;
            self.accel_params.max_speed = params.s_align * sheep_proto.accel_params.max_speed;
        }

        sheep.s_align = params.s_align;
    }

    try self.steerSum(room, sheep_in_view.slice(), sheep.push_vec, params);
}

pub fn update(_: *Sheep, self: *Thing, room: *Room) Error!void {
    assert(self.spawn_state == .spawned);
    try idle(self, room);
    //try followLastCmdId(self, room);
}
