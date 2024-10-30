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

const App = @This();
const Run = @import("Run.zig");
const Data = @import("Data.zig");
const Options = @import("Options.zig");

var _app: ?*App = null;
var _plat: ?*Platform = null;

pub fn get() *App {
    return _app orelse @panic("_app not found");
}

pub fn getPlat() *Platform {
    return _plat orelse @panic("_plat not found");
}

_arena: std.heap.ArenaAllocator = undefined,
arena: std.mem.Allocator = undefined,
data: *Data = undefined,
options: Options = undefined,
curr_tick: i64 = 0,
screen: enum {
    run,
} = .run,
options_open: bool = false,
run: Run = undefined,
render_texture: Platform.RenderTexture2D = undefined,

export fn appInit(plat: *Platform) *anyopaque {
    // everything depends on plat global
    _plat = plat;

    var app = plat.heap.create(App) catch @panic("Out of memory");
    app.* = .{
        .options = Options.initTryLoad(),
        .data = Data.init() catch @panic("Failed to init data"),
    };
    // TODO unused rn
    app._arena = std.heap.ArenaAllocator.init(plat.heap);
    app.arena = app._arena.allocator();

    // populate _app here, Room.init() uses it
    _app = app;
    app.render_texture = plat.createRenderTexture("app", core.native_dims);

    app.startNewRun(._4_slot_frank) catch @panic("Failed to go straight into run");

    return app;
}

pub fn staticAppInit(plat: *Platform) *anyopaque {
    return appInit(plat);
}

pub export fn appReload(app_ptr: *anyopaque, plat: *Platform) void {
    _plat = plat;
    const app: *App = @ptrCast(@alignCast(app_ptr));
    // allocator has a pointer to ArenaAllocater that needs re-setting
    app.arena = app._arena.allocator();
    app.data.reload() catch @panic("Failed to reload data");
    _app = app;
}

pub fn staticAppReload(app_ptr: *anyopaque, plat: *Platform) void {
    return appReload(app_ptr, plat);
}

pub export fn appTick() void {
    var app = App.get();
    app.update() catch @panic("fail appTick");
}

pub fn staticAppTick() void {
    appTick();
}

pub export fn appRender() void {
    var app = App.get();
    app.render() catch @panic("fail appRender");
}

pub fn staticAppRender() void {
    appRender();
}

fn startNewRun(self: *App, mode: Run.Mode) Error!void {
    self.run = try Run.initRandom(mode);
    try self.run.startRun();
    self.screen = .run;
}

pub fn deinit(self: *App) void {
    const plat = getPlat();
    self.run.deinit();
    plat.destroyRenderTexture(self.render_texture);
    plat.heap.destroy(self);
}

fn update(self: *App) Error!void {
    if (self.options_open) {
        switch (try self.options.update()) {
            .close => self.options_open = false,
            else => {},
        }
    } else {
        switch (self.screen) {
            .run => {
                try self.run.update();
            },
        }
    }
    self.curr_tick += 1;
}

fn render(self: *App) Error!void {
    const plat = getPlat();
    plat.clear(Colorf.magenta);

    switch (self.screen) {
        .run => {
            try self.run.render(self.render_texture);
        },
    }
    if (self.options_open) {
        try self.options.render(self.render_texture);
    }
    plat.endRenderToTexture();
    const texture_opt = draw.TextureOpt{
        .flip_y = true,
        .uniform_scaling = plat.native_to_screen_scaling,
        .origin = .center,
        .smoothing = .none,
    };
    plat.texturef(plat.screen_dims_f.scale(0.5), self.render_texture.texture, texture_opt);
}

pub fn copyString(allocator: *std.mem.Allocator, str: []const u8) []u8 {
    const ptr = allocator.alloc(u8, str.len) catch @panic("OOM");
    std.mem.copyForwards(u8, ptr, str);
    return ptr;
}
