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
const TileMap = @import("TileMap.zig");
const App = @import("App.zig");
const Tile = TileMap.Tile;
const PackedRoom = @This();

pub const ThingSpawn = struct {
    kind: Thing.Kind,
    pos: V2f,
};

pub const WavePositionsArray = std.BoundedArray(V2f, 16);

pub const tile_sz: i64 = 64;
pub const tile_sz_f: f32 = tile_sz;
pub const tile_dims = V2f.splat(tile_sz);
pub const tile_dims_2 = V2f.splat(tile_sz_f * 0.5);

exits: std.BoundedArray(V2f, 8) = .{},
waves: [10]WavePositionsArray = .{.{}} ** 10,
thing_spawns: std.BoundedArray(ThingSpawn, 64) = .{},
tiles: std.BoundedArray(Tile, 1024) = .{},
dims: V2f = .{},

pub fn init(str: []const u8) Error!PackedRoom {
    var ret = PackedRoom{};

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
            const curr_pos = TileMap.tileCoordToCenterPos(curr_coord);
            switch (ch) {
                '#' => {
                    try ret.tiles.append(.{
                        .coord = curr_coord,
                        .passable = false,
                    });
                },
                '&' => {
                    try ret.exits.append(curr_pos);
                },
                else => {
                    if (std.ascii.isDigit(ch)) {
                        const idx = std.fmt.parseInt(usize, &.{ch}, 10) catch unreachable;
                        ret.waves[idx].append(curr_pos) catch std.log.warn("Out of waves!", .{});
                    } else {
                        const data = App.get().data;
                        for (data.char_to_thing.constSlice()) |s| {
                            if (ch == s.ch) {
                                ret.thing_spawns.append(.{ .kind = s.kind, .pos = curr_pos }) catch std.log.warn("Out of spawns!", .{});
                                break;
                            }
                        }
                    }
                },
            }
            curr_coord.x += 1;
        }
        curr_coord.y += 1;
        curr_coord.x = topleft.x;
    }
    ret.dims = size.toV2f().scale(TileMap.tile_sz_f);
    std.debug.print("Loaded tilemap:\n size: {} x {}\n dims (px): {d:0.1} x {d:0.1}\n", .{ size.x, size.y, ret.dims.x, ret.dims.y });

    return ret;
}
