const std = @import("std");
const assert = std.debug.assert;
const utl = @import("util.zig");

pub const Platform = @import("raylib.zig");
const core = @import("core.zig");
const debug = @import("debug.zig");
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
const Log = App.Log;
const getPlat = App.getPlat;
const Thing = @import("Thing.zig");
const Room = @import("Room.zig");
const Data = @import("Data.zig");
const TileMap = @This();

pub const max_map_sz: i64 = 64;
pub const max_map_sz_f: f32 = max_map_sz;
pub const max_map_tiles: i64 = max_map_sz * max_map_sz;
pub const max_map_layers = 8;
pub const max_map_tilesets = 16;
pub const max_map_exits = 4;
pub const max_map_spawns = 32;
pub const max_map_creatures = 32;

pub const tile_sz: i64 = 32;
pub const tile_sz_f: f32 = tile_sz;
pub const tile_dims = V2f.splat(tile_sz);
pub const tile_dims_2 = V2f.splat(tile_sz_f * 0.5);

pub const NeighborDir = enum {
    N,
    E,
    S,
    W,
};
pub const neighbor_dirs: [4]NeighborDir = .{ .N, .E, .S, .W };
pub const neighbor_dirs_coords = std.EnumArray(NeighborDir, V2i).init(.{
    .N = v2i(0, -1),
    .E = v2i(1, 0),
    .S = v2i(0, 1),
    .W = v2i(-1, 0),
});

// pathing/collision braindump (written while adding spike pits)
//
// cases NOW
// 1. Normal moving creatures, projectiles... collide with walls, NOT spikes
// 2. Non-flying Things which are "on" spikes (center inside tile) get hit, go flying out of spikes
// 3. Mana crystals collide with both walls and spikes (bounce off same)
// 4. Non-flying things path around spikes, flying Things path over
// cases FUTURE
// 5. Low walls allow LOS, but otherwise act like regular walls
// 6. Path around lava, but don't get hit and go flying. mana crystals go through
// ???
// - collision mask/layers
//   - determines what actually COLLIDES and stops movement - goal being they never overlap
//   - everything collides with wall/low wall, only mana crystals collide with spikes
// - pathing mask/layers
//   - determines what we are allowed to pathfind on (and its cost?)
//   - flying creatures will path over spikes, lava... other Things will avoid them
//   - path layers must be a superset of coll layers - you can't path through things you collide with!
//   - Things dont need path layers? Maybe? They specify a mask of what they can path over
//

// layers we may want to differentiate for pathing
pub const PathLayer = enum {
    normal,
    flying,

    pub const Mask = std.EnumSet(PathLayer);
    pub const ConnIds = std.EnumArray(PathLayer, ?u8);
};

pub const GameTile = struct {
    coord: V2i,
    // default tile is empty (no wall) and fully pathable
    coll_layers: Thing.Collision.Mask = Thing.Collision.Mask.initEmpty(),
    path_layers: PathLayer.Mask = PathLayer.Mask.initFull(),
    path_conn_ids: PathLayer.ConnIds = PathLayer.ConnIds.initFill(null),
    // TODO
    // blocks_LOS: bool = false,
    pub fn canPath(self: *const GameTile, mask: PathLayer.Mask) bool {
        return mask.intersectWith(self.path_layers).count() > 0;
    }
    pub fn collides(self: *const GameTile, mask: Thing.Collision.Mask) bool {
        return mask.intersectWith(self.coll_layers).count() > 0;
    }
};

pub const TileIndex = u32;
pub const TileLayer = struct {
    pub const Tile = struct {
        idx: u32 = undefined,
    };
    above_objects: bool = false,
    tiles: std.BoundedArray(TileLayer.Tile, max_map_tiles) = .{},
};
pub const TileSetReference = struct {
    name: Data.TileSet.NameBuf,
    data_idx: usize = 0,
    first_gid: usize = 1,
};

pub const NameBuf = utl.BoundedString(64);

name: NameBuf = .{},
kind: Data.RoomKind = .testu,
id: i32 = 0,
game_tiles: std.BoundedArray(GameTile, max_map_tiles) = .{},
tile_layers: std.BoundedArray(TileLayer, max_map_layers) = .{},
tilesets: std.BoundedArray(TileSetReference, max_map_tilesets) = .{},
creatures: std.BoundedArray(struct { kind: Thing.CreatureKind, pos: V2f }, max_map_creatures) = .{},
exits: std.BoundedArray(ExitDoor, max_map_exits) = .{},
wave_spawns: std.BoundedArray(V2f, max_map_spawns) = .{},
dims_tiles: V2i = .{},
dims_game: V2i = .{},
rect_dims: V2f = .{},

pub fn tileIdxToTileSetRef(self: *const TileMap, tile_idx: usize) ?TileSetReference {
    if (tile_idx == 0) return null;
    assert(self.tilesets.len > 0);

    var tileset_ref = self.tilesets.get(self.tilesets.len - 1);
    for (0..self.tilesets.len - 1) |i| {
        const curr_ts_ref = self.tilesets.get(i);
        const next_ts_ref = self.tilesets.get(i + 1);
        if (tile_idx >= curr_ts_ref.first_gid and tile_idx < next_ts_ref.first_gid) {
            tileset_ref = curr_ts_ref;
            break;
        }
    }
    return tileset_ref;
}

pub fn tileCoordToGameTile(self: *TileMap, tile_coord: V2i) ?*GameTile {
    const idxi = tile_coord.x + tile_coord.y * self.dims_tiles.x;
    if (idxi < 0) return null;
    const idx = utl.as(usize, idxi);
    if (idx >= self.game_tiles.len) return null;
    const gt = &self.game_tiles.buffer[idx];
    // TODO ? change?
    if (!gt.coord.eql(tile_coord)) return null;
    return gt;
}

fn gameTileCoordToIdx(self: *const TileMap, gt_coord: V2i) ?usize {
    if (gt_coord.x < 0 or gt_coord.y < 0) return null;
    if (gt_coord.x >= self.dims_game.x or gt_coord.y >= self.dims_game.y) return null;
    const idxi = gt_coord.x + gt_coord.y * self.dims_game.x;
    if (idxi < 0) return null;
    const idx = utl.as(usize, idxi);
    if (idx >= self.game_tiles.len) return null;
    return idx;
}

pub fn gameTileCoordToGameTile(self: *TileMap, gt_coord: V2i) ?*GameTile {
    if (self.gameTileCoordToIdx(gt_coord)) |idx| {
        const gt = &self.game_tiles.buffer[idx];
        assert(gt.coord.eql(gt_coord));
        return gt;
    }
    return null;
}

pub fn gameTileCoordToConstGameTile(self: *const TileMap, gt_coord: V2i) ?*const GameTile {
    return @constCast(self).gameTileCoordToGameTile(gt_coord);
}

pub fn posToTileCoord(pos: V2f) V2i {
    return .{
        .x = utl.as(i32, @floor(pos.x / tile_sz_f)),
        .y = utl.as(i32, @floor(pos.y / tile_sz_f)),
    };
}

pub fn tileCoordToPos(coord: V2i) V2f {
    return coord.scale(tile_sz).toV2f();
}

pub fn tileCoordToCenterPos(coord: V2i) V2f {
    return tileCoordToPos(coord).add(tile_dims_2);
}

pub fn posToTileTopLeft(pos: V2f) V2f {
    return tileCoordToPos(posToTileCoord(pos));
}

pub fn tileTopLeftToCornersCW(topleft: V2f) [4]V2f {
    return .{
        topleft,
        topleft.add(v2f(tile_sz_f, 0)),
        topleft.add(tile_dims),
        topleft.add(v2f(0, tile_sz_f)),
    };
}

pub fn tileCoordToRect(coord: V2i) geom.Rectf {
    return .{
        .pos = tileCoordToPos(coord),
        .dims = tile_dims,
    };
}

pub fn getTileNeighborsPassable(self: *const TileMap, mask: Thing.Collision.Mask, coord: V2i) std.EnumArray(NeighborDir, bool) {
    var ret: std.EnumArray(NeighborDir, bool) = undefined;
    for (neighbor_dirs) |nd| {
        const neighbor_coord = coord.add(neighbor_dirs_coords.get(nd));
        const tile = self.gameTileCoordToConstGameTile(neighbor_coord);
        const passable = if (tile) |t| !t.collides(mask) else true;
        ret.set(nd, passable);
    }
    return ret;
}

pub fn __unused__findPathAStar(self: *const TileMap, allocator: std.mem.Allocator, start: V2f, goal: V2f) Error!std.BoundedArray(V2f, 32) {
    const AStar = struct {
        const PqEl = struct {
            p: V2i,
            g: f32,
            f: f32,
            fn lessThan(ctx: void, a: PqEl, b: PqEl) std.math.Order {
                _ = ctx;
                return std.math.order(a.f, b.f);
            }
        };
        const SeenEntry = struct {
            visited: bool,
            prev: V2i,
            best_g: f32,
        };
    };
    const start_coord = posToTileCoord(start);
    const goal_coord = posToTileCoord(goal);
    var path_arr = std.ArrayList(V2f).init(allocator);
    defer path_arr.deinit();
    var queue = std.PriorityQueue(AStar.PqEl, void, AStar.PqEl.lessThan).init(allocator, {});
    defer queue.deinit();
    var seen = std.AutoArrayHashMap(V2i, AStar.SeenEntry).init(allocator);
    defer seen.deinit();

    try queue.add(.{
        .p = start_coord,
        .g = 0,
        .f = start.sub(goal).length(),
    });
    try seen.put(
        start_coord,
        .{
            .visited = false,
            .prev = undefined,
            .best_g = 0,
        },
    );

    while (queue.items.len > 0) {
        const curr = queue.remove();

        seen.getPtr(curr.p).?.visited = true;

        if (curr.p.eql(goal_coord)) {
            break;
        }
        for (neighbor_dirs) |dir| {
            const dir_v = neighbor_dirs_coords.get(dir);
            const this_move_cost = tile_sz_f;
            const next_g = curr.g + this_move_cost;
            const next_p = tileCoordToCenterPos(curr.p.add(dir_v));
            const next = AStar.PqEl{
                .p = posToTileCoord(next_p),
                .g = next_g,
                .f = next_g + next_p.sub(goal).length(),
            };
            //std.debug.print("neighbor {}, {}\n", .{ next.p.x, next.p.y });
            if (self.gameTileCoordToGameTile(posToTileCoord(next_p))) |tile| {
                if (!tile.passable) continue;
            }
            const entry = try seen.getOrPut(next.p);
            if (entry.found_existing) {
                if (entry.value_ptr.visited) continue;

                if (next.g < entry.value_ptr.best_g) {
                    entry.value_ptr.best_g = next.g;
                    entry.value_ptr.prev = curr.p;
                }
            } else {
                entry.value_ptr.* = .{
                    .visited = false,
                    .prev = curr.p,
                    .best_g = next.g,
                };
            }

            try queue.add(next);
        }
    }
    // backtrack to get path
    {
        var curr = goal_coord;
        while (!curr.eql(start_coord)) {
            try path_arr.append(tileCoordToCenterPos(curr));
            curr = seen.get(curr).?.prev;
        }
        try path_arr.append(start);
        path_arr.items[0] = goal;
    }
    std.mem.reverse(V2f, path_arr.items);

    var ret = std.BoundedArray(V2f, 32){};
    const ret_path_len = @min(ret.buffer.len, path_arr.items.len);

    for (0..ret_path_len) |i| {
        ret.append(path_arr.items[i]) catch unreachable;
    }

    return ret;
}

pub fn updateConnectedComponents(self: *TileMap) Error!void {
    const plat = getPlat();
    const path_layers = utl.enumValueList(PathLayer);
    assert(path_layers.len == 2);
    assert(path_layers[0] == .normal);
    assert(path_layers[1] == .flying);

    for (self.game_tiles.slice()) |*t| {
        t.path_conn_ids = PathLayer.ConnIds.initFill(null);
    }

    var queue = std.ArrayList(V2i).init(plat.heap);
    defer queue.deinit();
    var seen = std.AutoArrayHashMap(V2i, void).init(plat.heap);
    defer seen.deinit();

    // TODO flying not getting connected!!!
    for (path_layers) |layer| {
        const path_mask = PathLayer.Mask.initOne(layer);
        var curr_id: u8 = 0;

        for (self.game_tiles.slice()) |*tile| {
            if (!tile.path_layers.contains(layer)) continue;
            // already part of a connected component
            if (tile.path_conn_ids.get(layer) != null) continue;

            queue.clearRetainingCapacity();
            seen.clearRetainingCapacity();
            try queue.append(tile.coord);
            try seen.put(tile.coord, {});

            while (queue.items.len > 0) {
                const curr = queue.orderedRemove(0);
                if (self.gameTileCoordToGameTile(curr)) |curr_tile| {
                    assert(curr_tile.path_conn_ids.get(layer) == null);
                    curr_tile.path_conn_ids.getPtr(layer).* = curr_id;
                }
                for (neighbor_dirs) |dir| {
                    const dir_v = neighbor_dirs_coords.get(dir);
                    const next = curr.add(dir_v);
                    if (!self.tileCoordIsPathable(path_mask, next)) continue;
                    if (seen.get(next)) |_| continue;
                    try seen.put(next, {});
                    try queue.append(next);
                }
            }
            curr_id += 1;
        }
    }
}

pub fn getClosestPathablePos(self: *const TileMap, layer: PathLayer, conn_id: ?u8, point: V2f, radius: f32) Error!?V2f {
    const plat = getPlat();
    const max_dim = self.getRoomRect().dims.max();
    const max_dist_away_squared = max_dim * max_dim;
    const Pair = struct { coord: V2i, pos: V2f };
    var queue = std.ArrayList(Pair).init(plat.heap);
    defer queue.deinit();
    var seen = std.AutoArrayHashMap(V2i, void).init(plat.heap);
    defer seen.deinit();
    var best_dist = std.math.inf(f32);
    var best_pair: ?Pair = null;

    const pt_coord = posToTileCoord(point);
    try queue.append(.{ .coord = pt_coord, .pos = point });
    try seen.put(pt_coord, {});

    while (queue.items.len > 0) {
        const curr_pair: Pair = queue.orderedRemove(0);
        if (self.gameTileCoordToConstGameTile(curr_pair.coord)) |curr_tile| {
            if (curr_tile.path_conn_ids.get(layer)) |curr_conn_id| {
                if (conn_id == null or curr_conn_id == conn_id.?) {
                    const dist = curr_pair.pos.dist(point);
                    if (dist < best_dist) {
                        best_dist = dist;
                        best_pair = curr_pair;
                    }
                    continue; // dont explore neighbors, this is the perimeter!
                }
            }
        }
        for (neighbor_dirs) |dir| {
            const dir_v = neighbor_dirs_coords.get(dir);
            const next_coord = curr_pair.coord.add(dir_v);
            if (seen.get(next_coord)) |_| continue;
            try seen.put(next_coord, {});
            const center_pos = tileCoordToCenterPos(next_coord);
            const point_to_pos = center_pos.sub(point);
            if (point_to_pos.lengthSquared() > max_dist_away_squared) continue;
            const dir_from_point = point_to_pos.normalizedChecked() orelse V2f.right;
            const closest_pos = center_pos.sub(dir_from_point.scale(tile_sz_f * 0.5 - radius));
            try queue.append(.{
                .coord = next_coord,
                .pos = closest_pos,
            });
        }
    }
    if (best_pair) |p| {
        return p.pos;
    }
    return null;
}

pub fn tileCoordIsPathable(self: *const TileMap, mask: PathLayer.Mask, coord: V2i) bool {
    if (self.gameTileCoordToConstGameTile(coord)) |tile| {
        return tile.canPath(mask);
    }
    return false;
}

pub fn raycast(self: *const TileMap, _a: V2f, _b: V2f, path_mask: ?PathLayer.Mask, coll_mask: ?Thing.Collision.Mask) ?V2i {
    const a_coord = posToTileCoord(_a);
    const b_coord = posToTileCoord(_b);
    const a = _a.scale(1 / tile_sz_f);
    const b = _b.scale(1 / tile_sz_f);
    const dx: f32 = @abs(b.x - a.x);
    const dy: f32 = @abs(b.y - a.y);

    var sx: i32 = undefined;
    var sy: i32 = undefined;
    var err: f32 = dx + dy;

    if (dx < 0.001) {
        sx = 0;
        err = std.math.inf(f32);
    } else if (a.x < b.x) {
        sx = 1;
        err = (@floor(a.x) + 1 - a.x) * dy;
    } else {
        sx = -1;
        err = (a.x - @floor(a.x)) * dy;
    }
    if (dy < 0.001) {
        sy = 0;
        err = -std.math.inf(f32);
    } else if (a.y < b.y) {
        sy = 1;
        err -= (@floor(a.y) + 1 - a.y) * dx;
    } else {
        sy = -1;
        err -= (a.y - @floor(a.y)) * dx;
    }

    var curr: V2i = a_coord;
    //std.debug.print("a_coord: {}, {}\n", .{ curr.x, curr.y });
    //std.debug.print("b_coord: {}, {}\n", .{ b_coord.x, b_coord.y });
    //std.debug.print("s: {}, {}\n", .{ sx, sy });
    //std.debug.print("d: {}, {}\n", .{ dx, dy });
    while (true) {
        //std.debug.print("curr: {}, {}\n", .{ curr.x, curr.y });
        // TODO tileCoolrdBlocksLOS
        if (self.gameTileCoordToConstGameTile(curr)) |tile| {
            if (path_mask) |mask| {
                if (!tile.canPath(mask)) return curr;
            }
            if (coll_mask) |mask| {
                if (tile.collides(mask)) return curr;
            }
        }
        if (curr.eql(b_coord)) break;
        //std.debug.print("e: {}\n", .{err});

        if (err > 0) {
            curr.y += sy;
            err -= dx;
        } else {
            curr.x += sx;
            err += dy;
        }
    }
    //std.debug.print("\n", .{});
    return null;
}

pub fn raycastBothThicc(self: *const TileMap, a: V2f, b: V2f, thickness: f32, path_mask: ?PathLayer.Mask, coll_mask: ?Thing.Collision.Mask) bool {
    const a_to_b = a.sub(b);
    const n = a_to_b.rot90CW().normalizedOrZero();
    if (n.isZero()) {
        return self.isLOSBetween(a, b);
    }
    const offset = n.scale(thickness * 0.5);
    const a_right = a.add(offset);
    const b_right = b.add(offset);
    const a_left = a.sub(offset);
    const b_left = b.sub(offset);
    return self.raycast(a_right, b_right, path_mask, coll_mask) == null and self.raycast(a_left, b_left, path_mask, coll_mask) == null;
}

pub inline fn raycastLOS(self: *const TileMap, a: V2f, b: V2f) ?V2i {
    return self.raycast(a, b, null, comptime Thing.Collision.Mask.initOne(.wall));
}

pub inline fn isLOSBetweenThicc(self: *const TileMap, a: V2f, b: V2f, thickness: f32) bool {
    return self.raycastBothThicc(a, b, thickness, null, comptime Thing.Collision.Mask.initOne(.wall));
}

pub inline fn isLOSBetween(self: *const TileMap, _a: V2f, _b: V2f) bool {
    return self.raycastLOS(_a, _b) == null;
}

pub inline fn isStraightPathBetween(self: *const TileMap, _a: V2f, _b: V2f, radius: f32, mask: PathLayer.Mask) bool {
    return self.raycastBothThicc(_a, _b, radius * 2, mask, null);
}

pub fn findPathThetaStar(self: *const TileMap, allocator: std.mem.Allocator, layer: PathLayer, start: V2f, desired_goal: V2f, radius: f32, coords_searched: *std.BoundedArray(V2i, 128)) Error!std.BoundedArray(V2f, 32) {
    const ThetaStar = struct {
        const PqEl = struct {
            p: V2i,
            g: f32,
            f: f32,
            fn lessThan(ctx: void, a: PqEl, b: PqEl) std.math.Order {
                _ = ctx;
                return std.math.order(a.f, b.f);
            }
        };
        const SeenEntry = struct {
            visited: bool,
            prev: ?V2i,
            best_g: f32,
        };
    };
    const path_mask = PathLayer.Mask.initMany(&.{layer});
    const start_coord = posToTileCoord(start);
    var actual_goal = desired_goal;
    var goal_coord = posToTileCoord(actual_goal);
    var ret = std.BoundedArray(V2f, 32){};

    if (self.gameTileCoordToConstGameTile(goal_coord)) |goal_tile| {
        if (self.gameTileCoordToConstGameTile(start_coord)) |start_tile| {
            if (!start_tile.path_layers.contains(layer)) {
                return ret;
            }
            const conn_id = start_tile.path_conn_ids.get(layer).?;
            if (!goal_tile.path_layers.contains(layer) or goal_tile.path_conn_ids.get(layer) != conn_id) {
                if (try self.getClosestPathablePos(layer, conn_id, desired_goal, radius)) |closest| {
                    actual_goal = closest;
                } else {
                    return ret;
                }
                goal_coord = posToTileCoord(actual_goal);
            }
        } else {
            return ret;
        }
    } else {
        return ret;
    }

    if (start_coord.eql(goal_coord)) {
        ret.appendAssumeCapacity(start);
        ret.appendAssumeCapacity(actual_goal);
        return ret;
    }

    var path_arr = std.ArrayList(V2f).init(allocator);
    defer path_arr.deinit();
    var queue = std.PriorityQueue(ThetaStar.PqEl, void, ThetaStar.PqEl.lessThan).init(allocator, {});
    defer queue.deinit();
    var seen = std.AutoArrayHashMap(V2i, ThetaStar.SeenEntry).init(allocator);
    defer seen.deinit();

    try queue.add(.{
        .p = start_coord,
        .g = 0,
        .f = start.sub(actual_goal).length(),
    });
    try seen.put(
        start_coord,
        .{
            .visited = false,
            .prev = null,
            .best_g = 0,
        },
    );
    coords_searched.len = 0;

    while (queue.items.len > 0) {
        const curr = queue.remove();
        const curr_seen = seen.getPtr(curr.p).?;
        if (curr_seen.visited) continue;
        curr_seen.visited = true;
        coords_searched.append(curr.p) catch {};

        if (curr.p.eql(goal_coord)) {
            break;
        }
        const parent_stuff: ?struct {
            coord: V2i,
            pos: V2f,
            seen: ThetaStar.SeenEntry,
        } = if (curr_seen.prev) |parent_coord| .{
            .coord = parent_coord,
            .pos = if (parent_coord.eql(start_coord)) start else tileCoordToCenterPos(parent_coord),
            .seen = seen.get(parent_coord).?,
        } else null;

        for (neighbor_dirs) |dir| {
            const dir_v = neighbor_dirs_coords.get(dir);
            const next_coord = curr.p.add(dir_v);
            if (!self.tileCoordIsPathable(path_mask, next_coord)) continue;
            const entry = try seen.getOrPut(next_coord);
            if (entry.found_existing and entry.value_ptr.visited) continue;
            const next_pos = if (next_coord.eql(goal_coord)) actual_goal else tileCoordToCenterPos(next_coord);

            var this_move_cost = tile_sz_f;
            var prev = curr.p;
            var prev_g = curr.g;
            if (parent_stuff) |parent| {
                const parent_to_next = next_pos.sub(parent.pos);
                if (self.isStraightPathBetween(parent.pos, next_pos, radius, path_mask)) {
                    this_move_cost = parent_to_next.length();
                    prev = parent.coord;
                    prev_g = parent.seen.best_g;
                }
            }
            const next_g = prev_g + this_move_cost;
            const next = ThetaStar.PqEl{
                .p = next_coord,
                .g = next_g,
                .f = next_g + next_pos.sub(actual_goal).length(),
            };
            //std.debug.print("neighbor {}, {}\n", .{ next.p.x, next.p.y });

            if (entry.found_existing) {
                if (next.g < entry.value_ptr.best_g) {
                    entry.value_ptr.best_g = next.g;
                    entry.value_ptr.prev = prev;
                    try queue.add(next);
                }
            } else {
                entry.value_ptr.* = .{
                    .visited = false,
                    .prev = prev,
                    .best_g = next.g,
                };
                try queue.add(next);
            }
        }
    }
    // backtrack to get path
    if (seen.get(goal_coord) == null) {
        return ret;
    }
    {
        var curr = goal_coord;
        while (!curr.eql(start_coord)) {
            try path_arr.append(tileCoordToCenterPos(curr));
            curr = seen.get(curr).?.prev.?;
        }
        try path_arr.append(start);
        path_arr.items[0] = actual_goal;
    }
    std.mem.reverse(V2f, path_arr.items);

    const ret_path_len = @min(ret.buffer.len, path_arr.items.len);

    for (0..ret_path_len) |i| {
        ret.append(path_arr.items[i]) catch unreachable;
    }

    return ret;
}

pub fn debugDrawPath(_: *const TileMap, camera: draw.Camera2D, path: []const V2i) Error!void {
    const plat = getPlat();
    const inv_zoom = 1 / camera.zoom;
    const line_thickness = inv_zoom;
    for (0..path.len - 1) |i| {
        const p0 = tileCoordToCenterPos(path[i]);
        const p1 = tileCoordToCenterPos(path[i + 1]);
        plat.linef(p0, p1, .{ .thickness = line_thickness, .color = Colorf.green });
    }
}

pub fn debugDrawGrid(_: *const TileMap, camera: draw.Camera2D) void {
    const plat = getPlat();
    const inv_zoom = 1 / camera.zoom;
    const camera_dims = plat.game_canvas_dims_f.scale(inv_zoom);
    const line_thickness = inv_zoom;
    // add 2 to grid dims to make sure it covers the screen
    const grid_dims = camera_dims.scale(1 / tile_sz_f).toV2i().add(v2i(2, 2));
    const grid_cols = utl.as(usize, grid_dims.x);
    const grid_rows = utl.as(usize, grid_dims.y);
    // go a tile beyond to make sure grid covers screen
    const grid_topleft = posToTileTopLeft(camera.pos.sub(camera_dims.scale(0.5).add(tile_dims)));
    // exact bottom right by rescaling grid_dims with tile size
    const grid_botright = grid_topleft.add(grid_dims.toV2f().scale(tile_sz_f));

    for (0..grid_cols) |col| {
        const x: f32 = grid_topleft.x + utl.as(f32, col) * tile_sz;
        plat.linef(v2f(x, grid_topleft.y), v2f(x, grid_botright.y), .{ .thickness = line_thickness, .color = Colorf.green.fade(0.5) });
    }
    for (0..grid_rows) |row| {
        const y: f32 = grid_topleft.y + utl.as(f32, row) * tile_sz;
        plat.linef(v2f(grid_topleft.x, y), v2f(grid_botright.x, y), .{ .thickness = line_thickness, .color = Colorf.green.fade(0.5) });
    }
}

pub fn debugDraw(self: *const TileMap, camera: draw.Camera2D) void {
    const plat = getPlat();
    for (self.game_tiles.constSlice()) |game_tile| {
        var color: Colorf = undefined;
        if (game_tile.coll_layers.contains(.spikes)) {
            if (game_tile.coll_layers.contains(.wall)) {
                color = Colorf.green;
            } else {
                color = Colorf.red;
            }
        } else if (game_tile.coll_layers.contains(.wall)) {
            color = Colorf.blue;
        } else {
            color = Colorf.blank;
        }
        const tl_pos = tileCoordToPos(game_tile.coord);
        plat.rectf(tl_pos, tile_dims, .{ .fill_color = color.fade(0.3) });
        plat.textf(tl_pos.add(v2f(1, 1)), "{?}", .{game_tile.path_conn_ids.get(.normal)}, .{ .color = .white, .size = 10 }) catch {};
    }
    self.debugDrawGrid(camera);
}

pub fn getRoomRect(self: *const TileMap) geom.Rectf {
    //const topleft_coord = v2i(
    //    -@divFloor(self.dims_tiles.x, 2),
    //    -@divFloor(self.dims_tiles.y, 2),
    //);
    const topleft_coord: V2i = .{};
    const topleft_pos = tileCoordToPos(topleft_coord).sub(tile_dims_2);
    return .{
        .pos = topleft_pos,
        .dims = self.rect_dims,
    };
}

fn renderTile(self: *const TileMap, pos: V2f, tile: TileLayer.Tile) void {
    const plat = getPlat();
    const data = App.get().data;
    const ref = self.tileIdxToTileSetRef(tile.idx) orelse {
        Log.err("unknown tileset ref!", .{});
        return;
    };
    assert(ref.data_idx < data.tilesets.items.len);
    const tileset = &data.tilesets.items[ref.data_idx];
    assert(tile.idx >= ref.first_gid);
    const tileset_tile_idx = tile.idx - ref.first_gid;
    assert(tileset_tile_idx < tileset.tiles.len);
    const tileset_tile_idxi = utl.as(i32, tileset_tile_idx);
    const sheet_coord = v2i(@mod(tileset_tile_idxi, tileset.sheet_dims.x), @divFloor(tileset_tile_idxi, tileset.sheet_dims.x));
    assert(sheet_coord.x < tileset.sheet_dims.x and sheet_coord.y < tileset.sheet_dims.y);
    const src_px_coord = v2i(sheet_coord.x * tileset.tile_dims.x, sheet_coord.y * tileset.tile_dims.y);
    const opt = draw.TextureOpt{
        .src_dims = tileset.tile_dims.toV2f(),
        .src_pos = src_px_coord.toV2f(),
        .uniform_scaling = core.game_sprite_scaling,
        .round_to_pixel = false,
    };
    plat.texturef(pos, tileset.texture, opt);
}

fn renderLayer(self: *const TileMap, layer: *const TileLayer) void {
    const room_rect = self.getRoomRect();
    var map_coord: V2i = .{};
    for (layer.tiles.constSlice()) |tile| {
        if (tile.idx != 0) {
            const pos = room_rect.pos.add(tileCoordToPos(map_coord));
            self.renderTile(pos, tile);
        }
        map_coord.x += 1;
        if (map_coord.x >= self.dims_tiles.x) {
            map_coord.x = 0;
            map_coord.y += 1;
        }
    }
}

pub fn renderUnderObjects(self: *const TileMap) Error!void {
    const plat = getPlat();
    const room_rect = self.getRoomRect();
    plat.rectf(room_rect.pos, room_rect.dims, .{ .fill_color = Colorf.rgb(0.4, 0.4, 0.4) });
    for (self.tile_layers.constSlice()) |*layer| {
        if (layer.above_objects) continue;
        self.renderLayer(layer);
    }
}

pub fn renderOverObjects(self: *const TileMap, cam: draw.Camera2D, things: []const *const Thing) Error!void {
    const plat = App.getPlat();
    const data = App.get().data;
    const shader = data.shaders.get(.tile_foreground_fade);
    var num_circles: usize = 0;
    for (things, 0..) |t, i| {
        if (num_circles >= 128) break; // MAX_CIRCLES in shader
        const visible_circle = t.getApproxVisibleCircle();
        var pos = plat.camPosToScreenPos(cam, visible_circle.pos);
        // shader screen pos needs y inverted!
        pos.y = plat.game_canvas_dims_f.y - pos.y;
        const radius = visible_circle.radius;
        const pos_name = try utl.bufPrintLocal("circles[{}].pos", .{i});
        try plat.setShaderValue(shader, pos_name, pos);
        const radius_name = try utl.bufPrintLocal("circles[{}].radius", .{i});
        try plat.setShaderValue(shader, radius_name, radius);
        num_circles += 1;
    }
    plat.setShaderValuesScalar(shader, .{
        .numCircles = num_circles,
    });
    plat.setShader(shader);
    for (self.tile_layers.constSlice()) |*layer| {
        if (!layer.above_objects) continue;
        self.renderLayer(layer);
    }
    plat.setDefaultShader();
}

pub const ExitDoor = struct {
    pub const RewardPreview = enum {
        none,
        gold,
        item,
        shop,
        end,
    };
    pub const ChallengePreview = enum {
        none,
        boss,
    };

    const radius = 12;
    const select_radius = 14;
    const closed_color = Colorf.rgb(0.4, 0.4, 0.4);
    const rim_color = Colorf.rgb(0.4, 0.3, 0.4);
    const open_color_1 = Colorf.rgb(0.2, 0.1, 0.2);
    const open_color_2 = Colorf.rgb(0.4, 0.1, 0.4);
    const open_hover_color = Colorf.rgb(0.4, 0.1, 0.4);
    const arrow_hover_color = Colorf.rgb(0.7, 0.5, 0.7);

    pos: V2f,
    door_pos: V2f,
    reward_preview: RewardPreview = .none,
    challenge_preview: ChallengePreview = .none,
    selected: bool = false,

    pub fn updateSelected(self: *ExitDoor, room: *Room) Error!bool {
        //const plat = App.getPlat();
        if (room.getConstPlayer()) |p| {
            if (p.path.len > 0) {
                const last_path_pos = p.path.buffer[p.path.len - 1];
                self.selected = last_path_pos.dist(self.pos) <= ExitDoor.radius + 5;
                if (self.selected) {
                    if (p.pos.dist(self.pos) <= select_radius) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    pub fn renderUnder(self: *const ExitDoor, room: *const Room) Error!void {
        const plat = App.getPlat();

        // rim
        plat.circlef(self.pos, ExitDoor.radius, .{ .fill_color = ExitDoor.rim_color });
        // fill
        if (room.progress_state == .won) {
            const mouse_pos = plat.getMousePosWorld(room.camera);
            const tick_60 = @mod(room.curr_tick, 360);
            const f = utl.pi * utl.as(f32, tick_60) / 360;
            const t = @sin(f);
            var opt = draw.PolyOpt{
                .fill_color = open_color_1.lerp(open_color_2, t),
                .outline = .{ .color = rim_color },
            };
            if (mouse_pos.dist(self.pos) <= select_radius) {
                opt.fill_color = open_hover_color;
            }
            plat.circlef(self.pos.add(v2f(0, 2)), radius - 1, opt);
        } else {
            const opt = draw.PolyOpt{
                .fill_color = closed_color,
                .outline = .{ .color = rim_color },
            };
            plat.circlef(self.pos.add(v2f(0, 2)), radius - 1, opt);
        }
    }

    pub fn renderOver(self: *const ExitDoor, room: *const Room) Error!void {
        const plat = App.getPlat();
        if (room.progress_state == .won) {
            const mouse_pos = plat.getMousePosWorld(room.camera);
            if (self.selected or mouse_pos.dist(self.pos) <= select_radius) {
                const tick_60 = @mod(room.curr_tick, 60);
                const f = utl.pi * utl.as(f32, tick_60) / 60;
                const t = @sin(f);
                var color = arrow_hover_color;
                if (self.selected) {
                    color = Colorf.white;
                }
                const range = 10;
                const base = self.pos.sub(v2f(0, 50 + range * t));
                const end = base.add(v2f(0, 35));
                plat.arrowf(base, end, .{ .thickness = 7.5, .color = color });
            }
        }
    }
};
