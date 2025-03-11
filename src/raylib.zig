const std = @import("std");
const assert = std.debug.assert;
const debug = @import("debug.zig");
const Platform = @This();
const Log = @import("Log.zig");
const u = @import("util.zig");
const r = @cImport({
    @cInclude("raylib.h");
    @cInclude("rlgl.h");
});
const stdio = @cImport({
    @cDefine("_NO_CRT_STDIO_INLINE", "1");
    @cDefine("_GNU_SOURCE", {}); // needed for vsnprintf()
    @cInclude("stdio.h");
    @cUndef("_GNU_SOURCE");
});
const core = @import("core.zig");
const draw = @import("draw.zig");
const Error = core.Error;
const Key = core.Key;
const MouseButton = core.MouseButton;
const Coloru = draw.Coloru;
const Colorf = draw.Colorf;
const V2f = @import("V2f.zig");
const v2f = V2f.v2f;
const V2i = @import("V2i.zig");
const v2i = V2i.v2i;
const DateTime = @import("DateTime.zig");
const Options = @import("Options.zig");

const builtin = @import("builtin");
const config = @import("config");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var __plat: *Platform = undefined;

const str_fmt_buf_size = 4096;

pub const Font = struct {
    name: []const u8,
    base_size: u32,
    r_font: r.Font,
};

pub const Texture2D = struct {
    name: []const u8,
    dims: V2i,
    r_tex: r.Texture2D,
};

pub const RenderTexture2D = struct {
    name: []const u8,
    texture: Texture2D,
    r_render_tex: r.RenderTexture2D,
};

const OnScreenLogLine = u.BoundedString(256);

log: Log = undefined,
onscreen_log_buf_lines: std.BoundedArray(OnScreenLogLine, 32) = .{},
stack_base: usize = 0,
should_exit: bool = false,
app_dll: ?std.DynLib = null,
appInit: *const fn (*Platform) callconv(.C) *anyopaque = undefined,
appReload: *const fn (*anyopaque, *Platform) callconv(.C) void = undefined,
appTick: *const fn () callconv(.C) void = undefined,
appRender: *const fn () callconv(.C) void = undefined,
heap: std.mem.Allocator = undefined,
default_font: Font = undefined,

// screeeeen
screen_dims: V2i = .{},
screen_dims_f: V2f = .{},
// set when resolution changes
game_zoom_levels: f32 = 1,
game_scaling: f32 = 1,
game_canvas_dims: V2i = core.min_resolution,
game_canvas_dims_f: V2f = core.min_resolution.toV2f(),
game_canvas_screen_topleft_offset: V2f = .{},
// ui canvas size == screen size
ui_scaling: f32 = 1,

curr_cam: draw.Camera2D = .{},
accumulated_update_ns: i64 = 0,
prev_frame_time_ns: i64 = 0,
input_buffer: core.InputBuffer = .{},
str_fmt_buf: []u8 = undefined,
assets_path: []const u8 = undefined,
cwd_path: []const u8 = undefined,
user_data_path: []const u8 = undefined,

// move where the game is drawn so it's centered, e.g. if the UI is blocking some part of the screen
pub fn centerGameRect(self: *Platform, screen_rect_pos: V2f, screen_rect_dims: V2f) void {
    self.game_canvas_screen_topleft_offset = screen_rect_pos.add(screen_rect_dims.sub(self.game_canvas_dims_f.scale(self.game_scaling)).scale(0.5));
}

pub fn getWindowSize(_: *Platform) V2i {
    return v2i(r.GetScreenWidth(), r.GetScreenHeight());
}

pub fn setWindowSize(_: *Platform, dims: V2i) void {
    r.SetWindowSize(@intCast(dims.x), @intCast(dims.y));
}

pub fn setWindowPosition(_: *Platform, pos: V2i) void {
    r.SetWindowPosition(@intCast(pos.x), @intCast(pos.y));
}

pub fn getMonitorIdxAndDims(_: *Platform) struct { monitor: i32, dims: V2i } {
    const m = r.GetCurrentMonitor();
    const dims = v2i(r.GetMonitorWidth(m), r.GetMonitorHeight(m));
    return .{
        .monitor = m,
        .dims = dims,
    };
}

pub fn toggleFullscreen(_: *Platform) void {
    r.ToggleFullscreen();
}

pub fn toggleBorderlessWindowed(_: *Platform) void {
    r.ToggleBorderlessWindowed();
}

fn raylibTraceLog(msg_type: c_int, text: [*c]const u8, args: stdio.va_list) callconv(.C) void {
    const plat = getPlat();
    var fmt_buf: [1024]u8 = undefined;
    const len_i = stdio.vsnprintf(&fmt_buf, fmt_buf.len, text, args);
    if (len_i < 0) {
        plat.log.err("raylib failed to log message!", .{});
        plat.log.raw("{s}\n", .{text});
        return;
    }
    const len = u.as(usize, len_i);
    const maybe_log_level: ?Log.Level = switch (msg_type) {
        r.LOG_DEBUG => .debug,
        r.LOG_INFO => .info,
        r.LOG_WARNING => .warn,
        r.LOG_ERROR => .err,
        r.LOG_FATAL => .fatal,
        else => null,
    };
    if (maybe_log_level) |log_level| {
        plat.log.level(log_level, "[raylib] {s}", .{fmt_buf[0..len]});
    } else {
        plat.log.raw("[raylib] {s}", .{fmt_buf[0..len]});
    }
}

fn getPlat() *Platform {
    return __plat;
}

pub fn init(title: []const u8) Error!*Platform {
    @setRuntimeSafety(core.rt_safe_blocks);
    const heap = gpa.allocator();

    var ret = try heap.create(Platform);
    ret.* = .{};
    ret.heap = gpa.allocator();
    // need string buf to do following stuff
    ret.str_fmt_buf = try ret.heap.alloc(u8, str_fmt_buf_size);
    // need our cwd and assets path!
    try ret.findAssetsPath();
    try ret.findUserDataPath();
    // okay need logging
    var user_data_dir = std.fs.openDirAbsolute(ret.user_data_path, .{}) catch return Error.FileSystemFail;
    defer user_data_dir.close();
    ret.log = Log.init(user_data_dir, heap) catch |e| {
        std.debug.print("ERROR: init logger: {any}\n", .{e});
        return Error.FileSystemFail;
    };
    // okay main stuff is done
    ret.log.info("Allocated Platform: {}KiB\n", .{@sizeOf(Platform) / 1024});
    // useful if we want to compare it later
    ret.stack_base = ret.getStackPointer();

    // only useable by code statically linked to raylib.zig
    __plat = ret;

    r.SetTraceLogCallback(raylibTraceLog);
    const title_z = try std.fmt.allocPrintZ(ret.heap, "{s}", .{title});
    r.SetConfigFlags(r.FLAG_WINDOW_RESIZABLE);

    // v2i(1352, 878)
    // core.min_resolution.scale(1); //.add(v2i(32, 32));
    r.InitWindow(@intCast(core.min_resolution.x), @intCast(core.min_resolution.y), title_z);
    const options = Options.initTryLoad(ret);
    const option_dims = options.display.selected_resolution;
    Options.updateScreenDims(ret, option_dims, true);
    // show raylib init INFO, then just warnings
    r.SetTraceLogLevel(r.LOG_WARNING);

    ret.default_font = try ret.loadFont("Roboto-Regular.ttf"); // NOTE uses str_fmt_buf initialized above

    r.InitAudioDevice();
    r.SetExitKey(0);

    return ret;
}

pub fn closeWindow(_: *Platform) void {
    r.CloseWindow();
}

pub fn getStackPointer(_: *Platform) usize {
    return asm (""
        : [ret] "={sp}" (-> usize),
    );
}

pub fn printStackSize(self: *Platform) void {
    std.debug.print("stack size: {x}\n", .{self.stack_base - self.getStackPointer()});
}

const CF = @cImport({
    @cInclude("CFArray.h");
    @cInclude("CFBundle.h");
    @cInclude("CFURL.h");
    @cInclude("CFString.h");
});

const NSApplicationSupportDirectory = 14; // location of application support files (plug-ins, etc) (Library/Application Support)
const NSUserDomainMask = 1;
// this really returns a NSArray<NSString *>
// but it can be cast to CF.CFArrayRef
extern fn NSSearchPathForDirectoriesInDomains(directory: u64, domain_mask: u64, expand_tilde: i8) CF.CFArrayRef;

pub fn findUserDataPath(self: *Platform) Error!void {
    self.user_data_path = self.cwd_path; // default to current directory
    const dir_name = "Dungeon Wizard";
    if (config.is_release) {
        switch (builtin.os.tag) {
            .macos => {
                const c_buf: [*c]u8 = @ptrCast(self.str_fmt_buf);

                // NOTE this leaks the array. we don't care.
                const result = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, 1);
                const count = CF.CFArrayGetCount(result);
                if (count == 0) return;
                const first_string = CF.CFArrayGetValueAtIndex(result, 0);
                // NOTE this leaks the string. we don't care.
                if (CF.CFStringGetCString(@ptrCast(first_string), c_buf, u.as(c_long, self.str_fmt_buf.len), CF.kCFStringEncodingUTF8) == 0) {
                    return Error.OutOfMemory;
                }
                var len: usize = 0;
                while (len < self.str_fmt_buf.len and self.str_fmt_buf[len] != 0) {
                    len += 1;
                }
                self.user_data_path = std.fmt.allocPrint(self.heap, "{s}/{s}", .{ self.str_fmt_buf[0..len], dir_name }) catch return Error.OutOfMemory;
            },
            .windows => {
                if (std.process.getenvW(std.unicode.wtf8ToWtf16LeStringLiteral("APPDATA"))) |appdata_w16| {
                    const appdata = try std.unicode.wtf16LeToWtf8Alloc(self.heap, appdata_w16);
                    defer self.heap.free(appdata);
                    self.user_data_path = std.fmt.allocPrint(self.heap, "{s}\\{s}", .{ appdata, dir_name }) catch return Error.OutOfMemory;
                }
            },
            else => {},
        }
    }
    var cwd: std.fs.Dir = std.fs.cwd(); // can't close this
    cwd.makePath(self.user_data_path) catch return Error.FileSystemFail;
    std.debug.print("user_data_path: {s}\n", .{self.user_data_path});
}

pub fn findAssetsPath(self: *Platform) Error!void {
    var cwd_path_base: []const u8 = ".";
    if (config.is_release) {
        switch (builtin.os.tag) {
            .macos => {
                cwd_path_base = "../Resources/";
                // this doesn't work with app bundle, funnily enough...
                // launch.sh script to change working directory works fine
                if (false) {
                    // Zig thinks these are ? but they're just C pointers I guess
                    const bundle = CF.CFBundleGetMainBundle();
                    const cf_url = CF.CFBundleCopyResourcesDirectoryURL(bundle);
                    const cf_str_ref = CF.CFURLCopyFileSystemPath(cf_url, CF.kCFURLPOSIXPathStyle);
                    const c_buf: [*c]u8 = @ptrCast(self.str_fmt_buf);
                    if (CF.CFStringGetCString(cf_str_ref, c_buf, str_fmt_buf_size, CF.kCFStringEncodingASCII) != 0) {
                        const slice = std.mem.span(c_buf);
                        self.cwd_path = std.fs.realpathAlloc(self.heap, slice) catch return Error.OutOfMemory;
                        self.assets_path = try std.fmt.allocPrint(self.heap, "{s}/assets", .{self.cwd_path});
                        return;
                    } else {
                        return Error.NoSpaceLeft;
                    }
                    return Error.FileSystemFail;
                }
            },
            else => {},
        }
    }
    self.cwd_path = std.fs.realpathAlloc(self.heap, cwd_path_base) catch return Error.OutOfMemory;
    self.assets_path = try std.fmt.allocPrint(self.heap, "{s}/assets", .{self.cwd_path});
    std.debug.print("cwd_path: {s}\n", .{self.cwd_path});
}

pub fn setTargetFPS(_: *Platform, fps: u32) void {
    @setRuntimeSafety(core.rt_safe_blocks);
    r.SetTargetFPS(@intCast(fps));
}

pub fn getGameTimeNanosecs(_: *Platform) i64 {
    return u.as(i64, r.GetTime() * u.as(f64, core.ns_per_sec));
}

const app_dll_name = switch (builtin.os.tag) {
    .macos => "libgame.dylib",
    .windows => "game.dll",
    else => @compileError("missing app dll name"),
};

fn loadAppDll(self: *Platform) Error!void {
    const cwd_path = std.fs.cwd().realpath(".", self.str_fmt_buf) catch return error.RecompileFail;
    // weirdness note:
    // if there is no '/' character' in the dll path, then this doesn't work. Due to reasons.
    // dlopen manpage:
    // "
    // When path does not contain a slash character (i.e. it is just a leaf name), dlopen() will do searching.  If $DYLD_LIBRARY_PATH was set at launch, dyld will first look in that directory.  Next, if the calling mach-o file or the main
    // executable specify an LC_RPATH, then dyld will look in those directories. Next, if the process is unrestricted, dyld will search in the current working directory. Lastly, for old binaries, dyld will try some fallbacks.  If
    // $DYLD_FALLBACK_LIBRARY_PATH was set at launch, dyld will search in those directories, otherwise, dyld will look in /usr/local/lib/ (if the process is unrestricted), and then in /usr/lib/.
    // "
    // So it's finding the old dll somewhere in one of these search paths instead of the recompiled one!
    //
    self.app_dll = blk: for ([_][]const u8{ cwd_path, "zig-out/lib", "zig-out/bin" }) |path| {
        const app_dll_path = try std.fmt.bufPrint(self.str_fmt_buf[cwd_path.len..], "{s}/{s}", .{ path, app_dll_name });
        self.log.info("######### LOAD {s} ######", .{app_dll_path});
        break :blk std.DynLib.open(app_dll_path) catch |e| {
            self.log.warn("{s}: {any}", .{ app_dll_path, e });
            continue;
        };
    } else {
        @panic("Fail to load app dll");
    };
    var dll = self.app_dll.?;
    self.log.info("######### LOADED ######", .{});
    self.appInit = dll.lookup(@TypeOf(self.appInit), "appInit") orelse return error.LookupFail;
    self.appReload = dll.lookup(@TypeOf(self.appReload), "appReload") orelse return error.LookupFail;
    self.appTick = dll.lookup(@TypeOf(self.appTick), "appTick") orelse return error.LookupFail;
    self.appRender = dll.lookup(@TypeOf(self.appRender), "appRender") orelse return error.LookupFail;
}

fn unloadAppDll(self: *Platform) void {
    if (self.app_dll) |*dll| {
        self.log.info("######### UNLOAD ######", .{});
        dll.close();
        self.app_dll = null;
    }
}

fn recompileAppDll(self: *Platform) Error!void {
    const proc_args = [_][]const u8{
        "zig",
        "build",
        "-Dapp-only=true",
    };
    self.log.info("\n#### START RECOMPILE OUTPUT ####\n", .{});
    const result = std.process.Child.run(.{
        .allocator = self.heap,
        .argv = &proc_args,
    }) catch return Error.RecompileFail;

    self.log.info("stderr:\n{s}", .{result.stderr});
    self.log.info("stdout:\n{s}", .{result.stdout});
    self.log.info("#### END RECOMPILE OUTPUT ####\n", .{});
    self.heap.free(result.stderr);
    self.heap.free(result.stdout);
    switch (result.term) {
        .Exited => |exited| {
            if (exited != 0) return Error.RecompileFail;
        },
        else => return Error.RecompileFail,
    }
}

fn loadStaticApp(self: *Platform) void {
    const App = @import("App.zig");
    self.appInit = App.staticAppInit;
    self.appRender = App.staticAppRender;
    self.appTick = App.staticAppTick;
    self.appReload = App.staticAppReload;
}

fn drawOnScreenLog(self: *Platform) void {
    var y: f32 = 10;
    for (self.onscreen_log_buf_lines.constSlice()) |line| {
        const pos = v2f(10, y);
        const dims = self.measureText(line.constSlice(), .{}) catch continue;
        self.rectf(pos, dims, .{ .fill_color = Colorf.black.fade(0.5) });
        self.textf(pos, "{s}", .{line.constSlice()}, .{ .color = .white }) catch {};
        y += 20;
    }
    self.onscreen_log_buf_lines.clear();
}

pub fn run(self: *Platform) Error!void {
    @setRuntimeSafety(core.rt_safe_blocks);

    if (comptime config.static_lib) {
        self.loadStaticApp();
    } else {
        try self.loadAppDll();
    }

    const app = self.appInit(self);

    self.prev_frame_time_ns = @max(self.getGameTimeNanosecs() - core.fixed_ns_per_update, 0);
    r.SetConfigFlags(r.FLAG_VSYNC_HINT);
    const refresh_rate = u.as(i64, r.GetMonitorRefreshRate(r.GetCurrentMonitor()));
    const ns_per_refresh = @divTrunc(core.ns_per_sec, refresh_rate);
    const min_sleep_time_ns = 1500000;
    //std.debug.print("refresh rate: {}\n", .{refresh_rate});
    //std.debug.print("ns per refresh: {}\n", .{ns_per_refresh});
    var tick_count_sec: f32 = 0;
    var draw_count_sec: f32 = 0;
    var avg_ups: f32 = 0;
    var avg_fps: f32 = 0;
    var sec_time_ns: i64 = 0;

    while (!r.WindowShouldClose() and !self.should_exit) {
        if (!config.static_lib and !config.is_release and self.input_buffer.keyIsJustPressed(.f5)) {
            self.unloadAppDll();
            try self.recompileAppDll();
            try self.loadAppDll();
            self.appReload(app, self);
        }
        const curr_time_ns = self.getGameTimeNanosecs();
        var delta_ns = curr_time_ns - self.prev_frame_time_ns;
        self.prev_frame_time_ns = curr_time_ns;
        //std.debug.print("loop: {d:.5}\n", .{core.nsToSecs(delta_ns)});
        if (false) {
            for (0..5) |i| {
                const multiple_ns: i64 = refresh_rate * u.as(i64, i);
                if (@abs(delta_ns - multiple_ns) < core.fixed_update_fuzziness_ns) {
                    delta_ns = multiple_ns;
                    break;
                }
            }
        }

        self.accumulated_update_ns += delta_ns;
        if (self.accumulated_update_ns > core.fixed_max_accumulated_update_ns) {
            self.accumulated_update_ns = core.fixed_max_accumulated_update_ns;
        }

        if (false) {
            //const num_updates_to_do: i64 = @divTrunc(self.accumulated_update_ns, core.fixed_ns_per_update);
            //std.debug.print("{}", .{num_updates_to_do});
        }

        while (self.accumulated_update_ns >= core.fixed_ns_per_update_upper) {
            r.PollInputEvents();
            self.tickInputBuffer();
            self.appTick();
            tick_count_sec += 1;
            self.accumulated_update_ns -= core.fixed_ns_per_update_lower;
            if (self.accumulated_update_ns < core.fixed_ns_per_update_lower - core.fixed_ns_per_update_upper) {
                self.accumulated_update_ns = 0;
            }
        }
        if (debug.show_ups_fps) {
            self.onScreenLog("ups: {d:.3}", .{avg_ups});
            self.onScreenLog("fps: {d:.3}", .{avg_fps});
        }

        //const start_draw_ns = self.getGameTimeNanosecs();
        r.BeginDrawing();
        self.appRender();
        self.drawOnScreenLog();
        r.EndDrawing();
        draw_count_sec += 1;

        sec_time_ns += delta_ns;
        if (sec_time_ns >= core.ns_per_sec) {
            const sec_time_secs = core.nsToSecs(sec_time_ns);
            avg_fps = draw_count_sec / u.as(f32, sec_time_secs);
            avg_ups = tick_count_sec / u.as(f32, sec_time_secs);
            sec_time_ns = 0;
            draw_count_sec = 0;
            tick_count_sec = 0;
        }

        //const end_draw_ns = self.getGameTimeNanosecs();
        //std.debug.print("update: {d:.5}\n", .{core.nsToSecs(start_draw_ns - curr_time_ns)});
        //std.debug.print("draw: {d:.5}\n", .{core.nsToSecs(end_draw_ns - start_draw_ns)});
        r.SwapScreenBuffer();

        if (false) {
            const frame_time_ns = self.getGameTimeNanosecs() - curr_time_ns;
            const time_left_ns = ns_per_refresh - frame_time_ns;
            //std.debug.print("time left: {d:.5}\n", .{core.nsToSecs(time_left_ns)});
            if (time_left_ns > min_sleep_time_ns) {
                const sleep_time_ns = time_left_ns - min_sleep_time_ns;
                const sleep_time_secs = core.nsToSecs(sleep_time_ns);
                //std.debug.print("sleep: {d:.5}\n", .{sleep_time_secs});
                r.WaitTime(sleep_time_secs);
            }
        }
    }
}

pub fn onScreenLog(self: *Platform, comptime fmt: []const u8, args: anytype) void {
    const s = u.bufPrintLocal(fmt, args) catch return;
    self.onscreen_log_buf_lines.append(OnScreenLogLine.fromSlice(s) catch return) catch return;
}

const key_map = std.EnumArray(Key, c_int).init(.{
    .backtick = r.KEY_GRAVE,
    .space = r.KEY_SPACE,
    .apostrophe = r.KEY_APOSTROPHE,
    .comma = r.KEY_COMMA,
    .minus = r.KEY_MINUS,
    .period = r.KEY_PERIOD,
    .a = r.KEY_A,
    .b = r.KEY_B,
    .c = r.KEY_C,
    .d = r.KEY_D,
    .e = r.KEY_E,
    .f = r.KEY_F,
    .g = r.KEY_G,
    .h = r.KEY_H,
    .i = r.KEY_I,
    .j = r.KEY_J,
    .k = r.KEY_K,
    .l = r.KEY_L,
    .m = r.KEY_M,
    .n = r.KEY_N,
    .o = r.KEY_O,
    .p = r.KEY_P,
    .q = r.KEY_Q,
    .r = r.KEY_R,
    .s = r.KEY_S,
    .t = r.KEY_T,
    .u = r.KEY_U,
    .v = r.KEY_V,
    .w = r.KEY_W,
    .x = r.KEY_X,
    .y = r.KEY_Y,
    .z = r.KEY_Z,
    .zero = r.KEY_ZERO,
    .one = r.KEY_ONE,
    .two = r.KEY_TWO,
    .three = r.KEY_THREE,
    .four = r.KEY_FOUR,
    .five = r.KEY_FIVE,
    .six = r.KEY_SIX,
    .seven = r.KEY_SEVEN,
    .eight = r.KEY_EIGHT,
    .nine = r.KEY_NINE,
    .semicolon = r.KEY_SEMICOLON,
    .equals = r.KEY_EQUAL,
    .slash = r.KEY_SLASH,
    .backslash = r.KEY_BACKSLASH,
    .left = r.KEY_LEFT,
    .right = r.KEY_RIGHT,
    .up = r.KEY_UP,
    .down = r.KEY_DOWN,
    .escape = r.KEY_ESCAPE,
    .f1 = r.KEY_F1,
    .f2 = r.KEY_F2,
    .f3 = r.KEY_F3,
    .f4 = r.KEY_F4,
    .f5 = r.KEY_F5,
    .f6 = r.KEY_F6,
    .f7 = r.KEY_F7,
    .f8 = r.KEY_F8,
    .f9 = r.KEY_F9,
    .f10 = r.KEY_F10,
    .f11 = r.KEY_F11,
    .f12 = r.KEY_F12,
});

pub fn keyIsDown(_: *Platform, key: Key) bool {
    return r.IsKeyDown(key_map.get(key));
}

fn cColoru(color: Coloru) r.Color {
    return .{
        .r = color.r,
        .g = color.g,
        .b = color.b,
        .a = color.a,
    };
}

fn cColorf(color: Colorf) r.Color {
    return cColoru(color.toColoru());
}

fn cVec(v: V2f) r.Vector2 {
    return .{
        .x = v.x,
        .y = v.y,
    };
}

fn zVec(v: r.Vector2) V2f {
    return .{
        .x = v.x,
        .y = v.y,
    };
}

pub fn clear(_: *Platform, color: Colorf) void {
    r.ClearBackground(cColorf(color));
}

pub fn textf(self: *Platform, pos: V2f, comptime fmt: []const u8, args: anytype, opt: draw.TextOpt) Error!void {
    @setRuntimeSafety(core.rt_safe_blocks);
    const text_z = try std.fmt.bufPrintZ(self.str_fmt_buf, fmt, args);
    const font = if (opt.font) |f| f else self.default_font;
    const font_size_f: f32 = u.as(f32, opt.size);
    const text_width = r.MeasureTextEx(font.r_font, text_z, font_size_f, 0);
    var draw_pos: r.Vector2 = if (opt.center) .{
        .x = pos.x - u.as(f32, text_width.x) / 2,
        .y = pos.y - text_width.y / 2,
    } else cVec(pos);
    const r_filter = switch (opt.smoothing) {
        .none => blk: {
            break :blk r.TEXTURE_FILTER_POINT;
        },
        .bilinear => r.TEXTURE_FILTER_BILINEAR,
    };
    if (opt.round_to_pixel) {
        const inv = 1 / self.curr_cam.zoom;
        draw_pos.x = @round(draw_pos.x * self.curr_cam.zoom) * inv;
        draw_pos.y = @round(draw_pos.y * self.curr_cam.zoom) * inv;
    }
    r.SetTextureFilter(font.r_font.texture, r_filter);
    // outline
    if (opt.border) |border| {
        const offsets = [_]V2f{ v2f(0, 1), v2f(1, 0), v2f(0, -1), v2f(-1, 0) };
        for (offsets) |offset| {
            const p = r.Vector2{
                .x = draw_pos.x + offset.x * border.dist,
                .y = draw_pos.y + offset.y * border.dist,
            };
            r.DrawTextEx(
                font.r_font,
                text_z,
                p,
                font_size_f,
                0,
                cColorf(border.color),
            );
        }
    }
    r.DrawTextEx(
        font.r_font,
        text_z,
        draw_pos,
        font_size_f,
        0,
        cColorf(opt.color),
    );
}

pub fn measureText(self: *Platform, text: []const u8, opt: draw.TextOpt) Error!V2f {
    const text_z = try std.fmt.bufPrintZ(self.str_fmt_buf, "{s}", .{text});
    const font = if (opt.font) |f| f else self.default_font;
    const font_size_f: f32 = u.as(f32, opt.size);
    const sz = r.MeasureTextEx(font.r_font, text_z, font_size_f, 0);
    return zVec(sz);
}

pub fn linef(_: *Platform, start: V2f, end: V2f, opt: draw.LineOpt) void {
    var start_r = start;
    var end_r = end;
    if (opt.round_to_pixel) {
        start_r = start.round();
        end_r = end.round();
    }
    switch (opt.smoothing) {
        .bilinear => r.rlEnableSmoothLines(),
        .none => r.rlDisableSmoothLines(),
    }
    r.DrawLineEx(cVec(start_r), cVec(end_r), opt.thickness, cColorf(opt.color));
}

pub fn rectf(self: *Platform, topleft: V2f, dims: V2f, opt: draw.PolyOpt) void {
    var topleft_r = topleft;
    var dims_r = dims;
    if (opt.round_to_pixel) {
        topleft_r = topleft_r.scale(self.curr_cam.zoom).round().scale(1 / self.curr_cam.zoom);
        dims_r = dims_r.round();
    }
    const rec: r.Rectangle = .{
        .x = topleft_r.x,
        .y = topleft_r.y,
        .width = dims_r.x,
        .height = dims_r.y,
    };
    switch (opt.smoothing) {
        .bilinear => r.rlEnableSmoothLines(),
        .none => r.rlDisableSmoothLines(),
    }

    if (opt.fill_color) |color| {
        if (opt.edge_radius > 0) {
            r.DrawRectangleRounded(rec, opt.edge_radius, 10, cColorf(color));
        } else {
            r.DrawRectangleRec(rec, cColorf(color));
        }
    }
    if (opt.outline) |outline| {
        if (opt.edge_radius > 0) {
            r.DrawRectangleRoundedLinesEx(rec, opt.edge_radius, 10, outline.thickness, cColorf(outline.color));
        } else {
            r.DrawRectangleLinesEx(rec, outline.thickness, cColorf(outline.color));
        }
    }
}

pub fn circlef(self: *Platform, center: V2f, radius: f32, opt: draw.PolyOpt) void {
    var center_r = center;
    const radius_r = radius;
    if (opt.round_to_pixel) {
        center_r = center_r.scale(self.curr_cam.zoom).round().scale(1 / self.curr_cam.zoom);
        //radius_r = @round(radius);
    }

    switch (opt.smoothing) {
        .bilinear => r.rlEnableSmoothLines(),
        .none => r.rlDisableSmoothLines(),
    }

    if (opt.fill_color) |color| {
        r.DrawCircleV(cVec(center_r), radius_r, cColorf(color));
    }
    if (opt.outline) |outline| {
        r.DrawCircleLinesV(cVec(center_r), radius_r, cColorf(outline.color));
    }
}

pub fn sectorf(_: *Platform, center: V2f, radius: f32, start_ang_rads: f32, end_ang_rads: f32, opt: draw.PolyOpt) void {
    var center_r = center;
    var radius_r = radius;
    const segs = 20;
    const start_deg = u.radiansToDegrees(start_ang_rads);
    const end_deg = u.radiansToDegrees(end_ang_rads);

    switch (opt.smoothing) {
        .bilinear => r.rlEnableSmoothLines(),
        .none => r.rlDisableSmoothLines(),
    }

    if (opt.round_to_pixel) {
        center_r = center_r.round();
        radius_r = @round(radius_r);
    }
    if (opt.fill_color) |color| {
        r.DrawCircleSector(cVec(center_r), radius_r, start_deg, end_deg, segs, cColorf(color));
    }
    if (opt.outline) |outline| {
        r.DrawCircleSectorLines(cVec(center_r), radius_r, start_deg, end_deg, segs, cColorf(outline.color));
    }
}

pub fn ellipsef(self: *Platform, center: V2f, radii: V2f, opt: draw.PolyOpt) void {
    var pt_buf = std.BoundedArray(V2f, 38){};
    var center_r = center;
    if (opt.round_to_pixel) {
        center_r = center_r.scale(self.curr_cam.zoom).round().scale(1 / self.curr_cam.zoom);
    }
    // raylib's ellipse drawing, for SOME reason, doesn't get rounded properly, so use a triangle fan + line strip
    // center point at 0,0
    pt_buf.appendAssumeCapacity(.{});
    var i: f32 = 0;
    while (i <= 360) {
        const rads = -u.degreesToRadians(i);
        const pt = v2f(
            @cos(rads) * radii.x,
            @sin(rads) * radii.y,
        );
        pt_buf.appendAssumeCapacity(pt);
        i += 10;
    }
    if (opt.rot_rads != 0) {
        for (pt_buf.slice()) |*pt| {
            pt.* = pt.rotRadians(opt.rot_rads);
        }
    }
    for (pt_buf.slice()) |*pt| {
        pt.* = pt.add(center_r);
    }

    switch (opt.smoothing) {
        .bilinear => r.rlEnableSmoothLines(),
        .none => r.rlDisableSmoothLines(),
    }

    if (opt.fill_color) |color| {
        r.DrawTriangleFan(@ptrCast(pt_buf.constSlice()), u.as(c_int, pt_buf.len), cColorf(color));
    }
    if (opt.outline) |outline| {
        r.DrawLineStrip(@ptrCast(pt_buf.constSlice()[1..]), u.as(c_int, pt_buf.len - 1), cColorf(outline.color));
    }
}

pub fn trianglef(_: *Platform, points: [3]V2f, opt: draw.PolyOpt) void {
    var points_r = points;
    if (opt.round_to_pixel) {
        for (&points_r) |*p| {
            p.* = p.round();
        }
    }
    switch (opt.smoothing) {
        .bilinear => r.rlEnableSmoothLines(),
        .none => r.rlDisableSmoothLines(),
    }
    if (opt.fill_color) |color| {
        r.DrawTriangle(cVec(points_r[0]), cVec(points_r[1]), cVec(points_r[2]), cColorf(color));
    }
    if (opt.outline) |outline| {
        r.DrawTriangleLines(cVec(points_r[0]), cVec(points_r[1]), cVec(points_r[2]), cColorf(outline.color));
    }
}

pub fn arrowf(self: *Platform, base: V2f, point: V2f, opt: draw.LineOpt) void {
    assert(opt.thickness >= 0.001);

    switch (opt.smoothing) {
        .bilinear => r.rlEnableSmoothLines(),
        .none => r.rlDisableSmoothLines(),
    }

    const tri_height = opt.thickness * 2.3;
    const tri_width = opt.thickness * 2.5;
    const tri_width_2 = tri_width * 0.5;
    const v = point.sub(base);
    var total_len = v.length();
    if (@abs(total_len) < 0.001) {
        total_len = tri_height;
    }
    const dir = v.scale(1 / total_len);

    const line_len = @max(total_len - tri_height, 0);
    const line_v = dir.scale(line_len);
    const line_end = base.add(line_v);
    self.linef(base, line_end, opt);

    const tri_end = line_end.add(dir.scale(tri_height));
    const tri_edge_v = dir.scale(tri_width_2);
    const left_v = V2f{ .x = tri_edge_v.y, .y = -tri_edge_v.x };
    const right_v = V2f{ .x = -tri_edge_v.y, .y = tri_edge_v.x };
    self.trianglef(
        .{ line_end.add(left_v), line_end.add(right_v), tri_end },
        .{ .fill_color = opt.color, .round_to_pixel = opt.round_to_pixel },
    );
}

pub fn loadFont(self: *Platform, path: []const u8) Error!Font {
    @setRuntimeSafety(core.rt_safe_blocks);
    const path_z = try std.fmt.bufPrintZ(self.str_fmt_buf, "{s}/fonts/{s}", .{ self.assets_path, path });
    var r_font = r.LoadFontEx(path_z, 200, 0, 0);
    r.GenTextureMipmaps(&r_font.texture);
    const ret: Font = .{
        .name = path,
        .base_size = u.as(u32, r_font.baseSize),
        .r_font = r_font,
    };
    return ret;
}

pub fn loadPixelFont(self: *Platform, path: []const u8, sz: u32) Error!Font {
    @setRuntimeSafety(core.rt_safe_blocks);
    const path_z = try std.fmt.bufPrintZ(self.str_fmt_buf, "{s}/fonts/{s}", .{ self.assets_path, path });
    var r_font = if (std.mem.endsWith(u8, path, ".png")) r.LoadFont(path_z) else r.LoadFontEx(path_z, u.as(c_int, sz), 0, 0);
    if (!r.IsFontValid(r_font)) {
        return Error.FileSystemFail;
    }
    r.GenTextureMipmaps(&r_font.texture);
    const ret: Font = .{
        .name = path,
        .base_size = u.as(u32, r_font.baseSize),
        .r_font = r_font,
    };
    return ret;
}

pub fn loadTexture(self: *Platform, path: []const u8) Error!Texture2D {
    @setRuntimeSafety(core.rt_safe_blocks);
    const path_z = try std.fmt.bufPrintZ(self.str_fmt_buf, "{s}/{s}", .{ self.assets_path, path });
    const r_tex = r.LoadTexture(path_z);
    return .{
        .name = path,
        .dims = .{ .x = @intCast(r_tex.width), .y = @intCast(r_tex.height) },
        .r_tex = r_tex,
    };
}
pub fn unloadTexture(self: *Platform, texture: Texture2D) void {
    _ = self;
    r.UnloadTexture(texture.r_tex);
}

pub const ImageBuf = struct {
    dims: V2i,
    data: []Coloru,
    r_img: r.Image,
    r_colors: [*c]r.Color,
};

pub fn textureToImageBuf(_: *Platform, texture: Texture2D) ImageBuf {
    const r_img = r.LoadImageFromTexture(texture.r_tex);
    const r_colors = r.LoadImageColors(r_img);
    const dims = V2i.iToV2i(c_int, r_img.width, r_img.height);
    return .{
        .dims = dims,
        .data = @alignCast(@ptrCast(r_colors[0..u.as(usize, dims.x * dims.y)])),
        .r_img = r_img,
        .r_colors = r_colors,
    };
}

pub fn unloadImageBuf(_: *Platform, image_buf: ImageBuf) void {
    r.UnloadImageColors(image_buf.r_colors);
    r.UnloadImage(image_buf.r_img);
}

pub fn createRenderTexture(_: *Platform, name: []const u8, dims: V2i) RenderTexture2D {
    @setRuntimeSafety(core.rt_safe_blocks);
    const r_render_tex = r.LoadRenderTexture(@intCast(dims.x), @intCast(dims.y));
    const tex = Texture2D{
        .name = name,
        .dims = dims,
        .r_tex = r_render_tex.texture,
    };
    return .{
        .name = name,
        .texture = tex,
        .r_render_tex = r_render_tex,
    };
}

pub fn destroyRenderTexture(_: *Platform, tex: RenderTexture2D) void {
    r.UnloadRenderTexture(tex.r_render_tex);
}

pub fn texturef(self: *Platform, pos: V2f, tex: Texture2D, opt: draw.TextureOpt) void {
    @setRuntimeSafety(core.rt_safe_blocks);
    var src = r.Rectangle{
        .width = @floatFromInt(tex.dims.x),
        .height = @floatFromInt(tex.dims.y),
    };
    if (opt.src_pos) |p| {
        src.x = p.x;
        src.y = p.y;
    }
    if (opt.src_dims) |d| {
        src.width = d.x;
        src.height = d.y;
    }
    var pos_r = pos;
    if (opt.round_to_pixel) {
        pos_r = pos.scale(self.curr_cam.zoom).round().scale(1 / self.curr_cam.zoom);
    }
    var dest = r.Rectangle{
        .x = pos_r.x,
        .y = pos_r.y,
        .width = src.width * opt.uniform_scaling,
        .height = src.height * opt.uniform_scaling,
    };

    if (opt.scaled_dims) |d| {
        dest.width = d.x;
        dest.height = d.y;
    }
    if (opt.flip_x) {
        src.width = -src.width;
    }
    if (opt.flip_y) {
        src.height = -src.height;
    }
    //std.debug.print("{any}", .{dest});
    const origin = switch (opt.origin) {
        .topleft => V2f{},
        .center => blk: {
            const p = v2f(dest.width, dest.height).scale(0.5);
            if (opt.round_to_pixel) {
                break :blk p.round();
            }
            break :blk p;
        },
        .offset => |o| o.scale(opt.uniform_scaling),
    };
    const r_filter = switch (opt.smoothing) {
        .none => blk: {
            break :blk r.TEXTURE_FILTER_POINT;
        },
        .bilinear => r.TEXTURE_FILTER_BILINEAR,
    };
    r.SetTextureFilter(tex.r_tex, r_filter);
    r.DrawTexturePro(tex.r_tex, src, dest, cVec(origin), u.radiansToDegrees(opt.rot_rads), cColorf(opt.tint));
}

pub fn setBlend(_: *Platform, blend: draw.Blend) void {
    const r_val = blk: switch (blend) {
        .alpha => r.BLEND_ALPHA,
        .multiply => r.BLEND_ALPHA_PREMULTIPLY,
        .render_tex_alpha => {
            r.rlSetBlendFactorsSeparate(0x0302, 0x0303, 1, 0x0303, 0x8006, 0x8006);
            break :blk r.BLEND_CUSTOM_SEPARATE;
        },
    };
    r.BeginBlendMode(r_val);
}

fn cCam(cam: draw.Camera2D) r.Camera2D {
    return .{
        .offset = cVec(cam.offset),
        .rotation = cam.rot_rads,
        .target = cVec(cam.pos),
        .zoom = cam.zoom,
    };
}

pub fn startCamera2D(self: *Platform, cam: draw.Camera2D, opt: draw.CameraOpt) void {
    var cam_r = cam;
    if (opt.round_to_pixel) {
        cam_r.pos = cam_r.pos.scale(cam.zoom).round().scale(1 / cam.zoom);
        //cam_r.pos = cam.pos.round();
        cam_r.offset = cam.offset.round();
    }
    self.curr_cam = cam_r;
    r.BeginMode2D(cCam(cam_r));
}

pub fn endCamera2D(self: *Platform) void {
    self.curr_cam = .{};
    r.EndMode2D();
}

pub fn screenPosToCamPos(self: *Platform, cam: draw.Camera2D, pos: V2f) V2f {
    const c = draw.Camera2D{
        .pos = cam.pos,
        .offset = cam.offset.scale(self.game_scaling),
        .zoom = cam.zoom * self.game_scaling,
    };
    const p = pos.sub(self.game_canvas_screen_topleft_offset);
    return zVec(r.GetScreenToWorld2D(cVec(p), cCam(c)));
}

pub fn camPosToScreenPos(self: *Platform, cam: draw.Camera2D, pos: V2f) V2f {
    _ = self;
    return zVec(r.GetWorldToScreen2D(cVec(pos), cCam(cam)));
}

pub fn getMousePosWorld(self: *Platform, cam: draw.Camera2D) V2f {
    return self.screenPosToCamPos(cam, self.mousePosf());
}

pub fn getMousePosScreen(self: *Platform) V2f {
    return self.mousePosf();
}

pub fn startRenderToTexture(_: *Platform, render_tex: RenderTexture2D) void {
    r.BeginTextureMode(render_tex.r_render_tex);
}
pub fn endRenderToTexture(_: *Platform) void {
    r.EndTextureMode();
}

pub fn mousePosf(_: *Platform) V2f {
    return zVec(r.GetMousePosition());
}

pub fn mouseWheelY(_: *Platform) f32 {
    return r.GetMouseWheelMoveV().y;
}

const mouse_button_map = std.EnumArray(MouseButton, c_int).init(.{
    .left = r.MOUSE_BUTTON_LEFT,
    .right = r.MOUSE_BUTTON_RIGHT,
});

pub fn mouseBtnIsDown(_: *Platform, button: MouseButton) bool {
    return r.IsMouseButtonDown(mouse_button_map.get(button));
}

fn tickInputBuffer(self: *Platform) void {
    self.input_buffer.advance_one();
    const state = self.input_buffer.getCurrPtr();

    inline for (std.meta.fields(Key)) |k| {
        const e: Key = @enumFromInt(k.value);
        if (self.keyIsDown(e)) {
            state.keys.insert(e);
        }
    }
    inline for (std.meta.fields(MouseButton)) |k| {
        const e: MouseButton = @enumFromInt(k.value);
        if (self.mouseBtnIsDown(e)) {
            state.mouse_buttons.insert(e);
        }
    }
    state.mouse_screen_pos = self.getMousePosScreen();
}

pub fn fitTextToRect(self: *Platform, dims: V2f, text: []const u8, opt: draw.TextOpt) Error!draw.TextOpt {
    var ret_opt = opt;
    ret_opt.size = 1;
    while (true) {
        const sz = try self.measureText(text, ret_opt);
        if (sz.x > dims.x or sz.y > dims.y) {
            ret_opt.size -= 1;
            break;
        }
        ret_opt.size += 1;
    }
    return ret_opt;
}

pub const Sound = struct {
    name: []const u8,
    r_wave: r.Wave,
};

pub const AudioStream = struct {
    const sample_rate: c_int = 44100;
    const sample_size_bits: c_int = 16;
    const num_channels: c_int = 1;
    const stride_bits = sample_size_bits * num_channels;
    const FrameInt = std.meta.Int(.unsigned, stride_bits);
    // bit of buffer, i think this is in frames
    const buf_sz: c_int = 4096;
    var scratch_buf: [buf_sz]FrameInt = undefined;

    playing_sound: ?Sound = null,
    play_offset: usize = 0,
    r_stream: r.AudioStream,

    pub fn setSound(self: *AudioStream, sound: Sound) void {
        self.playing_sound = sound;
        self.play_offset = 0;
    }
    // return true if ended (or looped)
    pub fn updateSound(self: *AudioStream, loop: bool) bool {
        if (self.playing_sound == null) return true;
        const r_wave = self.playing_sound.?.r_wave;
        // we got to the end of the wave
        var ret = false;
        if (!r.IsAudioStreamProcessed(self.r_stream)) {
            return false;
        }

        if (self.play_offset >= r_wave.frameCount) {
            // we don't reset it to 0 because of looping.
            // we might be starting at a non-zero offset
            // (see below where we use scratch_buffer)
            self.play_offset -= r_wave.frameCount;
            ret = true;
            if (!loop) {
                self.playing_sound = null;
                return ret;
            }
        }
        const frames_left = r_wave.frameCount - self.play_offset;
        const batch_size = @min(frames_left, buf_sz);
        const batch_end = self.play_offset + batch_size;
        const wave_buf: []FrameInt = @as([*]FrameInt, @alignCast(@ptrCast(r_wave.data.?)))[0..r_wave.frameCount];
        var buf = wave_buf[self.play_offset..batch_end];
        // we reached the end of the data, and we want to loop.
        // but raylib will always play the FULL buffer - all the way to the end (zeroing out unused part)
        // so, to loop seamlessly we need to copy the first part of the sound into the
        // end of a scratch buffer and send that too
        if (loop and batch_size < buf_sz) {
            const remaining_space = u.as(usize, buf_sz - batch_size);
            @memcpy(scratch_buf[0..batch_size], buf);
            @memcpy(scratch_buf[batch_size..], wave_buf[0..remaining_space]);
            buf = &scratch_buf;
        }
        r.UpdateAudioStream(self.r_stream, @ptrCast(buf), u.as(c_int, buf.len));
        self.play_offset += buf.len;

        // ret is false here unless we looped
        return ret;
    }

    pub fn setVolume(self: *AudioStream, vol: f32) void {
        r.SetAudioStreamVolume(self.r_stream, vol);
    }
    // start playing the stream, assuming there's a sound and it's been updated
    pub fn play(self: *AudioStream) void {
        r.PlayAudioStream(self.r_stream);
    }
    pub fn stop(self: *AudioStream) void {
        self.playing_sound = null;
        r.StopAudioStream(self.r_stream);
    }
};

pub fn createAudioStream(_: *Platform) AudioStream {
    r.SetAudioStreamBufferSizeDefault(AudioStream.buf_sz);
    const r_stream = r.LoadAudioStream(AudioStream.sample_rate, AudioStream.sample_size_bits, AudioStream.num_channels);
    return .{
        .r_stream = r_stream,
    };
}

pub fn destroyAudioStream(_: *Platform, s: AudioStream) void {
    r.UnloadAudioStream(s.r_stream);
}

pub fn _loadSound(_: *Platform, name: []const u8, path_z: [:0]const u8) Error!Sound {
    @setRuntimeSafety(core.rt_safe_blocks);
    var r_wave = r.LoadWave(path_z);
    if (!r.IsWaveValid(r_wave)) {
        return Error.FormatFail;
    }
    r.WaveFormat(&r_wave, AudioStream.sample_rate, AudioStream.sample_size_bits, AudioStream.num_channels);
    const ret: Sound = .{
        .name = name,
        .r_wave = r_wave,
    };
    return ret;
}

pub fn unloadSound(_: *Platform, sound: Sound) void {
    r.UnloadWave(sound.r_wave);
}

pub fn loadSound(self: *Platform, path: []const u8) Error!Sound {
    const path_z = try std.fmt.bufPrintZ(self.str_fmt_buf, "{s}/{s}", .{ self.assets_path, path });
    return self._loadSound(path, path_z);
}

pub fn exit(self: *Platform) void {
    self.should_exit = true;
}
pub const Shader = struct {
    r_shader: r.Shader,
};

pub fn loadShader(self: *Platform, vert_path: ?[]const u8, frag_path: ?[]const u8) Error!Shader {
    @setRuntimeSafety(core.rt_safe_blocks);
    const vert_path_z: [*c]const u8 = if (vert_path) |p|
        try std.fmt.bufPrintZ(self.str_fmt_buf, "{s}/shaders/{s}", .{ self.assets_path, p })
    else
        null;
    const frag_path_z: [*c]const u8 = if (frag_path) |p|
        try std.fmt.bufPrintZ(self.str_fmt_buf[1000..], "{s}/shaders/{s}", .{ self.assets_path, p })
    else
        null;
    const r_shader = r.LoadShader(vert_path_z, frag_path_z);
    const ret: Shader = .{
        .r_shader = r_shader,
    };
    return ret;
}

pub fn unloadShader(self: *Platform, shader: Shader) void {
    _ = self;
    r.UnloadShader(shader.r_shader);
}

fn getShaderUniformKind(T: type) c_int {
    const type_info = @typeInfo(T);
    switch (type_info) {
        .@"struct" => |s| {
            if (s.fields.len != 2)
                @compileError("Invalid struct type for shader uniform; must have 2 fields (x and y)")
            else if (@hasField(T, "x") and @hasField(T, "y"))
                switch (@typeInfo(s.fields[std.meta.fieldIndex(T, "x").?].type)) {
                    .float => |f| if (f.bits == 32) return r.SHADER_UNIFORM_VEC2 else @compileError("Shader float uniform must be 32 bits"),
                    .int => |i| if (i.bits == 32) return r.SHADER_UNIFORM_IVEC2 else @compileError("Shader int uniform must be 32 bits"),
                    else => @compileError("Invalid struct type for shader uniform; field \"x\" is not float or int"),
                }
            else
                @compileError("Invalid struct type for shader uniform");
        },
        .@"enum" => return r.SHADER_UNIFORM_INT,
        .float => return r.SHADER_UNIFORM_FLOAT,
        .int => return r.SHADER_UNIFORM_INT,
        else => @compileError("Invalid type for shader uniform"),
    }
}

pub fn setShaderValuesArray(self: *Platform, shader: Shader, arr_name: []const u8, member_name: ?[]const u8, T: type, args: []T) Error!void {
    const uniform_kind = getShaderUniformKind(T);
    for (args, 0..) |a, i| {
        const name_z = if (member_name) |mb|
            try std.fmt.bufPrintZ(self.str_fmt_buf, "{s}[{}].{s}", .{ arr_name, i, mb })
        else
            try std.fmt.bufPrintZ(self.str_fmt_buf, "{s}[{}]", .{ arr_name, i });
        const loc = r.GetShaderLocation(shader.r_shader, name_z);
        r.SetShaderValue(shader.r_shader, loc, &a, uniform_kind);
    }
}

pub fn setShaderValue(self: *Platform, shader: Shader, loc_name: []const u8, value: anytype) Error!void {
    const uniform_kind = getShaderUniformKind(@TypeOf(value));
    const name_z = try std.fmt.bufPrintZ(self.str_fmt_buf, "{s}", .{loc_name});
    const loc = r.GetShaderLocation(shader.r_shader, name_z);
    r.SetShaderValue(shader.r_shader, loc, &value, uniform_kind);
}

pub fn setShaderValuesScalar(_: *Platform, shader: Shader, args: anytype) void {
    const ArgsType = @TypeOf(args);
    const args_type_info = @typeInfo(ArgsType);
    if (args_type_info != .@"struct") {
        @compileError("expected tuple or struct argument, found " ++ @typeName(ArgsType));
    }

    const fields_info = args_type_info.@"struct".fields;
    if (fields_info.len > 32) {
        @compileError("32 arguments max are supported per setShaderValue");
    }
    inline for (args_type_info.@"struct".fields) |f| {
        const loc = r.GetShaderLocation(shader.r_shader, f.name);
        const uniform_kind = getShaderUniformKind(f.type);
        r.SetShaderValue(shader.r_shader, loc, &@field(args, f.name), uniform_kind);
    }
}

pub fn setShader(_: *Platform, shader: Shader) void {
    r.BeginShaderMode(shader.r_shader);
}

pub fn setDefaultShader(_: *Platform) void {
    r.EndShaderMode();
}

// iterates over files in a directory, with a given suffix (including dot, e.g. ".json")
pub const FileWalkerIterator = struct {
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    walker: std.fs.Dir.Walker,
    file_suffixes: ?[]const []const u8,

    pub fn deinit(self: *@This()) void {
        self.walker.deinit();
        self.dir.close();
    }

    pub const NextEntry = struct {
        path: []const u8,
        subdir: []const u8,
        basename: []const u8,
        owned_string: []u8,

        pub fn deinit(entry: NextEntry, it: FileWalkerIterator) void {
            it.allocator.free(entry.owned_string);
        }
    };

    pub fn next(self: *@This()) Error!?NextEntry {
        while (self.walker.next() catch return Error.FileSystemFail) |entry| {
            if (entry.kind != .file) continue;
            if (self.file_suffixes) |suffixes| {
                for (suffixes) |suf| {
                    if (std.mem.endsWith(u8, entry.basename, suf)) break;
                } else {
                    continue;
                }
            }
            const file = self.dir.openFile(entry.path, .{}) catch {
                // can't be used from dynlib
                //getPlat().log.err("Failed to open \"{s}\"", .{entry.path});
                continue;
            };
            const str = file.readToEndAlloc(self.allocator, 100 * 1024 * 1024) catch {
                // can't be used from dynlib
                //getPlat().log.err("Failed to read \"{s}\"", .{entry.path});
                continue;
            };
            return .{
                .path = entry.path,
                .subdir = entry.path[0..(entry.path.len - entry.basename.len)],
                .basename = entry.basename,
                .owned_string = str,
            };
        }
        return null;
    }
};

pub fn iteratePath(plat: *Platform, path: []const u8, file_suffixes: ?[]const []const u8) Error!FileWalkerIterator {
    var dir = std.fs.openDirAbsolute(path, .{ .iterate = true }) catch |err| {
        plat.log.err("Error opening dir \"{s}\"", .{path});
        plat.log.errorAndStackTrace(err);
        return Error.FileSystemFail;
    };
    const walker = try dir.walk(plat.heap);

    return .{
        .allocator = plat.heap,
        .dir = dir,
        .walker = walker,
        .file_suffixes = file_suffixes,
    };
}

pub fn iterateAssets(plat: *Platform, subdir: []const u8, file_suffixes: ?[]const []const u8) Error!FileWalkerIterator {
    const path = try u.bufPrintLocal("{s}/{s}", .{ plat.assets_path, subdir });
    return plat.iteratePath(path, file_suffixes);
}
