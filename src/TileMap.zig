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

const getPlat = @import("App.zig").getPlat;
const Thing = @import("Thing.zig");
const Room = @import("Room.zig");
const TileMap = @This();

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

pub const Tile = struct {
    coord: V2i,
    passable: bool = true,
};

pub const Spawn = struct {
    kind: Thing.Kind,
    pos: V2f,
};

pub const tile_sz: i64 = 64;
pub const tile_sz_f: f32 = tile_sz;
pub const tile_dims = V2f.splat(tile_sz);
pub const tile_dims_2 = V2f.splat(tile_sz_f * 0.5);

initted: bool = false,
spawns: std.BoundedArray(Spawn, 128) = .{},
start_zone: geom.Rectf = undefined,
end_zone: geom.Rectf = undefined,
tiles: std.AutoArrayHashMap(V2i, Tile) = undefined,
dims: V2f = .{},

pub fn initStr(self: *TileMap, str: []const u8) Error!void {
    if (self.initted) return;

    self.spawns.len = 0;
    self.tiles = @TypeOf(self.tiles).init(getPlat().heap);
    var zones = [2]geom.Rectf{ .{}, .{} };
    var size = v2i(0, 0);
    var line_it = std.mem.tokenizeScalar(u8, str, '\n');
    while (line_it.next()) |line| {
        size.x = @intCast(line.len);
        size.y += 1;
    }

    const topleft = v2i(-@divFloor(size.x, 2), -@divFloor(size.y, 2));
    var curr_coord = topleft;
    line_it = std.mem.tokenizeScalar(u8, str, '\n');

    while (line_it.next()) |line| {
        for (line) |ch| {
            switch (ch) {
                '#' => {
                    try self.tiles.put(curr_coord, .{
                        .coord = curr_coord,
                        .passable = false,
                    });
                },
                'p' => {
                    self.spawns.append(.{ .kind = .player, .pos = tileCoordToCenterPos(curr_coord) }) catch std.log.warn("Out of spawns!", .{});
                },
                't' => {
                    self.spawns.append(.{ .kind = .troll, .pos = tileCoordToCenterPos(curr_coord) }) catch std.log.warn("Out of spawns!", .{});
                },
                'g' => {
                    self.spawns.append(.{ .kind = .gobbow, .pos = tileCoordToCenterPos(curr_coord) }) catch std.log.warn("Out of spawns!", .{});
                },
                'A', 'B' => {
                    const idx: usize = ch - 'A';
                    var zone_pos = zones[idx].pos.toArr();
                    var zone_dims = zones[idx].dims.toArr();
                    const v_pos = tileCoordToPos(curr_coord);
                    const tl_pos = v_pos.toArr();
                    const br_pos = v_pos.add(tile_dims).toArr();
                    for (0..2) |i| {
                        if (zone_dims[i] == 0) {
                            zone_pos[i] = tl_pos[i];
                            zone_dims[i] = tile_sz_f;
                        } else if (tl_pos[i] < zone_pos[i]) {
                            zone_dims[i] += zone_pos[i] - tl_pos[i];
                            zone_pos[i] = tl_pos[i];
                        }
                        if (zone_dims[i] == 0) {
                            zone_pos[i] = tl_pos[i]; // yes tl
                            zone_dims[i] = tile_sz_f;
                        } else if (br_pos[i] > zone_pos[i] + zone_dims[i]) {
                            zone_dims[i] = br_pos[i] - zone_pos[i];
                        }
                    }
                    zones[idx] = .{ .pos = V2f.fromArr(zone_pos), .dims = V2f.fromArr(zone_dims) };
                },
                else => {},
            }
            curr_coord.x += 1;
        }
        curr_coord.y += 1;
        curr_coord.x = topleft.x;
    }
    self.dims = size.toV2f().scale(tile_sz_f);
    self.start_zone = zones[0];
    self.end_zone = zones[1];
    self.initted = true;
    std.debug.print("Loaded tilemap:\n size: {} x {}\n dims (px): {d:0.1} x {d:0.1}\n", .{ size.x, size.y, self.dims.x, self.dims.y });
}

pub fn deinit(self: *TileMap) void {
    if (!self.initted) return;
    self.tiles.clearAndFree();
    self.initted = false;
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

pub fn getTileNeighborsPassable(self: *const TileMap, coord: V2i) std.EnumArray(NeighborDir, bool) {
    var ret: std.EnumArray(NeighborDir, bool) = undefined;
    for (neighbor_dirs) |nd| {
        const neighbor_coord = coord.add(neighbor_dirs_coords.get(nd));
        const tile = self.tiles.get(neighbor_coord);
        const passable = if (tile) |t| t.passable else true;
        ret.set(nd, passable);
    }
    return ret;
}

pub fn findPathAStar(self: *const TileMap, allocator: std.mem.Allocator, start: V2f, goal: V2f) Error!std.BoundedArray(V2f, 32) {
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
            if (self.tiles.get(posToTileCoord(next_p))) |tile| {
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

pub fn tileCoordIsPassable(self: *const TileMap, coord: V2i) bool {
    if (self.tiles.get(coord)) |tile| {
        return tile.passable;
    }
    return true;
}

pub fn isLOSBetweenThicc(self: *const TileMap, a: V2f, b: V2f, thickness: f32) bool {
    const a_to_b = a.sub(b);
    const n = a_to_b.rot90CW().normalized();
    const offset = n.scale(thickness * 0.5);
    const a_right = a.add(offset);
    const b_right = b.add(offset);
    const a_left = a.sub(offset);
    const b_left = b.sub(offset);
    return self.isLOSBetween(a_right, b_right) and self.isLOSBetween(a_left, b_left);
}

pub fn isLOSBetween(self: *const TileMap, _a: V2f, _b: V2f) bool {
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
        if (!self.tileCoordIsPassable(curr)) return false;
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
    return true;
}

pub fn findPathThetaStar(self: *const TileMap, allocator: std.mem.Allocator, start: V2f, goal: V2f, radius: f32, coords_searched: *std.ArrayList(V2i)) Error!std.BoundedArray(V2f, 32) {
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
    const start_coord = posToTileCoord(start);
    const goal_coord = posToTileCoord(goal);

    if (self.tiles.get(goal_coord)) |goal_tile| {
        if (!goal_tile.passable) {
            return .{};
        }
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
        .f = start.sub(goal).length(),
    });
    try seen.put(
        start_coord,
        .{
            .visited = false,
            .prev = null,
            .best_g = 0,
        },
    );
    coords_searched.clearAndFree();

    while (queue.items.len > 0) {
        const curr = queue.remove();
        const curr_seen = seen.getPtr(curr.p).?;
        if (curr_seen.visited) continue;
        curr_seen.visited = true;
        try coords_searched.append(curr.p);

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
            if (!self.tileCoordIsPassable(next_coord)) continue;
            const entry = try seen.getOrPut(next_coord);
            if (entry.found_existing and entry.value_ptr.visited) continue;
            const next_pos = if (next_coord.eql(goal_coord)) goal else tileCoordToCenterPos(next_coord);

            var this_move_cost = tile_sz_f;
            var prev = curr.p;
            var prev_g = curr.g;
            if (parent_stuff) |parent| {
                const parent_to_next = next_pos.sub(parent.pos);
                const n = parent_to_next.rot90CW().normalized();
                const offset = n.scale(radius);
                const a_right = parent.pos.add(offset);
                const b_right = next_pos.add(offset);
                const a_left = parent.pos.sub(offset);
                const b_left = next_pos.sub(offset);
                if (self.isLOSBetween(a_right, b_right) and self.isLOSBetween(a_left, b_left)) {
                    this_move_cost = parent_to_next.length();
                    prev = parent.coord;
                    prev_g = parent.seen.best_g;
                }
            }
            const next_g = prev_g + this_move_cost;
            const next = ThetaStar.PqEl{
                .p = next_coord,
                .g = next_g,
                .f = next_g + next_pos.sub(goal).length(),
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
    var ret = std.BoundedArray(V2f, 32){};
    if (seen.get(goal_coord) == null) {
        return ret;
    }
    if (start_coord.eql(goal_coord)) {
        ret.append(start) catch unreachable;
        ret.append(goal) catch unreachable;
        return ret;
    }
    {
        var curr = goal_coord;
        while (!curr.eql(start_coord)) {
            try path_arr.append(tileCoordToCenterPos(curr));
            curr = seen.get(curr).?.prev.?;
        }
        try path_arr.append(start);
        path_arr.items[0] = goal;
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
        plat.linef(p0, p1, line_thickness, Colorf.green);
    }
}

pub fn debugDrawGrid(_: *const TileMap, camera: draw.Camera2D) Error!void {
    const plat = getPlat();
    const inv_zoom = 1 / camera.zoom;
    const camera_dims = plat.screen_dims_f.scale(inv_zoom);
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
        plat.linef(v2f(x, grid_topleft.y), v2f(x, grid_botright.y), line_thickness, Colorf.green.fade(0.5));
    }
    for (0..grid_rows) |row| {
        const y: f32 = grid_topleft.y + utl.as(f32, row) * tile_sz;
        plat.linef(v2f(grid_topleft.x, y), v2f(grid_botright.x, y), line_thickness, Colorf.green.fade(0.5));
    }
}

pub fn debugDraw(self: *const TileMap) Error!void {
    const plat = getPlat();
    for (self.tiles.values()) |tile| {
        const color = if (tile.passable) Colorf.darkgray else Colorf.gray;
        plat.rectf(tileCoordToPos(tile.coord), tile_dims, .{ .fill_color = color });
    }
    plat.rectf(self.start_zone.pos, self.start_zone.dims, .{ .fill_color = Colorf.red.fade(0.2) });
    plat.rectf(self.end_zone.pos, self.end_zone.dims, .{ .fill_color = Colorf.blue.fade(0.2) });
}
