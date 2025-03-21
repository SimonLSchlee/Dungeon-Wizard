const std = @import("std");
const assert = std.debug.assert;
const u = @import("util.zig");

pub const Platform = @import("raylib.zig");
const core = @import("core.zig");

var _plat: ?*Platform = null;

pub fn main() !void {
    _plat = try Platform.init("Dungeon Wizard");
    if (_plat) |plat| {
        defer plat.closeWindow();
        try plat.run();
    }
}

// Note this handler is for the executable's root module
// It will only run for static builds or if a panic occurs in platform code
pub const panic = std.debug.FullPanic(
    struct {
        fn panic(msg: []const u8, first_trace_addr: ?usize) noreturn {
            Platform.panic(_plat, msg, first_trace_addr);
        }
    }.panic,
);
