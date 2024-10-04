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

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

const assets_path = "assets";

var str_fmt_local_buf: [1024]u8 = undefined;

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

app_dll: ?std.DynLib = null,
appInit: *const fn (*Platform) *anyopaque = undefined,
appReload: *const fn (*anyopaque, *Platform) void = undefined,
appTick: *const fn () void = undefined,
appRender: *const fn () void = undefined,
heap: std.mem.Allocator = gpa.allocator(),
default_font: Font = undefined,
screen_dims: V2i = .{},
screen_dims_f: V2f = .{},
accumulated_update_ns: i64 = 0,
prev_frame_time_ns: i64 = 0,
input_buffer: core.InputBuffer = .{},

pub fn init(width: u32, height: u32, title: []const u8) Error!Platform {
    @setRuntimeSafety(core.rt_safe_blocks);
    var ret: Platform = .{};
    const title_z = try std.fmt.allocPrintZ(ret.heap, "{s}", .{title});
    r.InitWindow(@intCast(width), @intCast(height), title_z);
    ret.default_font = try ret.loadFont("Roboto-Regular.ttf");
    ret.screen_dims = V2i.iToV2i(u32, width, height);
    ret.screen_dims_f = ret.screen_dims.toV2f();
    return ret;
}

pub fn closeWindow(_: *Platform) void {
    r.CloseWindow();
}

pub fn setTargetFPS(_: *Platform, fps: u32) void {
    @setRuntimeSafety(core.rt_safe_blocks);
    r.SetTargetFPS(@intCast(fps));
}

pub fn getGameTimeNanosecs(_: *Platform) i64 {
    return u.as(i64, r.GetTime() * u.as(f64, core.ns_per_sec));
}

const app_dll_path = "zig-out/lib/" ++ switch (@import("builtin").os.tag) {
    .macos => "libgame.dylib",
    .windows => "game.dll",
    else => @compileError("missing app dll name"),
};

fn loadAppDll(self: *Platform) Error!void {
    self.app_dll = std.DynLib.open(app_dll_path) catch @panic("Fail to load app dll");
    var dll = self.app_dll.?;
    self.appInit = dll.lookup(@TypeOf(self.appInit), "appInit") orelse return error.LookupFail;
    self.appReload = dll.lookup(@TypeOf(self.appReload), "appReload") orelse return error.LookupFail;
    self.appTick = dll.lookup(@TypeOf(self.appTick), "appTick") orelse return error.LookupFail;
    self.appRender = dll.lookup(@TypeOf(self.appRender), "appRender") orelse return error.LookupFail;
}

fn unloadAppDll(self: *Platform) void {
    if (self.app_dll) |*dll| {
        dll.close();
        self.app_dll = null;
    }
}

fn recompileAppDll(self: *Platform) Error!void {
    const proc_args = [_][]const u8{
        "zig",
        "build",
        "-Dapp_only=true",
    };
    var proc = std.process.Child.init(&proc_args, self.heap);
    const term = proc.spawnAndWait() catch return Error.RecompileFail;
    switch (term) {
        .Exited => |exited| {
            if (exited != 0) return Error.RecompileFail;
        },
        else => return Error.RecompileFail,
    }
}

pub fn run(self: *Platform) Error!void {
    @setRuntimeSafety(core.rt_safe_blocks);

    try self.loadAppDll();
    const app = self.appInit(self);

    self.prev_frame_time_ns = @max(self.getGameTimeNanosecs() - core.fixed_ns_per_update, 0);
    r.SetConfigFlags(r.FLAG_VSYNC_HINT);
    const refresh_rate = u.as(i64, r.GetMonitorRefreshRate(r.GetCurrentMonitor()));
    const ns_per_refresh = @divTrunc(core.ns_per_sec, refresh_rate);
    const min_sleep_time_ns = 1500000;
    std.debug.print("refresh rate: {}\n", .{refresh_rate});
    std.debug.print("ns per refresh: {}\n", .{ns_per_refresh});

    while (!r.WindowShouldClose()) {
        if (r.IsKeyPressed(r.KEY_F5)) {
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
    const text_z = try std.fmt.bufPrintZ(&str_fmt_local_buf, fmt, args);
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
    const text_z = try std.fmt.bufPrintZ(&str_fmt_local_buf, "{s}", .{text});
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

pub fn loadFont(_: *Platform, path: []const u8) Error!Font {
    @setRuntimeSafety(core.rt_safe_blocks);
    const path_z = try std.fmt.bufPrintZ(&str_fmt_local_buf, "{s}/fonts/{s}", .{ assets_path, path });
    var r_font = r.LoadFontEx(path_z, 200, 0, 0);
    r.GenTextureMipmaps(&r_font.texture);
    const ret: Font = .{
        .name = path,
        .r_font = r_font,
    };
    return ret;
}

pub fn loadTexture(_: *Platform, path: []const u8) Error!Texture2D {
    @setRuntimeSafety(core.rt_safe_blocks);
    const path_z = try std.fmt.bufPrintZ(&str_fmt_local_buf, "{s}/images/{s}", .{ assets_path, path });
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
        .offset => |o| o,
    };
    const r_filter = switch (opt.smoothing) {
        .none => r.TEXTURE_FILTER_POINT,
        .bilinear => r.TEXTURE_FILTER_POINT,
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

pub fn startCamera2D(_: *Platform, cam: draw.Camera2D) void {
    r.BeginMode2D(cCam(cam));
}

pub fn endCamera2D(_: *Platform) void {
    r.EndMode2D();
}

pub fn screenPosToCamPos(_: *Platform, cam: draw.Camera2D, pos: V2f) V2f {
    return zVec(r.GetScreenToWorld2D(cVec(pos), cCam(cam)));
}

pub fn camPosToScreenPos(_: *Platform, cam: draw.Camera2D, pos: V2f) V2f {
    return zVec(r.GetWorldToScreen2D(cVec(pos), cCam(cam)));
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
    state.mouse_screen_pos = self.mousePosf();
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
