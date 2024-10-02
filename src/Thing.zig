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

const player = @import("Player.zig");
const enemies = @import("enemies.zig");
const Spell = @import("Spell.zig");

pub const Kind = enum {
    player,
    troll,
    projectile,
};

pub const Pool = pool.BoundedPool(Thing, 32);
// TODO wrap
pub const Id = pool.Id;

pub const CollLayer = enum {
    creature,
    tile,
};
pub const CollMask = std.EnumSet(CollLayer);

id: Id = undefined,
alloc_state: pool.AllocState = undefined,
spawn_state: enum {
    instance, // not in any pool
    spawning, // in pool. yet to be spawned
    spawned, // active in the world
    freeable, // in pool. yet to be freed
} = .instance,
//
kind: Kind = undefined,
pos: V2f = .{},
vel: V2f = .{},
dir: V2f = V2f.right,
dirv: f32 = 0,
coll_radius: f32 = 0,
coll_mask: CollMask = .{},
coll_layer: CollMask = .{},
vision_range: f32 = 0,
accel_params: AccelParams = .{},
dir_accel_params: DirAccelParams = .{},
dbg: struct {
    last_coll: ThingCollision = .{},
    coords_searched: std.ArrayList(V2i) = undefined,
} = .{},
controller: union(enum) {
    none: void,
    player: player.InputController,
    enemy: enemies.AIController,
    spell: Spell.Controller,
} = .none,
renderer: union(enum) {
    none: void,
    default: DebugCircleRenderer,
} = .{ .default = .{} },
path: std.BoundedArray(V2f, 32) = .{},

pub const DebugCircleRenderer = struct {
    pub const DebugAnimator = struct {
        pub const DebugAnimPlayParams = struct {
            from: ?i32 = null, // null == continue from last frame, or 0 if new anim
            loop: bool = false,
        };

        pub const DebugAnimKind = enum {
            none,
            attack,
        };
        pub const DebugAnim = struct {
            num_frames: i32 = 1,
        };
        curr: DebugAnimKind = .none,
        tick: i64 = 0,
        anims: std.EnumMap(DebugAnimKind, DebugAnim) = std.EnumMap(DebugAnimKind, DebugAnim).init(.{ .none = .{} }),

        pub fn play(self: *DebugAnimator, anim_kind: DebugAnimKind, params: DebugAnimPlayParams) bool {
            const anim = if (self.anims.get(anim_kind)) |a| a else {
                std.debug.print("WARNING: tried to play non-existent debug anim: {any}\n", .{anim_kind});
                return false;
            };

            if (params.from) |f| {
                self.tick = f;
            } else if (anim_kind != self.curr) {
                self.tick = 0;
            }
            self.curr = anim_kind;
            // stopped anim
            if (self.tick >= anim.num_frames) {
                return true;
            }

            self.tick += 1;
            if (self.tick >= anim.num_frames) {
                if (params.loop) {
                    self.tick = 0;
                }
                return true;
            }
            return false;
        }
    };

    draw_radius: f32 = 20,
    draw_color: Colorf = Colorf.red,
    animator: DebugAnimator = .{},

    pub fn render(self: *const Thing, room: *const Room) Error!void {
        assert(self.spawn_state == .spawned);
        const plat = getPlat();
        const renderer = &self.renderer.default;

        plat.circlef(self.pos, renderer.draw_radius, .{ .fill_color = renderer.draw_color });
        plat.arrowf(self.pos, self.pos.add(self.dir.scale(renderer.draw_radius)), 5, Colorf.black);

        const animator = renderer.animator;
        switch (animator.curr) {
            .none => {},
            .attack => {
                plat.circlef(self.pos.add(self.dir.scale(renderer.draw_radius)), 5, .{ .fill_color = Colorf.red });
            },
        }

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
};

pub const DefaultController = struct {
    pub fn update(_: *Thing, _: *Room) Error!void {}
};

pub fn update(self: *Thing, room: *Room) Error!void {
    switch (self.controller) {
        inline else => |c| {
            const C = @TypeOf(c);
            if (std.meta.hasMethod(C, "update")) {
                try C.update(self, room);
            }
        },
    }
}

pub fn render(self: *const Thing, room: *const Room) Error!void {
    switch (self.renderer) {
        inline else => |r| {
            const R = @TypeOf(r);
            if (std.meta.hasMethod(R, "render")) {
                try R.render(self, room);
            }
        },
    }
}

pub fn deferFree(self: *Thing, room: *Room) void {
    assert(self.spawn_state == .spawned);
    self.spawn_state = .freeable;
    room.free_queue.append(self.id) catch @panic("out of free_queue space!");
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

pub fn getNextCollisionWithCreatures(self: *Thing, room: *Room) ThingCollision {
    var coll: ThingCollision = .{ .pos = self.pos };

    for (&room.things.items) |*thing| {
        if (!thing.isActive()) continue;
        if (thing.id.eql(self.id)) continue;
        if (!thing.coll_layer.contains(.creature)) continue;

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

        if (self.coll_mask.contains(.creature)) {
            coll = getNextCollisionWithCreatures(self, room);
        }
        if (!coll.collided and self.coll_mask.contains(.tile)) {
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
    if (self.path.len == 0) {
        self.path.append(self.pos) catch unreachable;
        self.path.append(goal) catch unreachable;
    }
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

pub fn debugDrawPath(self: *const Thing, room: *const Room) Error!void {
    const plat = getPlat();
    const inv_zoom = 1 / room.camera.zoom;
    const line_thickness = inv_zoom;
    for (0..self.path.len - 1) |i| {
        plat.arrowf(self.path.buffer[i], self.path.buffer[i + 1], line_thickness, Colorf.green);
        //p.linef(self.path.buffer[i], self.path.buffer[i + 1], line_thickness, Colorf.green);
    }
}
