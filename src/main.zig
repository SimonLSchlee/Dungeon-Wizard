const std = @import("std");
const assert = std.debug.assert;
const u = @import("util.zig");

pub const Platform = @import("raylib.zig");
const core = @import("core.zig");

pub fn main() !void {
    var plat = try Platform.init(1280, 960, "boidsu");
    defer plat.closeWindow();
    try plat.run();
}
