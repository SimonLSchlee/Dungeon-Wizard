const std = @import("std");
const assert = std.debug.assert;
const Platform = @This();
const u = @import("util.zig");
const r = @cImport({
    @cInclude("raylib.h");
    @cInclude("rlgl.h");
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

const builtin = @import("builtin");
const config = @import("config");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

const str_fmt_buf_size = 4096;

pub const Font = struct {
    name: []const u8,
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

should_exit: bool = false,
app_dll: ?std.DynLib = null,
appInit: *const fn (*Platform) *anyopaque = undefined,
appReload: *const fn (*anyopaque, *Platform) void = undefined,
appTick: *const fn () void = undefined,
appRender: *const fn () void = undefined,
heap: std.mem.Allocator = gpa.allocator(),
default_font: Font = undefined,
screen_dims: V2i = .{},
screen_dims_f: V2f = .{},
native_to_screen_scaling: f32 = 1,
native_to_screen_offset: V2f = .{},
native_rect_cropped_offset: V2f = .{},
native_rect_cropped_dims: V2f = .{},
accumulated_update_ns: i64 = 0,
prev_frame_time_ns: i64 = 0,
input_buffer: core.InputBuffer = .{},
str_fmt_buf: []u8 = undefined,
assets_path: []const u8 = undefined,

pub fn updateDims(self: *Platform, dims: V2i) void {
    self.screen_dims = dims;
    self.screen_dims_f = dims.toV2f();
    const x_scaling = self.screen_dims_f.x / core.native_dims_f.x;
    const y_scaling = self.screen_dims_f.y / core.native_dims_f.y;
    self.native_to_screen_scaling = @max(x_scaling, y_scaling);
    const scaled_native_dims = core.native_dims_f.scale(self.native_to_screen_scaling);
    self.native_to_screen_offset = self.screen_dims_f.sub(scaled_native_dims).scale(0.5);
    // in native space, get rectangle that is actually shown on the screen, for UI anchoring and such
    self.native_rect_cropped_offset = self.native_to_screen_offset.scale(1 / self.native_to_screen_scaling).neg();
    self.native_rect_cropped_dims = self.screen_dims_f.scale(1 / self.native_to_screen_scaling);
}

pub fn init(title: []const u8) Error!Platform {
    @setRuntimeSafety(core.rt_safe_blocks);

    const dims = core.native_dims;

    var ret: Platform = .{};
    const title_z = try std.fmt.allocPrintZ(ret.heap, "{s}", .{title});

    //r.SetConfigFlags(r.FLAG_WINDOW_RESIZABLE);
    r.InitWindow(@intCast(dims.x), @intCast(dims.y), title_z);
    // show raylib init INFO, then just warnings
    r.SetTraceLogLevel(r.LOG_WARNING);

    ret.str_fmt_buf = try ret.heap.alloc(u8, str_fmt_buf_size);
    ret.assets_path = try ret.getAssetsPath();

    ret.updateDims(dims);
    ret.default_font = try ret.loadFont("Roboto-Regular.ttf"); // NOTE uses str_fmt_buf initialized above

    r.InitAudioDevice();
    r.SetExitKey(0);

    return ret;
}

pub fn closeWindow(_: *Platform) void {
    r.CloseWindow();
}

pub fn getAssetsPath(self: *Platform) Error![]const u8 {
    if (config.is_release) {
        switch (builtin.os.tag) {
            .macos => {
                const CF = @cImport({
                    @cInclude("CFBundle.h");
                    @cInclude("CFURL.h");
                    @cInclude("CFString.h");
                });
                // Zig thinks these are ? but they're just C pointers I guess
                const bundle = CF.CFBundleGetMainBundle();
                const cf_url = CF.CFBundleCopyResourcesDirectoryURL(bundle);
                const cf_str_ref = CF.CFURLCopyFileSystemPath(cf_url, CF.kCFURLPOSIXPathStyle);
                const c_buf: [*c]u8 = @ptrCast(self.str_fmt_buf);
                if (CF.CFStringGetCString(cf_str_ref, c_buf, str_fmt_buf_size, CF.kCFStringEncodingASCII) != 0) {
                    const slice = std.mem.span(c_buf);
                    return try std.fmt.allocPrint(self.heap, "{s}/assets", .{slice});
                } else {
                    return Error.NoSpaceLeft;
                }
                return Error.FileSystemFail;
            },
            else => {},
        }
    }
    return "assets";
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
        std.debug.print("######### LOAD {s} ######\n", .{app_dll_path});
        break :blk std.DynLib.open(app_dll_path) catch |e| {
            std.debug.print("{s}: {any}\n", .{ app_dll_path, e });
            continue;
        };
    } else {
        @panic("Fail to load app dll");
    };
    var dll = self.app_dll.?;
    std.debug.print("######### LOADED ######\n", .{});
    self.appInit = dll.lookup(@TypeOf(self.appInit), "appInit") orelse return error.LookupFail;
    self.appReload = dll.lookup(@TypeOf(self.appReload), "appReload") orelse return error.LookupFail;
    self.appTick = dll.lookup(@TypeOf(self.appTick), "appTick") orelse return error.LookupFail;
    self.appRender = dll.lookup(@TypeOf(self.appRender), "appRender") orelse return error.LookupFail;
}

fn unloadAppDll(self: *Platform) void {
    if (self.app_dll) |*dll| {
        std.debug.print("######### UNLOAD ######\n", .{});
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
    std.debug.print("\n#### START RECOMPILE OUTPUT ####\n", .{});
    const result = std.process.Child.run(.{
        .allocator = self.heap,
        .argv = &proc_args,
    }) catch return Error.RecompileFail;

    std.debug.print("stderr:\n{s}\n", .{result.stderr});
    std.debug.print("stdout:\n{s}\n", .{result.stdout});
    std.debug.print("\n#### END RECOMPILE OUTPUT ####\n", .{});
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
    std.debug.print("refresh rate: {}\n", .{refresh_rate});
    std.debug.print("ns per refresh: {}\n", .{ns_per_refresh});

    while (!r.WindowShouldClose() and !self.should_exit) {
        if (!config.static_lib and !config.is_release and r.IsKeyPressed(r.KEY_F5)) {
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
            const num_updates_to_do: i64 = @divTrunc(self.accumulated_update_ns, core.fixed_ns_per_update);
            std.debug.print("{}", .{num_updates_to_do});
        }

        while (self.accumulated_update_ns >= core.fixed_ns_per_update_upper) {
            r.PollInputEvents();
            self.tickInputBuffer();
            self.appTick();
            self.accumulated_update_ns -= core.fixed_ns_per_update_lower;
            if (self.accumulated_update_ns < core.fixed_ns_per_update_lower - core.fixed_ns_per_update_upper) {
                self.accumulated_update_ns = 0;
            }
        }

        //const start_draw_ns = self.getGameTimeNanosecs();
        r.BeginDrawing();
        self.appRender();
        r.EndDrawing();

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
    const draw_pos: r.Vector2 = if (opt.center) .{ .x = pos.x - u.as(f32, text_width.x) / 2, .y = pos.y - text_width.y / 2 } else cVec(pos);
    r.SetTextureFilter(font.r_font.texture, r.TEXTURE_FILTER_BILINEAR);
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

pub fn linef(_: *Platform, start: V2f, end: V2f, thickness: f32, color: Colorf) void {
    r.DrawLineEx(cVec(start), cVec(end), thickness, cColorf(color));
}

pub fn rectf(_: *Platform, topleft: V2f, dims: V2f, opt: draw.PolyOpt) void {
    const rec: r.Rectangle = .{
        .x = topleft.x,
        .y = topleft.y,
        .width = dims.x,
        .height = dims.y,
    };
    if (opt.fill_color) |color| {
        r.DrawRectangleRec(rec, cColorf(color));
    }
    if (opt.outline_color) |color| {
        r.DrawRectangleLinesEx(rec, opt.outline_thickness, cColorf(color));
    }
}

pub fn circlef(_: *Platform, center: V2f, radius: f32, opt: draw.PolyOpt) void {
    if (opt.fill_color) |color| {
        r.DrawCircleV(cVec(center), radius, cColorf(color));
    }
    if (opt.outline_color) |color| {
        r.DrawCircleLinesV(cVec(center), radius, cColorf(color));
    }
}

pub fn sectorf(_: *Platform, center: V2f, radius: f32, start_ang_rads: f32, end_ang_rads: f32, opt: draw.PolyOpt) void {
    const p = cVec(center);
    const segs = 20;
    const start_deg = u.radiansToDegrees(start_ang_rads);
    const end_deg = u.radiansToDegrees(end_ang_rads);
    if (opt.fill_color) |color| {
        r.DrawCircleSector(p, radius, start_deg, end_deg, segs, cColorf(color));
    }
    if (opt.outline_color) |color| {
        r.DrawCircleSectorLines(p, radius, start_deg, end_deg, segs, cColorf(color));
    }
}

//pub fn polyf(_: *Platform, points: []V2f, opt: draw.PolyOpt) void {
//    r.drawPol
//    r.DrawPoly(center: Vector2, sides: c_int, radius: f32, rotation: f32, color: Colorf)
//    return self._drawRectf(self, points, opt);
//}

pub fn trianglef(_: *Platform, points: [3]V2f, opt: draw.PolyOpt) void {
    if (opt.fill_color) |color| {
        r.DrawTriangle(cVec(points[0]), cVec(points[1]), cVec(points[2]), cColorf(color));
    }
    if (opt.outline_color) |color| {
        r.DrawTriangleLines(cVec(points[0]), cVec(points[1]), cVec(points[2]), cColorf(color));
    }
}

pub fn arrowf(self: *Platform, base: V2f, point: V2f, thickness: f32, color: Colorf) void {
    assert(thickness >= 0.001);

    const tri_height = thickness * 2.3;
    const tri_width = thickness * 2.5;
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
    self.linef(base, line_end, thickness, color);

    const tri_end = line_end.add(dir.scale(tri_height));
    const tri_edge_v = dir.scale(tri_width_2);
    const left_v = V2f{ .x = tri_edge_v.y, .y = -tri_edge_v.x };
    const right_v = V2f{ .x = -tri_edge_v.y, .y = tri_edge_v.x };
    self.trianglef(.{ line_end.add(left_v), line_end.add(right_v), tri_end }, .{ .fill_color = color });
}

pub fn loadFont(self: *Platform, path: []const u8) Error!Font {
    @setRuntimeSafety(core.rt_safe_blocks);
    const path_z = try std.fmt.bufPrintZ(self.str_fmt_buf, "{s}/fonts/{s}", .{ self.assets_path, path });
    var r_font = r.LoadFontEx(path_z, 200, 0, 0);
    r.GenTextureMipmaps(&r_font.texture);
    const ret: Font = .{
        .name = path,
        .r_font = r_font,
    };
    return ret;
}

pub fn loadTexture(self: *Platform, path: []const u8) Error!Texture2D {
    @setRuntimeSafety(core.rt_safe_blocks);
    const path_z = try std.fmt.bufPrintZ(self.str_fmt_buf, "{s}/images/{s}", .{ self.assets_path, path });
    const r_tex = r.LoadTexture(path_z);
    return .{
        .name = path,
        .dims = .{ .x = @intCast(r_tex.width), .y = @intCast(r_tex.height) },
        .r_tex = r_tex,
    };
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

pub fn texturef(_: *Platform, pos: V2f, tex: Texture2D, opt: draw.TextureOpt) void {
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
    var dest = r.Rectangle{
        .x = pos.x,
        .y = pos.y,
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
        .center => v2f(dest.width, dest.height).scale(0.5),
        .offset => |o| o.scale(opt.uniform_scaling),
    };
    const r_filter = switch (opt.smoothing) {
        .none => r.TEXTURE_FILTER_POINT,
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

pub fn startCamera2D(self: *Platform, cam: draw.Camera2D) void {
    _ = self;
    r.BeginMode2D(cCam(cam));
}

pub fn endCamera2D(_: *Platform) void {
    r.EndMode2D();
}

pub fn screenPosToCamPos(self: *Platform, cam: draw.Camera2D, pos: V2f) V2f {
    var c = cam;
    c.offset = c.offset.add(self.native_to_screen_offset);
    return zVec(r.GetScreenToWorld2D(cVec(pos), cCam(c)));
}

pub fn camPosToScreenPos(self: *Platform, cam: draw.Camera2D, pos: V2f) V2f {
    var c = cam;
    c.offset = c.offset.add(self.native_to_screen_offset);
    return zVec(r.GetWorldToScreen2D(cVec(pos), cCam(c)));
}

pub fn getMousePosWorld(self: *Platform, cam: draw.Camera2D) V2f {
    const mouse_cam = draw.Camera2D{
        .pos = cam.pos,
        .offset = self.screen_dims_f.scale(0.5).sub(self.native_to_screen_offset),
        .zoom = cam.zoom * self.native_to_screen_scaling,
    };
    return self.screenPosToCamPos(mouse_cam, self.mousePosf());
}

pub fn getMousePosScreen(self: *Platform) V2f {
    return self.mousePosf().sub(self.native_to_screen_offset).scale(1 / self.native_to_screen_scaling);
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
    r_sound: r.Sound,
};

pub fn stopSound(_: *Platform, sound: Sound) void {
    r.StopSound(sound.r_sound);
}

pub fn playSound(_: *Platform, sound: Sound) void {
    r.PlaySound(sound.r_sound);
}

pub fn loopSound(_: *Platform, sound: Sound) void {
    if (!r.IsSoundPlaying(sound.r_sound)) {
        r.PlaySound(sound.r_sound);
    }
}
pub fn setSoundVolume(_: *Platform, sound: Sound, volume: f32) void {
    r.SetSoundVolume(sound.r_sound, volume);
}

pub fn loadSound(self: *Platform, path: []const u8) Error!Sound {
    @setRuntimeSafety(core.rt_safe_blocks);
    const path_z = try std.fmt.bufPrintZ(self.str_fmt_buf, "{s}/sounds/{s}", .{ self.assets_path, path });
    const r_sound = r.LoadSound(path_z);
    const ret: Sound = .{
        .name = path,
        .r_sound = r_sound,
    };
    return ret;
}

pub fn exit(self: *Platform) void {
    self.should_exit = true;
}
