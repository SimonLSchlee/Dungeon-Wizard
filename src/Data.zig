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
const Thing = @import("Thing.zig");
const Room = @import("Room.zig");
const Data = @This();

const test_levels = [_][]const u8{
    \\#########################
    \\#                       #
    \\#                       #
    \\#                       #
    \\#                       #
    \\#                       #
    \\#       p   t           #
    \\#                       #
    \\#                       #
    \\#                       #
    \\#                       #
    \\#                       #
    \\#########################
    ,
    \\#######################################################
    \\##           ###    ##          ####                 ##
    \\#         ##  #          # ##   #       ####    ### ###
    \\####     ##   #         ####        # ####           ##
    \\#######  t      ##      #                       #######
    \\#AAAAA##         ####      #####     ##      ####BBBBB#
    \\#AAAAA p     #         ########      #   #   ####BBBBB#
    \\#AAAAA    #    ##   ############     #####       BBBBB#
    \\#AAAAA##    #   #      ########     ##           BBBBB#
    \\#AAAAA##    ##     ##     ### ##  ##         ####BBBBB#
    \\#######     ###            #       # # ###   ##########
    \\####  #   #         ##        #        ##      ########
    \\#      #  ##     ### ##     ###   ##     #            #
    \\#   #           #     ##     ####  ####        #    ###
    \\#######################################################
    ,
};

levels: []const []const u8 = undefined,
things: std.EnumMap(Thing.Kind, Thing) = undefined,

pub fn init() Error!*Data {
    const plat = App.getPlat();
    const data = plat.heap.create(Data) catch @panic("Out of memory");
    data.* = .{};
    try data.reload();
    return data;
}

pub fn loadSprites(_: *Data) Error!void {
    const plat = App.getPlat();
    var creature = std.fs.cwd().openDir("assets/images/creature", .{ .iterate = true }) catch return Error.FileSystemFail;
    defer creature.close();
    var walker = try creature.walk(plat.heap);
    defer walker.deinit();
    while (walker.next() catch return Error.FileSystemFail) |w| {
        if (std.mem.endsWith(u8, w.basename, ".json")) {
            var f = creature.openFile(w.basename, .{}) catch return Error.FileSystemFail;
            const s = f.readToEndAlloc(plat.heap, 8 * 1024 * 1024) catch return Error.FileSystemFail;
            //std.debug.print("{s}\n", .{s});
            var scanner = std.json.Scanner.initCompleteInput(plat.heap, s);
            const tree = std.json.Value.jsonParse(plat.heap, &scanner, .{ .max_value_len = s.len }) catch return Error.ParseFail;
            // TODO I guess tree just leaks rn? use arena?
            const frames = tree.object.get("frames").?.array;
            const meta = tree.object.get("meta").?.object;
            for (frames.items) |v| {
                v.dump();
            }
            meta.get("image").?.dump();
            meta.get("frameTags").?.dump();
            //const image_filename = meta.get("image").?.string;
            //const
        }
    }
}

pub fn reload(self: *Data) Error!void {
    loadSprites(self) catch std.debug.print("WARNING: failed to load all sprites\n", .{});
    self.levels = &test_levels;
    self.things = @TypeOf(self.things).init(
        .{
            .player = try @import("player.zig").protoype(),
            .troll = try @import("enemies.zig").troll(),
        },
    );
}
