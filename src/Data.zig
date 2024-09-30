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
    \\#       p   g           #
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
    \\#######  g      ##      #                       #######
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
things: std.EnumArray(Thing.Kind, Thing) = undefined,

pub fn init() Error!*Data {
    const plat = App.getPlat();
    const data = plat.heap.create(Data) catch @panic("Out of memory");
    data.* = .{};
    try data.reload();
    return data;
}

pub fn reload(self: *Data) Error!void {
    self.levels = &test_levels;
    self.things = @TypeOf(self.things).init(
        .{
            .player = try @import("Player.zig").protoype(),
            //.sheep = try @import("Sheep.zig").protoype(),
            .goat = try @import("Goat.zig").protoype(),
        },
    );
}
