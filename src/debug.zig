const std = @import("std");
const utl = @import("util.zig");
const core = @import("core.zig");
const Error = core.Error;
const App = @import("App.zig");
const DateTime = @import("DateTime.zig");
const config = @import("config");

pub const assert = std.debug.assert;

pub const enable_debug_controls = false;

// ai stuff
pub const show_thing_paths = false;
pub const show_thing_coords_searched = false;
pub const show_ai_decision = false;
pub const show_hiding_places = false;

// various Room stuff
pub const show_thing_collisions = false;
pub const show_tilemap_grid = false;
pub const show_hitboxes = false;
pub const show_selectable = false;
pub const show_waves = false;

// stats n whatnot
pub const show_num_enemies = false;
pub const show_highest_num_things_in_room = false;

pub const LogLevel = enum {
    debug,
    info,
    warn,
    err,
    crit,

    pub fn format(self: LogLevel, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) Error!void {
        _ = fmt;
        _ = options;
        var buf: [8]u8 = undefined;
        const s = utl.enumToString(LogLevel, self);
        const s_upper = std.ascii.upperString(&buf, s);
        writer.print("{s}", .{s_upper}) catch return Error.FormatFail;
    }
};

pub fn logRawBytes(bytes: []const u8) void {
    // file
    const plat = App.getPlat();
    plat.debugLogBytes(bytes);
    // stderr
    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    const stderr = std.io.getStdErr().writer();
    nosuspend stderr.writeAll(bytes) catch {};
}

pub fn logRaw(comptime fmt: []const u8, args: anytype) void {
    const plat = App.getPlat();
    // TODO does this actually truncate?
    const msg = std.fmt.bufPrint(plat.str_fmt_buf, fmt, args) catch plat.str_fmt_buf;
    logRawBytes(msg);
}

pub fn logLevel(level: LogLevel, comptime fmt: []const u8, args: anytype) void {
    const plat = App.getPlat();

    const pre = std.fmt.bufPrint(plat.str_fmt_buf, "[{any}] {any} ", .{ level, DateTime.getUTC() }) catch "[FMT ERR]";
    plat.debugLogBytes(pre);
    const msg = std.fmt.bufPrint(plat.str_fmt_buf, fmt, args) catch plat.str_fmt_buf;
    plat.debugLogBytes(msg);
    plat.debugLogBytes("\n");

    var smol_buf: [10]u8 = undefined;
    const stderr_pre = std.fmt.bufPrint(&smol_buf, "[{any}] ", .{level}) catch unreachable;
    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    const stderr = std.io.getStdErr().writer();
    nosuspend stderr.writeAll(stderr_pre) catch {};
    nosuspend stderr.writeAll(msg) catch {};
    nosuspend stderr.writeAll("\n") catch {};
}

pub fn debug(comptime fmt: []const u8, args: anytype) void {
    logLevel(.debug, fmt, args);
}

pub fn info(comptime fmt: []const u8, args: anytype) void {
    logLevel(.info, fmt, args);
}

pub fn warn(comptime fmt: []const u8, args: anytype) void {
    logLevel(.warn, fmt, args);
}

pub fn err(comptime fmt: []const u8, args: anytype) void {
    logLevel(.err, fmt, args);
}

pub fn crit(comptime fmt: []const u8, args: anytype) void {
    logLevel(.crit, fmt, args);
}

pub fn errorAndStackTrace(e: anytype) void {
    logRaw("ERROR: {any}\n", .{e});
    var stack_trace: std.builtin.StackTrace = undefined;
    std.debug.captureStackTrace(null, &stack_trace);
    logRaw("{any}\n", .{stack_trace});
}
