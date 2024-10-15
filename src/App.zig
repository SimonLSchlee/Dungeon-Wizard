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
options: Options = .{},
screen: enum {
    run,
} = .run,
run: Run = undefined,

export fn appInit(plat: *Platform) *anyopaque {
    // everything depends on plat global
    _plat = plat;

    var app = plat.heap.create(App) catch @panic("Out of memory");
    app.* = .{};
    app._arena = std.heap.ArenaAllocator.init(plat.heap);
    app.arena = app._arena.allocator();
    app.data = Data.init() catch @panic("Failed to init data");

    // populate _app here, Room.init() uses it
    _app = app;
    app.run = Run.init(0) catch @panic("Failed to init run state");

    return app;
}

export fn appReload(app_ptr: *anyopaque, plat: *Platform) void {
    _plat = plat;
    const app: *App = @ptrCast(@alignCast(app_ptr));
    // allocator has a pointer to ArenaAllocater that needs re-setting
    app.arena = app._arena.allocator();
    app.data.reload() catch @panic("Failed to reload data");
    _app = app;
}

export fn appTick() void {
    var app = App.get();
    app.update() catch @panic("fail appTick");
}

export fn appRender() void {
    var app = App.get();
    app.render() catch @panic("fail appRender");
}

pub fn reset(self: *App) Error!*App {
    self.deinit();
    self.* = .{};
    try self.init();
    return self;
}

pub fn deinit(self: *App) void {
    self.run.deinit();
    getPlat().heap.destroy(self);
}

fn update(self: *App) Error!void {
    switch (self.screen) {
        .run => {
            try self.run.update();
        },
    }
}

fn render(self: *App) Error!void {
    switch (self.screen) {
        .run => {
            try self.run.render();
        },
    }
}

pub fn copyString(allocator: *std.mem.Allocator, str: []const u8) []u8 {
    const ptr = allocator.alloc(u8, str.len) catch @panic("OOM");
    std.mem.copyForwards(u8, ptr, str);
    return ptr;
}
