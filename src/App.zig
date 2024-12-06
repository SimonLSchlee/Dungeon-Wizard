const std = @import("std");
const assert = std.debug.assert;
const utl = @import("util.zig");

pub const Platform = @import("raylib.zig");
const LogType = @import("Log.zig");
const debug = @import("debug.zig");
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
const ImmUI = @import("ImmUI.zig");
const menuUI = @import("menuUI.zig");
const config = @import("config");

var _app: ?*App = null;
var _plat: ?*Platform = null;

pub inline fn get() *App {
    return _app orelse @panic("_app not found");
}

pub inline fn getPlat() *Platform {
    return _plat orelse @panic("_plat not found");
}

pub const Log = LogType.GlobalInterface(getLog);
fn getLog() *LogType {
    return &getPlat().log;
}

pub inline fn getData() *Data {
    return get().data;
}

_arena: std.heap.ArenaAllocator = undefined,
arena: std.mem.Allocator = undefined,
data: *Data = undefined,
options: Options = undefined,
curr_tick: i64 = 0,
screen: enum {
    menu,
    run,
} = .menu,
options_open: bool = false,
run: Run = undefined,
menu_ui: struct {
    commands: ImmUI.CmdBuf = .{},
} = .{},
render_texture: Platform.RenderTexture2D = undefined,

export fn appInit(plat: *Platform) *anyopaque {
    // everything depends on plat global
    _plat = plat;

    Log.info("Init app {s}", .{config.version});

    Log.info("Allocating App: {}KiB\n", .{@sizeOf(App) / 1024});

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

    //app.startNewRun(._4_slot_frank) catch @panic("Failed to go straight into run");

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
    _ = try Run.initRandom(&self.run, mode);
    try self.run.startRun();
    self.screen = .run;
    //const plat = getPlat();
    //plat.playSound(self.data.music.get(.dungongnu));
}

pub fn deinit(self: *App) void {
    const plat = getPlat();
    self.run.deinit();
    plat.destroyRenderTexture(self.render_texture);
    plat.heap.destroy(self);
}

fn menuUpdate(self: *App) Error!void {
    const plat = getPlat();
    const title_text = "Magic-Using Individual";
    const title_opt = draw.TextOpt{
        .center = true,
        .color = .white,
        .size = 40,
    };
    const title_dims = try plat.measureText(title_text, title_opt);
    const btn_dims = v2f(190, 90);
    const title_padding = v2f(50, 50);
    const btn_spacing: f32 = 20;
    const bottom_spacing: f32 = 40;
    const num_buttons = 4;
    const panel_dims = v2f(
        title_dims.x + title_padding.x * 2,
        title_dims.y + title_padding.y * 2 + btn_dims.y * num_buttons + btn_spacing * (num_buttons - 1) + bottom_spacing,
    );
    const panel_topleft = plat.native_rect_cropped_offset.add(plat.native_rect_cropped_dims.sub(panel_dims).scale(0.5));
    self.menu_ui.commands.clear();
    self.menu_ui.commands.append(.{
        .rect = .{
            .pos = panel_topleft,
            .dims = panel_dims,
            .opt = .{
                .fill_color = Colorf.rgb(0.1, 0.1, 0.1),
            },
        },
    }) catch unreachable;

    const title_topleft = panel_topleft.add(title_padding);
    const title_center = title_topleft.add(title_dims.scale(0.5));

    self.menu_ui.commands.append(.{
        .label = .{
            .pos = title_center,
            .text = ImmUI.initLabel(title_text),
            .opt = title_opt,
        },
    }) catch unreachable;
    const version_text = config.version;
    const version_opt = draw.TextOpt{
        .color = .white,
        .size = 20,
    };
    self.menu_ui.commands.append(.{
        .label = .{
            .pos = title_center.add(v2f(title_dims.x * 0.5 + 5, 0)),
            .text = ImmUI.initLabel(version_text),
            .opt = version_opt,
        },
    }) catch unreachable;

    const btns_topleft = v2f(
        panel_topleft.x + (panel_dims.x - btn_dims.x) * 0.5,
        title_topleft.y + title_dims.y + title_padding.y,
    );
    var curr_btn_pos = btns_topleft;
    if (false) {
        if (menuUI.textButton(&self.menu_ui.commands, curr_btn_pos, "    New Run\n(Frank 4-slot)", btn_dims)) {
            try self.startNewRun(.frank_4_slot);
        }

        curr_btn_pos.y += btn_dims.y + btn_spacing;

        if (menuUI.textButton(&self.menu_ui.commands, curr_btn_pos, "      New Run\n(Mandy 3-mana)", btn_dims)) {
            try self.startNewRun(.mandy_3_mana);
        }
        curr_btn_pos.y += btn_dims.y + btn_spacing;
    }

    if (menuUI.textButton(&self.menu_ui.commands, curr_btn_pos, "      New Run\n(Crispin\nCrystal-picker)", btn_dims)) {
        try self.startNewRun(.crispin_picker);
    }
    curr_btn_pos.y += btn_dims.y + btn_spacing;

    if (false) {
        if (menuUI.textButton(&self.menu_ui.commands, curr_btn_pos, "Options", btn_dims)) {
            self.options_open = true;
        }
        curr_btn_pos.y += btn_dims.y + btn_spacing;
    }

    if (menuUI.textButton(&self.menu_ui.commands, curr_btn_pos, "Exit", btn_dims)) {
        plat.exit();
    }
}

fn update(self: *App) Error!void {
    if (self.options_open) {
        switch (try self.options.update()) {
            .close => self.options_open = false,
            else => {},
        }
    } else {
        switch (self.screen) {
            .menu => {
                try self.menuUpdate();
            },
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
        .menu => {
            plat.startRenderToTexture(self.render_texture);
            plat.setBlend(.render_tex_alpha);
            plat.clear(.gray);
            try ImmUI.render(&self.menu_ui.commands);
            plat.endRenderToTexture();
        },
        .run => {
            try self.run.render(self.render_texture);
        },
    }
    if (self.options_open) {
        try self.options.render(self.render_texture);
    }
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
