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

const Thing = @This();
const App = @import("App.zig");
const getPlat = App.getPlat;
const Room = @import("Room.zig");
const TileMap = @import("TileMap.zig");
const data = @import("data.zig");
const pool = @import("pool.zig");

pub const Kind = enum {
    player,
    sheep,
    goat,
};

pub const KindData = union(Kind) {
    player: @import("Player.zig"),
    sheep: @import("Sheep.zig"),
    goat: @import("Goat.zig"),

    pub fn render(_: *const KindData, self: *const Thing, room: *const Room) Error!void {
        try self.defaultRender(room);
    }
    pub fn update(_: *KindData, self: *Thing, room: *Room) Error!void {
        try self.defaultUpdate(room);
    }
};

pub const Pool = pool.BoundedPool(Thing, 32);

id: pool.Id = undefined,
alloc_state: pool.AllocState = undefined,
spawn_state: enum {
    instance, // not in any pool
    spawning, // in pool. yet to be spawned
    spawned, // active in the world
    freeable, // in pool. yet to be freed
} = .instance,
//
kind: KindData,
pos: V2f = .{},
vel: V2f = .{},
dir: V2f = V2f.right,
dirv: f32 = 0,
coll_radius: f32 = 0,
draw_color: Colorf = Colorf.red,
vision_range: f32 = 0,
accel_params: AccelParams = .{},
dir_accel_params: DirAccelParams = .{},
dbg: struct {
    last_coll: ThingCollision = .{},
    coords_searched: std.ArrayList(V2i) = undefined,
    boid_sep: V2f = .{},
    boid_cohere: V2f = .{},
    boid_align: V2f = .{},
    boid_avoid: V2f = .{},
    boid_follow: V2f = .{},
    boid_wall_sep: V2f = .{},
    boid_desired_vel: V2f = .{},
} = .{},
path: std.BoundedArray(V2f, 32) = .{},

pub fn render(self: *const Thing, room: *const Room) Error!void {
    if (self.spawn_state != .spawned) return;
    switch (self.kind) {
        // inline else is required, otherwise KindData.render will be used
        inline else => |e| try e.render(self, room),
    }
}

pub fn update(self: *Thing, room: *Room) Error!void {
    if (self.spawn_state != .spawned) return;
    switch (self.kind) {
        // inline else is required, otherwise KindData.update will be used
        inline else => |*e| try e.update(self, room),
    }
}

pub fn deferFree(self: *Thing) Error!void {
    assert(self.spawn_state == .spawned);
    self.spawn_state = .freeable;
}

pub fn init(self: *Thing) Error!void {
    self.dbg.coords_searched = @TypeOf(self.dbg.coords_searched).init(getPlat().heap);
}

pub fn deinit(self: *Thing) void {
    self.dbg.coords_searched.deinit();
}

// copy retaining original id, alloc state and spawn_state
pub fn copyTo(self: *const Thing, other: *Thing) Error!void {
    const id = other.id;
    const alloc_state = other.alloc_state;
    const spawn_state = other.spawn_state;
    other.* = self.*;
    // TODO clone allocated stuff
    other.dbg.coords_searched = try self.dbg.coords_searched.clone();
    other.id = id;
    other.alloc_state = alloc_state;
    other.spawn_state = spawn_state;
}

pub fn defaultRender(self: *const Thing, room: *const Room) Error!void {
    assert(self.spawn_state == .spawned);
    const plat = getPlat();
    //if (self.kind == .sheep) {
    //    std.debug.print("i'm rendering maaam! {s} at {d:0.2}, {d:0.2}\n", .{ self.name, self.pos.x, self.pos.y });
    //}
    plat.circlef(self.pos, self.coll_radius, .{ .fill_color = self.draw_color });
    plat.arrowf(self.pos, self.pos.add(self.dir.scale(self.coll_radius)), 5, Colorf.black);
    if (debug.show_thing_collisions) {
        if (self.dbg.last_coll.collided) {
            const coll = self.dbg.last_coll;
            plat.arrowf(coll.pos, coll.pos.add(coll.normal.scale(self.coll_radius * 0.75)), 3, Colorf.red);
        }
    }
    if (debug.show_thing_coords_searched) {
        if (self.path.len > 0) {
            for (self.dbg.coords_searched.items) |coord| {
                plat.circlef(TileMap.tileCoordToCenterPos(coord), 10, .{ .outline_color = Colorf.white, .fill_color = null });
            }
        }
    }
    if (debug.show_thing_paths) {
        if (self.path.len > 0) {
            try self.debugDrawPath(room);
        }
    }
}

fn defaultUpdate(self: *Thing, room: *Room) Error!void {
    assert(self.spawn_state == .spawned);
    try self.moveAndCollide(room);
}

pub const ThingCollision = struct {
    collided: bool = false,
    pos: V2f = .{},
    normal: V2f = V2f.right,
    pen_dist: f32 = 0,
};

pub fn getCircleCircleCollision(pos_a: V2f, radius_a: f32, pos_b: V2f, radius_b: f32) ThingCollision {
    var coll: ThingCollision = .{ .pos = pos_a };

    const b_to_a = pos_a.sub(pos_b);
    const dist = b_to_a.length();
    if (dist < radius_a + radius_b) {
        // default to right, is ok fallback
        if (dist > 0.001) {
            coll.normal = b_to_a.scale(1 / dist);
        }
        coll.pen_dist = @max(radius_a + radius_b - dist, 0);
        coll.pos = pos_b.add(coll.normal.scale(radius_b));
        coll.collided = true;
    }

    return coll;
}

pub fn isActive(self: *const Thing) bool {
    return self.alloc_state == .allocated and self.spawn_state == .spawned;
}

pub fn getNextCollisionWithThings(self: *Thing, room: *Room) ThingCollision {
    var coll: ThingCollision = .{ .pos = self.pos };

    for (&room.things.items) |*thing| {
        if (!thing.isActive()) continue;
        if (thing.id.eql(self.id)) continue;
        if (thing.coll_radius == 0) continue;

        coll = getCircleCircleCollision(self.pos, self.coll_radius, thing.pos, thing.coll_radius);
        if (coll.collided) break;
    }
    return coll;
}

pub fn getCircleCollisionWithTiles(pos: V2f, radius: f32, room: *const Room) ThingCollision {
    var coll: ThingCollision = .{ .pos = pos };

    for (room.tilemap.tiles.values()) |tile| outer_blk: {
        if (tile.passable) continue;

        const passable_neighbors = room.tilemap.getTileNeighborsPassable(tile.coord);
        const all_corners_cw = TileMap.tileTopLeftToCornersCW(TileMap.tileCoordToPos(tile.coord));
        const all_edges_cw: [4][2]V2f = blk: {
            var ret: [4][2]V2f = undefined;
            for (0..4) |i| {
                ret[i] = .{ all_corners_cw[i], all_corners_cw[@mod(i + 1, 4)] };
            }
            break :blk ret;
        };
        const corners_cw = blk: {
            const corner_dirs: [4][2]TileMap.NeighborDir = .{ .{ .N, .W }, .{ .N, .E }, .{ .S, .E }, .{ .S, .W } };
            var ret = std.BoundedArray(V2f, 4){};
            for (corner_dirs, 0..) |dirs, i| {
                if (passable_neighbors.get(dirs[0]) and passable_neighbors.get(dirs[1])) {
                    ret.append(all_corners_cw[i]) catch unreachable;
                }
            }
            break :blk ret;
        };
        const edges_cw = blk: {
            var ret = std.BoundedArray([2]V2f, 4){};
            for (TileMap.neighbor_dirs, 0..) |dir, i| {
                if (passable_neighbors.get(dir)) {
                    ret.append(all_edges_cw[i]) catch unreachable;
                }
            }
            break :blk ret;
        };
        const center = TileMap.tileCoordToCenterPos(tile.coord);
        const rect = TileMap.tileCoordToRect(tile.coord);

        // inside! arg get ouuuut
        if (geom.pointIsInRectf(pos, rect)) {
            const center_to_pos = pos.sub(center);
            const n = center_to_pos.normalizedOrZero();

            // if exactly at the center, we'll always go right, but meh, is ok fallback
            if (!n.isZero()) {
                var is_passable_dir: bool = false;
                var max_dot: f32 = -std.math.inf(f32);
                var max_dir: V2f = .{};

                for (TileMap.neighbor_dirs) |dir| {
                    if (passable_neighbors.get(dir)) {
                        const dir_v = TileMap.neighbor_dirs_coords.get(dir).toV2f();
                        const dot = dir_v.dot(center_to_pos);
                        is_passable_dir = true;
                        if (dot > max_dot) {
                            max_dot = dot;
                            max_dir = dir_v;
                        }
                    }
                }
                if (is_passable_dir) {
                    coll.normal = max_dir;
                }
            }
            coll.pen_dist = radius;
            coll.pos = pos;
            coll.collided = true;
            break;
        }
        // check edges before corners, to rule out areas in corner radius that are also on edges
        for (edges_cw.constSlice()) |edge| {
            const edge_v = edge[1].sub(edge[0]);
            const pos_v = pos.sub(edge[0]);
            const edge_v_len = edge_v.length();
            if (edge_v_len < 0.001) continue;
            const edge_v_n = edge_v.scale(1 / edge_v_len);
            const dot = edge_v_n.dot(pos_v);
            // outside line seg
            if (dot < 0 or dot > edge_v_len) {
                continue;
            }
            const intersect_pos = edge[0].add(edge_v_n.scale(dot));
            const pos_to_intersect = intersect_pos.sub(pos);
            const dist = pos_to_intersect.length();
            if (dist < radius) {
                coll.pen_dist = @max(radius - dist, 0);
                coll.normal = v2f(edge_v.y, -edge_v.x).normalized();
                coll.pos = intersect_pos;
                coll.collided = true;
                break :outer_blk;
            }
        }
        // finally corners; only the parts which are beyond the edge
        // TODO optimization - discover the corner in edge detection part - using dot product used to rule out line seg
        for (corners_cw.constSlice()) |corner_pos| {
            const pos_to_corner = corner_pos.sub(pos);
            const dist = pos_to_corner.length();
            if (dist < radius) {
                if (dist < 0.001) {
                    const center_to_pos = pos.sub(center).normalizedOrZero();
                    if (!center_to_pos.isZero()) {
                        coll.normal = center_to_pos;
                    }
                } else {
                    coll.normal = pos_to_corner.scale(-1 / dist);
                }
                coll.pen_dist = @max(radius - dist, 0);
                coll.pos = corner_pos;
                coll.collided = true;
                break :outer_blk;
            }
        }
    }

    return coll;
}

pub fn followPathGetNextPoint(self: *Thing, dist: f32) V2f {
    var ret: V2f = self.pos;

    if (self.path.len > 0) {
        assert(self.path.len >= 2);
        const curr_coord = TileMap.posToTileCoord(self.pos);
        const next_pos = self.path.buffer[1];
        const next_coord = TileMap.posToTileCoord(next_pos);
        const curr_to_next = next_pos.sub(self.pos);
        var remove_next = false;

        ret = next_pos;

        // for last square, only care about radius. for others, enter the square
        if ((self.path.len == 2 and curr_to_next.length() <= dist) or (self.path.len > 2 and curr_coord.eql(next_coord))) {
            remove_next = true;
        }

        if (remove_next) {
            _ = self.path.orderedRemove(0);
            if (self.path.len == 1) {
                _ = self.path.orderedRemove(0);
                ret = self.pos;
            }
        }
    }

    return ret;
}

pub fn moveAndCollide(self: *Thing, room: *Room) Error!void {
    var num_iters: i32 = 0;

    self.dbg.last_coll.collided = false;
    self.pos = self.pos.add(self.vel);

    while (num_iters < 5) {
        var coll: ThingCollision = .{ .pos = self.pos };

        coll = getNextCollisionWithThings(self, room);
        if (!coll.collided) {
            coll = getCircleCollisionWithTiles(self.pos, self.coll_radius, room);
        }

        if (!coll.collided) break;

        self.dbg.last_coll = coll;

        // push out
        if (coll.pen_dist > 0) {
            self.pos = coll.pos.add(coll.normal.scale(self.coll_radius + 1));
        }
        // remove -normal component from vel, isn't necessary with current implementation
        //const d = coll_normal.dot(self.vel);
        //self.vel = self.vel.sub(coll_normal.scale(d + 0.1));

        num_iters += 1;
    }
}

pub fn findPath(self: *Thing, room: *Room, goal: V2f) Error!void {
    self.path = try room.tilemap.findPathThetaStar(getPlat().heap, self.pos, goal, self.coll_radius, &self.dbg.coords_searched);
}

pub const DirAccelParams = struct {
    ang_accel: f32 = utl.pi * 0.002,
    max_ang_vel: f32 = utl.pi * 0.03,
};

pub fn updateDir(self: *Thing, desired_dir: V2f, params: DirAccelParams) void {
    const n = desired_dir.normalizedOrZero();
    if (!n.isZero()) {
        const a_dir: f32 = if (self.dir.cross(n) > 0) 1 else -1;
        const cos = self.dir.dot(n);
        const ang = std.math.acos(cos);

        self.dirv += a_dir * params.ang_accel;
        const abs_dirv = @abs(self.dirv);
        if (@abs(ang) <= abs_dirv * 2) {
            self.dir = n;
            self.dirv = 0;
        } else {
            if (abs_dirv > params.max_ang_vel) self.dirv = a_dir * params.max_ang_vel;
            self.dir = self.dir.rotRadians(self.dirv);
        }
    }
}

pub const AccelParams = struct {
    accel: f32 = 0.05,
    friction: f32 = 0.02,
    max_speed: f32 = 0.8,
};

pub fn updateVel(self: *Thing, accel_dir: V2f, params: AccelParams) void {
    const speed_limit: f32 = 20;
    const min_speed_threshold = 0.001;

    const accel = accel_dir.scale(params.accel);
    const len = self.vel.length();
    var new_vel = self.vel;
    var len_after_accel: f32 = len;

    // max speed isn't a hard limit - we just can't accelerate past it
    // this allows being over max speed if it changed over time, or something else accelerated us
    if (len < params.max_speed) {
        new_vel = self.vel.add(accel);
        len_after_accel = new_vel.length();
        if (len_after_accel > params.max_speed) {
            len_after_accel = params.max_speed;
            new_vel = new_vel.clampLength(params.max_speed);
        }
    }

    if (len_after_accel - params.friction > min_speed_threshold) {
        var n = new_vel.scale(1 / len_after_accel);
        new_vel = new_vel.sub(n.scale(params.friction));
        // speed limit is a hard limit. don't go past it
        new_vel = new_vel.clampLength(speed_limit);
    } else {
        new_vel = .{};
    }

    self.vel = new_vel;
}

pub fn getBoidThingAvoidance(self: *Thing, others_in_vision_range: []*Thing) V2f {
    var ret: V2f = .{};

    const vel_dir = self.vel.normalizedOrZero();
    if (vel_dir.isZero()) return ret;

    const projected_pos = self.pos.add(vel_dir.scale(self.coll_radius));
    //var coll = self.getCircleCollisionWithTiles(projected_pos, self.coll_radius, room: *Room)
    var best_coll: ThingCollision = .{};
    var best_dist: f32 = std.math.inf(f32);

    for (others_in_vision_range) |other| {
        const coll = getCircleCircleCollision(projected_pos, self.coll_radius, other.pos, other.coll_radius);
        if (!coll.collided) continue;
        if (!best_coll.collided) {
            best_coll = coll;
        }
        const dist = coll.pos.dist(projected_pos);
        if (dist < best_dist) {
            best_dist = dist;
            best_coll = coll;
        }
    }

    if (best_coll.collided) {
        const cross = vel_dir.cross(best_coll.normal);
        const perp = if (cross < 0) best_coll.normal.rot90CW() else best_coll.normal.rot90CCW();
        const avoid_dir = if (cross < 0) vel_dir.rot90CCW() else vel_dir.rot90CW();
        // how much are we facing the thing
        const f = vel_dir.dot(perp);
        ret = avoid_dir.scale(f);
    }

    return ret;
}

pub fn getBoidThingSeparation(self: *Thing, others_in_vision_range: []*Thing, sep_range: f32) V2f {
    var ret: V2f = .{};
    var num: f32 = 0;

    for (others_in_vision_range) |other| {
        const vec = other.pos.sub(self.pos);
        const dist = vec.length();
        const range = @max(dist - self.coll_radius - other.coll_radius, 0);

        if (range < sep_range) {
            const inv = @max(sep_range - range, 0);
            const v_inv = if (dist > 0.001) vec.scale(inv / dist) else V2f.right;
            ret = ret.sub(v_inv);
            num += 1;
        }
    }

    if (num > 0) {
        ret = ret.scale(1 / num);
        ret = ret.clampLength(sep_range);
        ret = ret.remapLengthTo0_1(0, sep_range);
    }

    return ret;
}

pub fn getBoidCohesion(self: *Thing, others_in_vision_range: []*Thing) V2f {
    var num: f32 = 0;
    var ret: V2f = .{};

    for (others_in_vision_range) |other| {
        if (utl.unionTagEql(self.kind, other.kind)) {
            // TODO weight based on range, somehow?
            // cant just weight the pos, that doesn't make sense
            // record a separate number per 'other' (0-1), to scale with when averaging? running average? ???
            ret = ret.add(other.pos);
            num += 1;
        }
    }

    if (num > 0) {
        ret = ret.scale(1 / num);
        ret = ret.sub(self.pos);
        ret = ret.clampLength(self.vision_range);
        ret = ret.remapLengthTo0_1(0, self.vision_range);
    }

    return ret;
}

pub fn getBoidAlignment(self: *Thing, others_in_vision_range: []*Thing) V2f {
    var num: f32 = 0;
    var ret: V2f = .{};

    for (others_in_vision_range) |other| {
        if (utl.unionTagEql(self.kind, other.kind)) {
            const dist = other.pos.dist(self.pos);
            const range = @max(dist - self.coll_radius - other.coll_radius, 0);
            // only care about velocity direction, scale based on how far the other is
            const inv = @max(self.vision_range - range, 0);
            const v = other.vel.normalizedOrZero().scale(inv);
            ret = ret.add(v);
            num += 1;
        }
    }

    if (num > 0) {
        ret = ret.scale(1 / num);
        ret = ret.clampLength(self.vision_range);
        ret = ret.remapLengthTo0_1(0, self.vision_range);
    }

    return ret;
}

pub fn getSteeringWallSep(self: *Thing, room: *const Room, sep_range: f32) V2f {
    var wall_sep_vec: V2f = .{};
    const tile_coll = Thing.getCircleCollisionWithTiles(self.pos, self.coll_radius + sep_range, room);
    if (tile_coll.collided) {
        const dist = tile_coll.pos.sub(self.pos).length();
        const max_dist = self.coll_radius + sep_range;
        const inv = @max(max_dist - dist, 0);
        wall_sep_vec = wall_sep_vec.add(tile_coll.normal.scale(inv));
    }
    {
        const room_botright = room.tilemap.dims.scale(0.5);
        const room_topleft = room_botright.neg();
        const border_soft: f32 = 50;
        const border_offset_soft = V2f.splat(border_soft + self.coll_radius);
        const border_topleft = room_topleft.add(border_offset_soft);
        const border_botright = room_botright.sub(border_offset_soft);

        var outside_topleft = border_topleft.sub(self.pos);
        outside_topleft.x = utl.clampf(outside_topleft.x, 0, border_soft);
        outside_topleft.y = utl.clampf(outside_topleft.y, 0, border_soft);
        wall_sep_vec = wall_sep_vec.add(outside_topleft);

        var outside_botright = self.pos.sub(border_botright);
        outside_botright.x = utl.clampf(outside_botright.x, 0, border_soft);
        outside_botright.y = utl.clampf(outside_botright.y, 0, border_soft);
        wall_sep_vec = wall_sep_vec.sub(outside_botright);
    }
    wall_sep_vec = wall_sep_vec.normalizedOrZero();

    return wall_sep_vec;
}

pub const BoidParams = struct {
    s_cohere: f32 = 0,
    s_avoid: f32 = 0,
    s_sep: f32 = 0,
    s_align: f32 = 0,
    s_follow: f32 = 0,
    sep_thing_range: f32 = 10,
    sep_wall_range: f32 = 8,
};

pub fn steerSum(self: *Thing, room: *Room, others: []*Thing, follow_vec: V2f, params: BoidParams) Error!void {
    const v_cohere = self.getBoidCohesion(others);
    const v_sep = self.getBoidThingSeparation(others, params.sep_thing_range);
    const v_align = self.getBoidAlignment(others);
    const v_avoid = self.getBoidThingAvoidance(others);
    const v_follow = follow_vec;
    const v_wall = self.getSteeringWallSep(room, params.sep_wall_range);

    const weights = [_]f32{ params.s_cohere, params.s_sep, params.s_align, params.s_avoid, params.s_follow, params.s_sep };
    const vecs = [weights.len]V2f{ v_cohere, v_sep, v_align, v_avoid, v_follow, v_wall };
    const dbg_vecs = [weights.len]?*V2f{ &self.dbg.boid_cohere, &self.dbg.boid_sep, &self.dbg.boid_align, &self.dbg.boid_avoid, &self.dbg.boid_follow, &self.dbg.boid_wall_sep };
    var summed_vecs: V2f = .{};
    for (vecs, 0..) |v, i| {
        const scaled = v.scale(weights[i]);
        if (dbg_vecs[i]) |ptr| {
            ptr.* = scaled;
        }
        //std.debug.print("[{}]: {d:0.2} {d:0.2}\n", .{ i, v.x, v.y });
        summed_vecs = summed_vecs.add(scaled);
    }
    const desired_dir = summed_vecs.normalizedOrZero();

    self.dbg.boid_desired_vel = desired_dir;
    //std.debug.print("{d:0.2} {d:0.2}\n", .{ summed_accels.x, summed_accels.y });

    self.updateVel(desired_dir, self.accel_params);
    self.updateDir(desired_dir, self.dir_accel_params);

    try self.moveAndCollide(room);
}

pub fn steerAvg(self: *Thing, room: *Room, others: []*Thing, follow_vec: V2f, params: BoidParams) Error!void {
    const wall_sep_vec: V2f = self.getSteeringWallSep(room, params.sep_wall_range);
    const v_cohere = self.getBoidCohesion(others);
    self.dbg.boid_cohere = v_cohere.scale(params.s_cohere);
    const v_sep = self.getBoidThingSeparation(others, params.sep_thing_range);
    self.dbg.boid_sep = v_sep.scale(params.s_sep);
    const v_align = self.getBoidAlignment(others);
    self.dbg.boid_align = v_align.scale(params.s_align);
    const v_avoid = self.getBoidThingAvoidance(others);
    self.dbg.boid_avoid = v_avoid.scale(params.s_avoid);
    const v_follow = follow_vec;
    self.dbg.boid_follow = v_follow.scale(params.s_follow);
    const v_wall = wall_sep_vec;
    const weights = [_]f32{ params.s_cohere, params.s_sep, params.s_align, params.s_avoid, params.s_follow, params.s_sep };
    const vecs = [weights.len]V2f{ v_cohere, v_sep, v_align, v_avoid, v_follow, v_wall };
    var summed_vecs: V2f = .{};
    //var summed_lens: f32 = 0;
    var summed_weights: f32 = 0;
    for (vecs, 0..) |v, i| {
        summed_vecs = summed_vecs.add(v.scale(weights[i]));
        //summed_lens += v.length();
        summed_weights += weights[i];
    }
    //std.debug.print("{d:0.2} {d:0.2} {d:0.2} {d:0.2}\n", .{ v_cohere.lengthSquared(), v_avoid.lengthSquared(), v_align.lengthSquared(), v_follow.lengthSquared() });
    const avg_vec = summed_vecs.scale(1.0 / summed_weights);
    const desired_vel_norm = avg_vec.clampLength(1);
    //const avg_len = summed_lens / vecs.len;
    //const avg = avg_vec_normalized.scale(avg_len);

    self.dbg.boid_desired_vel = desired_vel_norm;

    std.debug.print("{d:0.2} {d:0.2}\n", .{ desired_vel_norm.x, desired_vel_norm.y });

    var accel_params: Thing.AccelParams = .{};
    const dv = desired_vel_norm.scale(accel_params.max_speed).sub(self.vel);
    const len = dv.length();
    accel_params.accel = @min(accel_params.accel, len);
    const accel_dir = dv.normalizedOrZero();
    self.updateVel(accel_dir, accel_params);
    self.updateDir(desired_vel_norm.normalizedOrZero(), .{});

    try self.moveAndCollide(room);
}

pub fn debugDrawPath(self: *const Thing, room: *const Room) Error!void {
    const plat = getPlat();
    const inv_zoom = 1 / room.camera.zoom;
    const line_thickness = inv_zoom;
    for (0..self.path.len - 1) |i| {
        plat.arrowf(self.path.buffer[i], self.path.buffer[i + 1], line_thickness, Colorf.green);
        //p.linef(self.path.buffer[i], self.path.buffer[i + 1], line_thickness, Colorf.green);
    }
}
