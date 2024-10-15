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
const TileMap = @import("TileMap.zig");
const Thing = @import("Thing.zig");
const Room = @import("Room.zig");
const Collision = @This();

pub const Layer = enum {
    creature,
    tile,
};
pub const Mask = std.EnumSet(Layer);

kind: union(enum) {
    none,
    tile: V2i,
    thing: Thing.Id,
} = .none,
pos: V2f = .{},
normal: V2f = V2f.right,
pen_dist: f32 = 0,

pub fn getPointCircleCollision(point: V2f, circle_pos: V2f, radius: f32) ?Collision {
    const point_to_circle = circle_pos.sub(point);
    const dist = point_to_circle.length();
    if (dist < radius) {
        var coll = Collision{};
        if (dist < 0.001) {
            const n = point_to_circle.scale(-1 / dist);
            coll.normal = n;
        }
        coll.pen_dist = radius - dist;
        coll.pos = circle_pos.add(coll.normal);
        return coll;
    }
    return null;
}

pub fn getRayCircleCollision(ray_pos: V2f, ray_v: V2f, circle_pos: V2f, radius: f32) ?Collision {
    assert(radius > 0.001);
    const ray_to_circle = circle_pos.sub(ray_pos);
    const ray_len = ray_v.length();
    const ray_v_n = if (ray_len > 0.001) ray_v.scale(1 / ray_len) else {
        // ray is really a point
        return getPointCircleCollision(ray_pos, circle_pos, radius);
    };
    const dot = ray_v_n.dot(ray_to_circle);
    //circle before or after line seg
    if (dot <= 0) {
        return getPointCircleCollision(ray_pos, circle_pos, radius);
    } else if (dot >= ray_len) {
        return getPointCircleCollision(ray_pos.add(ray_v), circle_pos, radius);
    }
    const closest_point = ray_pos.add(ray_v_n.scale(dot));
    const closest_point_dist = closest_point.sub(circle_pos).length();
    if (closest_point_dist <= radius) {
        var coll = Collision{};
        const seg_dist = @sqrt(radius * radius - closest_point_dist * closest_point_dist);
        coll.pos = closest_point.sub(ray_v_n.scale(seg_dist));
        coll.pen_dist = seg_dist;
        const circle_to_coll = coll.pos.sub(circle_pos);
        coll.normal = circle_to_coll.scale(1 / radius);
        return coll;
    }
    return null;
}

pub fn getNextSweptCircleCollision(ray_pos: V2f, ray_v: V2f, radius: f32, mask: Mask, ignore_ids: []const Thing.Id, room: *const Room) ?Collision {
    const creature_coll: ?Collision = if (mask.contains(.creature)) getNextSweptCircleCollisionWithThings(ray_pos, ray_v, radius, mask, ignore_ids, room) else null;
    const tile_coll: ?Collision = if (mask.contains(.tile)) getNextSweptCircleCollisionWithTiles(ray_pos, ray_v, radius, &room.tilemap) else null;
    // take the min dist
    if (creature_coll) |ccoll| {
        if (tile_coll) |tcoll| {
            if (ccoll.pos.dist(ray_pos) < tcoll.pos.dist(ray_pos)) {
                return ccoll;
            }
            return tcoll;
        }
        return ccoll; // no tile_coll
    }
    return tile_coll; // can be null
}

pub fn getNextSweptCircleCollisionWithThings(ray_pos: V2f, ray_v: V2f, radius: f32, mask: Mask, ignore_ids: []const Thing.Id, room: *const Room) ?Collision {
    var best_coll: ?Collision = null;
    var best_dist: f32 = std.math.inf(f32);

    thing_loop: for (&room.things.items) |*thing| {
        if (!thing.isActive()) continue;
        for (ignore_ids) |id| {
            if (thing.id.eql(id)) continue :thing_loop;
        }
        if (mask.intersectWith(thing.coll_layer).count() == 0) continue;

        if (getRayCircleCollision(ray_pos, ray_v, thing.pos, radius + thing.coll_radius)) |r_coll| {
            var coll = r_coll;
            coll.pos = r_coll.pos.sub(coll.normal.scale(radius));
            const dist = ray_pos.dist(coll.pos);
            if (best_coll == null or dist < best_dist) {
                best_coll = coll;
                best_dist = dist;
            }
        }
    }
    return best_coll;
}

pub fn getCircleCircleCollision(pos_a: V2f, radius_a: f32, pos_b: V2f, radius_b: f32) ?Collision {
    var coll: ?Collision = null;
    const b_to_a = pos_a.sub(pos_b);
    const dist = b_to_a.length();
    if (dist < radius_a + radius_b) {
        const n = if (dist > 0.001) b_to_a.scale(1 / dist) else V2f.right;
        coll = Collision{
            .normal = n,
            .pen_dist = @max(radius_a + radius_b - dist, 0),
            .pos = pos_b.add(n.scale(radius_b)),
        };
    }
    return coll;
}

pub fn getNextCircleCollisionWithThings(pos: V2f, radius: f32, mask: Mask, ignore_ids: []const Thing.Id, room: *const Room) ?Collision {
    var best_coll: ?Collision = null;
    var best_dist: f32 = std.math.inf(f32);

    thing_loop: for (&room.things.items) |*thing| {
        if (!thing.isActive()) continue;
        for (ignore_ids) |id| {
            if (thing.id.eql(id)) continue :thing_loop;
        }
        if (mask.intersectWith(thing.coll_layer).count() == 0) continue;

        if (getCircleCircleCollision(pos, radius, thing.pos, thing.coll_radius)) |coll| {
            const dist = pos.dist(coll.pos);
            if (best_coll == null or dist < best_dist) {
                best_coll = coll;
                best_coll.?.kind = .{ .thing = thing.id };
                best_dist = dist;
            }
        }
    }
    return best_coll;
}

pub fn getPointCollisionInTile(point: V2f, tile: TileMap.Tile, passable_neighbors: std.EnumArray(TileMap.NeighborDir, bool)) ?Collision {
    const rect = TileMap.tileCoordToRect(tile.coord);
    if (!geom.pointIsInRectf(point, rect)) {
        return null;
    }
    const topleft = TileMap.tileCoordToPos(tile.coord);
    const center = TileMap.tileCoordToCenterPos(tile.coord);
    const center_to_pos = point.sub(center);

    // if exactly at the center, we'll always go right, but meh, is ok fallback
    const normal = blk: {
        const n = center_to_pos.normalizedOrZero();
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
                break :blk max_dir;
            }
        }
        break :blk V2f.right;
    };
    const pen_dist = blk: {
        const c_idx: usize = if (normal.x != 0) 0 else 1;
        const base = topleft.toArr()[c_idx];
        const pt = point.toArr()[c_idx];
        const sgn = normal.toArr()[c_idx];
        const dif = pt - base;
        if (sgn > 0) {
            break :blk TileMap.tile_sz_f - dif;
        }
        break :blk dif;
    };
    return Collision{
        .kind = .{ .tile = tile.coord },
        .normal = normal,
        .pen_dist = pen_dist,
        .pos = point.add(normal.scale(pen_dist)),
    };
}

pub fn getCircleCollisionWithTiles(pos: V2f, radius: f32, tilemap: *const TileMap) ?Collision {
    var coll: ?Collision = null;

    for (tilemap.tiles.values()) |tile| outer_blk: {
        if (tile.passable) continue;

        const passable_neighbors = tilemap.getTileNeighborsPassable(tile.coord);
        const center = TileMap.tileCoordToCenterPos(tile.coord);
        if (getPointCollisionInTile(pos, tile, passable_neighbors)) |c| {
            return c;
        }

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
                coll = Collision{
                    .kind = .{ .tile = tile.coord },
                    .normal = v2f(edge_v.y, -edge_v.x).normalized(),
                    .pen_dist = @max(radius - dist, 0),
                    .pos = intersect_pos,
                };
                break :outer_blk;
            }
        }
        // finally corners; only the parts which are beyond the edge
        // TODO optimization - discover the corner in edge detection part - using dot product used to rule out line seg
        for (corners_cw.constSlice()) |corner_pos| {
            const pos_to_corner = corner_pos.sub(pos);
            const dist = pos_to_corner.length();
            if (dist < radius) {
                const normal = blk: {
                    if (dist < 0.001) {
                        if (pos.sub(center).normalizedChecked()) |center_to_pos| {
                            break :blk center_to_pos;
                        } else {
                            break :blk V2f.right;
                        }
                    } else {
                        break :blk pos_to_corner.scale(-1 / dist);
                    }
                };
                coll = Collision{
                    .kind = .{ .tile = tile.coord },
                    .normal = normal,
                    .pen_dist = @max(radius - dist, 0),
                    .pos = corner_pos,
                };
                break :outer_blk;
            }
        }
    }

    return coll;
}

pub fn getNextSweptCircleCollisionWithTiles(ray_pos: V2f, ray_v: V2f, radius: f32, tilemap: *const TileMap) ?Collision {
    assert(radius > 0.001);
    assert(ray_v.lengthSquared() > 0.001);
    const ray_v_n = ray_v.normalized();
    var best_coll: ?Collision = null;
    var best_dist = std.math.inf(f32);

    for (tilemap.tiles.values()) |tile| {
        if (tile.passable) continue;

        const passable_neighbors = tilemap.getTileNeighborsPassable(tile.coord);
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
        // check if ray starts in tile
        if (getPointCollisionInTile(ray_pos, tile, passable_neighbors)) |c| {
            return c;
        }
        // if ray hits edge, swept circle hits edge
        for (edges_cw.constSlice()) |edge| {
            const edge_v = edge[1].sub(edge[0]);
            const intersection = geom.lineSegsIntersect(ray_pos, ray_v, edge[0], edge_v);
            const intersect_point = switch (intersection) {
                .none => continue,
                .colinear => |_c| if (_c) |c| c[0] else continue,
                .intersection => |i| i,
            };
            var coll = Collision{};
            coll.pen_dist = 0;
            coll.normal = v2f(edge_v.y, -edge_v.x).normalized();
            const dot = ray_v_n.dot(coll.normal.neg());
            if (@abs(dot) < 0.001) {
                if (ray_v_n.dot(edge_v) > 0) {
                    coll.pos = edge[0];
                } else {
                    coll.pos = edge[1];
                }
            } else {
                const hyp = radius / dot;
                const circle_center = intersect_point.sub(ray_v_n.scale(hyp));
                coll.pos = circle_center.add(coll.normal.neg().scale(radius));
            }
            const dist = coll.pos.dist(ray_pos);
            if (best_coll == null or dist < best_dist) {
                best_coll = coll;
                best_dist = dist;
            }
        }
        // if ray hits circle centered at corner, swept circle hits corner
        for (corners_cw.constSlice()) |corner_pos| {
            if (getRayCircleCollision(ray_pos, ray_v, corner_pos, radius)) |r_coll| {
                var coll = r_coll;
                coll.pos = coll.pos.add(coll.normal.neg().scale(radius));
                const dist = coll.pos.dist(ray_pos);
                if (best_coll == null or dist < best_dist) {
                    best_coll = coll;
                    best_dist = dist;
                }
            }
        }
    }

    return best_coll;
}
