const std = @import("std");
const utl = @import("util.zig");
const core = @import("core.zig");
const Error = core.Error;
const DateTime = @import("DateTime.zig");
const config = @import("config");
const Log = @This();

pub const assert = std.debug.assert;

pub const fmt_buf_size = 4096;
const curr_log_name = "debug-log.txt";
const prev_log_name = "old-debug-log.txt";

pub fn GlobalInterface(getter: fn () *Log) type {
    return struct {
        pub inline fn putBytes(buf: []const u8) void {
            getter().putBytes(buf);
        }
        pub inline fn raw(comptime fmt: []const u8, args: anytype) void {
            getter().raw(fmt, args);
        }
        pub inline fn level(lev: Level, comptime fmt: []const u8, args: anytype) void {
            getter().level(lev, fmt, args);
        }
        pub inline fn debug(comptime fmt: []const u8, args: anytype) void {
            getter().debug(fmt, args);
        }

        pub inline fn info(comptime fmt: []const u8, args: anytype) void {
            getter().info(fmt, args);
        }

        pub inline fn warn(comptime fmt: []const u8, args: anytype) void {
            getter().warn(fmt, args);
        }

        pub inline fn err(comptime fmt: []const u8, args: anytype) void {
            getter().err(fmt, args);
        }

        pub inline fn fatal(comptime fmt: []const u8, args: anytype) void {
            getter().fatal(fmt, args);
        }
        pub fn stackTrace() void {
            getter().stackTrace();
        }
        pub fn errorAndStackTrace(e: anytype) void {
            getter().errorAndStackTrace(e);
        }
    };
}

pub const Level = enum {
    debug,
    info,
    warn,
    err,
    fatal,

    pub fn format(self: Level, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) Error!void {
        _ = fmt;
        _ = options;
        var buf: [8]u8 = undefined;
        const s = utl.enumToString(Level, self);
        const s_upper = std.ascii.upperString(&buf, s);
        writer.print("{s}", .{s_upper}) catch return Error.FormatFail;
    }
};

fmt_buf: []u8 = undefined,
logfile: ?std.fs.File = undefined,

pub fn init(dir: std.fs.Dir, allocator: std.mem.Allocator) !Log {
    var ret = Log{};
    ret.fmt_buf = try allocator.alloc(u8, fmt_buf_size);

    // rename old log
    const maybe_stat: ?std.fs.Dir.Stat = dir.statFile(curr_log_name) catch null;
    if (maybe_stat) |stat| {
        if (stat.kind == .file) {
            try dir.rename(curr_log_name, prev_log_name);
        } else {
            // TODO
            @panic("idk what to do");
        }
    }
    ret.logfile = try dir.createFile(curr_log_name, .{});

    return ret;
}

pub fn putBytes(self: *Log, buf: []const u8) void {
    // file
    if (self.logfile) |file| {
        file.writeAll(buf) catch |e| {
            std.debug.print("WRITE ERROR: {any}\n", .{e});
        };
        file.sync() catch |e| {
            std.debug.print("SYNC ERROR: {any}\n", .{e});
        };
    }
    // stderr
    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    const stderr = std.io.getStdErr().writer();
    nosuspend stderr.writeAll(buf) catch {};
}

pub fn raw(self: *Log, comptime fmt: []const u8, args: anytype) void {
    // TODO does this actually truncate?
    const msg = std.fmt.bufPrint(self.fmt_buf, fmt, args) catch self.fmt_buf;
    self.putBytes(msg);
}

pub fn level(self: *Log, lev: Level, comptime fmt: []const u8, args: anytype) void {
    const pre = std.fmt.bufPrint(self.fmt_buf, "[{any}] {any} ", .{ lev, DateTime.getUTC() }) catch "[FMT ERR]";
    const msg = std.fmt.bufPrint(self.fmt_buf[pre.len..], fmt, args) catch self.fmt_buf[pre.len..];
    var len = pre.len + msg.len;
    assert(len <= self.fmt_buf.len);
    if (len == self.fmt_buf.len) {
        self.fmt_buf[self.fmt_buf.len - 1] = '\n';
    } else {
        self.fmt_buf[len] = '\n';
        len += 1;
    }
    self.putBytes(self.fmt_buf[0..len]);
}

pub inline fn debug(self: *Log, comptime fmt: []const u8, args: anytype) void {
    self.level(.debug, fmt, args);
}

pub inline fn info(self: *Log, comptime fmt: []const u8, args: anytype) void {
    self.level(.info, fmt, args);
}

pub inline fn warn(self: *Log, comptime fmt: []const u8, args: anytype) void {
    self.level(.warn, fmt, args);
}

pub inline fn err(self: *Log, comptime fmt: []const u8, args: anytype) void {
    self.level(.err, fmt, args);
}

pub inline fn fatal(self: *Log, comptime fmt: []const u8, args: anytype) void {
    self.level(.fatal, fmt, args);
}

pub fn stackTrace(self: *Log) void {
    var stack_trace: std.builtin.StackTrace = undefined;
    std.debug.captureStackTrace(null, &stack_trace);
    self.raw("{any}\n", .{stack_trace});
}

pub fn errorAndStackTrace(self: *Log, e: anytype) void {
    self.raw("ERROR: {any}\n", .{e});
    self.stackTrace();
}
