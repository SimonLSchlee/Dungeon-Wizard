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
const Fog = @This();

const Map = std.AutoArrayHashMap(V2i, State);

const TileSizes = struct {
    sz: i32,
    sz_f: f32,
    dims: V2f,
    dims_2: V2f,

    pub fn init(sz: i32) TileSizes {
        return .{
            .sz = sz,
            .sz_f = sz,
            .dims = V2f.splat(sz),
            .dims_2 = V2f.splat(sz).scale(0.5),
        };
    }
};

const world_tiles = TileSizes.init(16);
//const screen_tiles = TileSizes.init(32);

const State = enum {
    unseen,
    visited,
    visible,
};

visited: Map = undefined,
render_tex: Platform.RenderTexture2D = undefined,

pub fn init() Error!Fog {
    const plat = getPlat();
    return .{
        .visited = Map.init(plat.heap),
        .render_tex = plat.createRenderTexture("fog", core.native_dims),
    };
}

pub fn deinit(self: *Fog) void {
    const plat = getPlat();
    self.visited.clearAndFree();
    plat.destroyRenderTexture(self.render_tex);
}

pub fn posToTileCoord(pos: V2f, tile_sz_f: f32) V2i {
    return .{
        .x = utl.as(i32, @floor(pos.x / tile_sz_f)),
        .y = utl.as(i32, @floor(pos.y / tile_sz_f)),
    };
}

pub fn tileCoordToPos(coord: V2i, tile_sz: i32) V2f {
    return coord.scale(tile_sz).toV2f();
}

pub fn posToTileTopLeft(pos: V2f, tile_sz: i32) V2f {
    return tileCoordToPos(posToTileCoord(pos, utl.as(f32, tile_sz)), tile_sz);
}

pub fn tileCoordToCenterPos(coord: V2i, tile_sz: i32, tile_dims_2: V2f) V2f {
    return tileCoordToPos(coord, tile_sz).add(tile_dims_2);
}

pub fn clearAll(self: *Fog) void {
    self.visited.clearRetainingCapacity();
}

pub fn clearVisible(self: *Fog) void {
    for (self.visited.values()) |*v| {
        if (v.* == .visible) v.* = .visited;
    }
}

pub fn addVisiblePoly(self: *Fog, room_rect: geom.Rectf, points: []const V2f) Error!void {
    if (points.len < 3) return;
    var topleft = points[0];
    var botright = points[0];
    for (points) |p| {
        topleft.x = @min(p.x, topleft.x);
        topleft.y = @min(p.y, topleft.y);
        botright.x = @max(p.x, botright.x);
        botright.y = @max(p.y, botright.y);
    }
    const tl_coord = posToTileCoord(topleft, world_tiles.sz_f);
    const br_coord = posToTileCoord(botright, world_tiles.sz_f);
    const right_x = tileCoordToPos(br_coord, world_tiles.sz).x + world_tiles.sz_f * 2;
    var coord = v2i(tl_coord.x, tl_coord.y);
    while (coord.y < br_coord.y) {
        while (coord.x < br_coord.x) {
            defer coord.x += 1;
            const center_pos = tileCoordToCenterPos(coord, world_tiles.sz, world_tiles.dims_2);
            if (!geom.pointIsInRectf(center_pos, room_rect)) continue;
            const v = v2f(right_x, center_pos.y);
            var num_intersections: usize = 0;
            for (points, 0..) |curr_p, i| {
                const next_p = points[(i + 1) % points.len];
                const line_seg_v = next_p.sub(curr_p);
                const intersect: bool = switch (geom.lineSegsIntersect(curr_p, line_seg_v, center_pos, v)) {
                    .intersection => true,
                    .colinear => |c| (c != null),
                    .none => false,
                };
                if (intersect) num_intersections += 1;
            }
            if (num_intersections % 2 == 1) {
                try self.visited.put(coord, .visible);
            }
        }
        coord.y += 1;
        coord.x = tl_coord.x;
    }
}

pub fn addVisibleCircle(self: *Fog, room_rect: geom.Rectf, pos: V2f, radius: f32) Error!void {
    assert(radius >= 0);
    const center_coord = posToTileCoord(pos, world_tiles.sz_f);
    const radius_i: i32 = utl.as(i32, @floor(radius / world_tiles.sz_f));
    const tl_offset = V2i.splat(radius_i);
    const tl_coord = center_coord.sub(tl_offset);
    const br_coord = center_coord.add(tl_offset);
    //std.debug.print("{any}\n", .{bl_coord.sub(tl_coord)});
    var coord = tl_coord;

    while (coord.y < br_coord.y) {
        while (coord.x < br_coord.x) {
            // TODO this is slow but w/e
            const tile_center_pos = tileCoordToCenterPos(coord, world_tiles.sz, world_tiles.dims_2);
            if (geom.pointIsInRectf(tile_center_pos, room_rect)) {
                const dist = tile_center_pos.dist(pos);
                if (dist <= radius) {
                    try self.visited.put(coord, .visible);
                }
            }
            coord.x += 1;
        }
        coord.y += 1;
        coord.x = tl_coord.x;
    }
}

pub fn renderToTexture(self: *const Fog, camera: draw.Camera2D) Error!void {
    const plat = getPlat();
    plat.startRenderToTexture(self.render_tex);
    plat.clear(Colorf.blank);
    plat.setBlend(.render_tex_alpha);
    plat.startCamera2D(camera);

    // TODO this works like the tilemap grid drawing for now, needs changing for blurring etc
    const inv_zoom = 1 / camera.zoom;
    const camera_dims = self.render_tex.texture.dims.toV2f().scale(inv_zoom);

    // add 2 to dims to make sure it covers the screen
    const world_screen_dims = camera_dims.scale(1 / world_tiles.sz_f).toV2i().add(v2i(2, 2));
    //std.debug.print("{any}\n", .{world_screen_dims});
    const world_screen_cols = utl.as(usize, world_screen_dims.x);
    const world_screen_rows = utl.as(usize, world_screen_dims.y);
    // go a tile beyond to make sure grid covers screen
    const topleft = posToTileTopLeft(camera.pos.sub(camera_dims.scale(0.5).add(world_tiles.dims)), world_tiles.sz_f);

    for (0..world_screen_rows) |r| {
        for (0..world_screen_cols) |c| {
            const offset = V2i.iToV2i(usize, c, r).toV2f().scale(world_tiles.sz_f);
            const world_pos = topleft.add(offset);
            const world_coord = posToTileCoord(world_pos, world_tiles.sz_f);
            //std.debug.print("world_coord {any}\n", .{world_coord});

            const color: ?Colorf = if (self.visited.get(world_coord)) |v|
                switch (v) {
                    .unseen => Colorf.black,
                    .visited => Colorf.black.fade(0.6),
                    .visible => null,
                }
            else
                Colorf.black;

            if (color) |col| {
                plat.rectf(world_pos, world_tiles.dims, .{ .fill_color = col });
            }
        }
    }

    plat.endCamera2D();
    plat.endRenderToTexture();
}
