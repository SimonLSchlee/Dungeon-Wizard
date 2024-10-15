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

const App = @import("App.zig");
const Run = @import("Run.zig");
const Data = @import("Data.zig");
const Options = @This();

pub const CastMethod = enum {
    left_click,
    quick_press,
    quick_release,
};

cast_method: CastMethod = .quick_release,

pub fn writeToTxt(self: Options) void {
    const options_file = std.fs.cwd().createFile("options.txt", .{}) catch {
        std.log.warn("WARNING: Failed to open options.txt for writing\n", .{});
        return;
    };
    defer options_file.close();
    inline for (std.meta.fields(Options)) |field| {
        switch (@typeInfo(field.type)) {
            .@"enum" => |info| {
                options_file.writeAll("# Possible values:\n") catch {};
                inline for (info.fields) |efield| {
                    const e = utl.bufPrintLocal("# {s}\n", .{efield.name}) catch break;
                    options_file.writeAll(e) catch {};
                }
                const val_as_string = @tagName(@field(self, field.name));
                const line = utl.bufPrintLocal("{s}={s}\n", .{ field.name, val_as_string }) catch break;
                options_file.writeAll(line) catch break;
            },
            else => continue,
        }
    }
}

pub fn initEmpty() Options {
    const ret = Options{};
    ret.writeToTxt();
    return ret;
}

fn trySetFromKeyVal(self: *Options, key: []const u8, val: []const u8) void {
    inline for (std.meta.fields(Options)) |field| {
        if (std.mem.eql(u8, key, field.name)) {
            switch (@typeInfo(field.type)) {
                .@"enum" => {
                    if (std.meta.stringToEnum(field.type, val)) |v| {
                        @field(self, field.name) = v;
                    }
                    return;
                },
                else => continue,
            }
        }
    }
    std.log.warn("WARNING: Options parse fail. key: \"{s}\", val: \"{s}\"\n", .{ key, val });
}

pub fn initTryLoad() Options {
    const plat = App.getPlat();
    var ret = Options{};
    const options_file = std.fs.cwd().openFile("options.txt", .{}) catch return initEmpty();
    const str = options_file.readToEndAlloc(plat.heap, 1024 * 1024) catch return initEmpty();
    defer plat.heap.free(str);
    var line_it = std.mem.tokenizeScalar(u8, str, '\n');
    while (line_it.next()) |line_untrimmed| {
        const line = std.mem.trim(u8, line_untrimmed, &std.ascii.whitespace);
        if (line[0] == '#') continue;
        var equals_it = std.mem.tokenizeScalar(u8, line, '=');
        const key = equals_it.next() orelse continue;
        const val = equals_it.next() orelse continue;
        ret.trySetFromKeyVal(key, val);
    }
    options_file.close();
    ret.writeToTxt();
    return ret;
}
