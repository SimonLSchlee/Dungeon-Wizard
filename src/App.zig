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
const sounds = @import("sounds.zig");
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

data: *Data = undefined,
options: Options = undefined,
sfx_player: sounds.SFXPlayer = undefined,
music_player: sounds.MusicPlayer = undefined,
curr_tick: i64 = 0,
screen: enum {
    menu,
    run,
} = .menu,
paused: bool = false,
options_open: bool = false,
run: Run = undefined,
menu_ui: struct {
    commands: ImmUI.CmdBuf = .{},
} = .{},
game_render_texture: Platform.RenderTexture2D = undefined,
ui_render_texture: Platform.RenderTexture2D = undefined,

pub fn resolutionChanged(self: *App) void {
    const plat = getPlat();
    plat.destroyRenderTexture(self.game_render_texture);
    plat.destroyRenderTexture(self.ui_render_texture);
    self.game_render_texture = plat.createRenderTexture("app_game", plat.game_canvas_dims);
    self.ui_render_texture = plat.createRenderTexture("app_ui", plat.screen_dims);

    if (self.screen == .run) {
        self.run.resolutionChanged();
    }
}

export fn appInit(plat: *Platform) *anyopaque {
    // everything depends on plat global
    _plat = plat;

    Log.info("Init app {s}", .{config.version});

    Log.info("Allocating App: {}KiB", .{@sizeOf(App) / 1024});

    var app = plat.heap.create(App) catch @panic("Out of memory");
    app.* = .{
        .options = Options.initTryLoad(plat),
        .data = Data.init() catch @panic("Failed to init data"),
        .sfx_player = sounds.SFXPlayer.init(),
        .music_player = sounds.MusicPlayer.init(),
    };

    // populate _app here, Room.init() uses it, and data.reload
    _app = app;

    app.data.reload() catch @panic("Failed to load data");

    app.game_render_texture = plat.createRenderTexture("app_game", plat.game_canvas_dims);
    app.ui_render_texture = plat.createRenderTexture("app_ui", plat.screen_dims);

    //app.startNewRun(._4_slot_frank) catch @panic("Failed to go straight into run");

    return app;
}

pub fn staticAppInit(plat: *Platform) callconv(.C) *anyopaque {
    return appInit(plat);
}

pub export fn appReload(app_ptr: *anyopaque, plat: *Platform) void {
    _plat = plat;
    const app: *App = @ptrCast(@alignCast(app_ptr));
    _app = app;
    // data reload uses app and plat
    app.data.reload() catch @panic("Failed to reload data");
}

pub fn staticAppReload(app_ptr: *anyopaque, plat: *Platform) callconv(.C) void {
    return appReload(app_ptr, plat);
}

pub export fn appTick() void {
    var app = App.get();
    app.update() catch @panic("fail appTick");
}

pub fn staticAppTick() callconv(.C) void {
    appTick();
}

pub export fn appRender() void {
    var app = App.get();
    app.render() catch @panic("fail appRender");
}

pub fn staticAppRender() callconv(.C) void {
    appRender();
}

fn startNewRun(self: *App, mode: Run.Mode) Error!void {
    _ = try Run.initRandom(&self.run, mode);
    try self.run.startRun();
    self.screen = .run;
    if (false) {
        const Ref = struct {
            var dungongnu = Data.Ref(Data.Sound).init("dungongnu");
        };
        const plat = getPlat();
        plat.playSound(Ref.dungongnu.get().sound);
    }
}

pub fn deinit(self: *App) void {
    const plat = getPlat();
    self.run.deinit();
    plat.destroyRenderTexture(self.render_texture);
    plat.heap.destroy(self);
}

fn menuUpdate(self: *App) Error!void {
    const plat = getPlat();
    const data = self.data;
    const ui_scaling = plat.ui_scaling;
    const title_text = "Dungeon Wizard";
    const title_font = data.fonts.get(.pixeloid);
    const title_opt = draw.TextOpt{
        .center = true,
        .color = .white,
        .font = title_font,
        .size = title_font.base_size * utl.as(u32, ui_scaling + 2),
    };
    const title_dims = try plat.measureText(title_text, title_opt);
    const btn_dims = v2f(85, 45).scale(ui_scaling);
    const title_padding = v2f(55, 25).scale(ui_scaling);
    const btn_spacing: f32 = 10 * ui_scaling;
    const bottom_spacing: f32 = 20 * ui_scaling;
    const num_buttons = 4;
    const panel_dims = v2f(
        title_dims.x + title_padding.x * 2,
        title_dims.y + title_padding.y * 2 + btn_dims.y * num_buttons + btn_spacing * (num_buttons - 1) + bottom_spacing,
    );
    const panel_topleft = plat.screen_dims_f.sub(panel_dims).scale(0.5);
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
        .font = title_font,
        .size = title_font.base_size * utl.as(u32, ui_scaling),
    };
    self.menu_ui.commands.append(.{
        .label = .{
            .pos = title_center.add(v2f(title_dims.x * 0.5 + 5 * ui_scaling, 0)),
            .text = ImmUI.initLabel(version_text),
            .opt = version_opt,
        },
    }) catch unreachable;

    const btns_topleft = v2f(
        panel_topleft.x + (panel_dims.x - btn_dims.x) * 0.5,
        title_topleft.y + title_dims.y + title_padding.y,
    );
    var curr_btn_pos = btns_topleft;

    if (menuUI.textButtonEx(&self.menu_ui.commands, curr_btn_pos, "   New Run\n(Harriet\nHoarder)", btn_dims, ui_scaling, .yellow)) {
        try self.startNewRun(.harriet_hoarder);
    }
    curr_btn_pos.y += btn_dims.y + btn_spacing;

    if (menuUI.textButtonEx(&self.menu_ui.commands, curr_btn_pos, "   New Run\n(Crispin\nCrystal-picker)", btn_dims, ui_scaling, .orange)) {
        try self.startNewRun(.crispin_picker);
    }
    curr_btn_pos.y += btn_dims.y + btn_spacing;

    if (false) {
        if (menuUI.textButton(&self.menu_ui.commands, curr_btn_pos, "    New Run\n(Frank 4-slot)", btn_dims, ui_scaling)) {
            try self.startNewRun(.frank_4_slot);
        }

        curr_btn_pos.y += btn_dims.y + btn_spacing;
        if (menuUI.textButton(&self.menu_ui.commands, curr_btn_pos, "      New Run\n(Mandy 3-mana)", btn_dims, ui_scaling)) {
            try self.startNewRun(.mandy_3_mana);
        }
        curr_btn_pos.y += btn_dims.y + btn_spacing;
    }

    if (menuUI.textButton(&self.menu_ui.commands, curr_btn_pos, "Options", btn_dims, ui_scaling)) {
        self.options_open = true;
    }
    curr_btn_pos.y += btn_dims.y + btn_spacing;

    if (menuUI.textButton(&self.menu_ui.commands, curr_btn_pos, "Exit", btn_dims, ui_scaling)) {
        plat.exit();
    }
}

fn pauseMenuUpdate(self: *App) Error!void {
    const plat = getPlat();
    const data = self.data;
    const ui_scaling = plat.ui_scaling;
    const title_font = data.fonts.get(.pixeloid);
    const title_text = "Iiiiits a pause menu";
    const title_opt = draw.TextOpt{
        .center = true,
        .color = .white,
        .size = title_font.base_size * utl.as(u32, ui_scaling + 1),
        .font = title_font,
        .smoothing = .none,
    };
    const title_dims = try plat.measureText(title_text, title_opt);
    const btn_dims = v2f(70, 30).scale(ui_scaling);
    const title_padding = v2f(15, 15).scale(ui_scaling);
    const btn_spacing: f32 = 10 * ui_scaling;
    const bottom_spacing: f32 = 25 * ui_scaling;
    const num_buttons = 5;
    const panel_dims = v2f(
        title_dims.x + title_padding.x * 2,
        title_dims.y + title_padding.y * 2 + btn_dims.y * num_buttons + btn_spacing * (num_buttons - 1) + bottom_spacing,
    );
    const panel_topleft = plat.screen_dims_f.sub(panel_dims).scale(0.5);
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

    const btns_topleft = v2f(
        panel_topleft.x + (panel_dims.x - btn_dims.x) * 0.5,
        title_topleft.y + title_dims.y + title_padding.y,
    );
    var curr_btn_pos = btns_topleft;

    if (menuUI.textButton(&self.menu_ui.commands, curr_btn_pos, "Resume", btn_dims, ui_scaling)) {
        self.paused = false;
    }
    curr_btn_pos.y += btn_dims.y + btn_spacing;

    if (menuUI.textButton(&self.menu_ui.commands, curr_btn_pos, "Options", btn_dims, ui_scaling)) {
        self.options_open = true;
    }
    curr_btn_pos.y += btn_dims.y + btn_spacing;

    if (menuUI.textButton(&self.menu_ui.commands, curr_btn_pos, "New Run", btn_dims, ui_scaling)) {
        self.paused = false;
        try self.startNewRun(.crispin_picker);
    }
    curr_btn_pos.y += btn_dims.y + btn_spacing;

    if (menuUI.textButton(&self.menu_ui.commands, curr_btn_pos, "Abandon\n(Main Menu)", btn_dims, ui_scaling)) {
        self.paused = false;
        self.run.deinit();
        self.screen = .menu;
    }
    curr_btn_pos.y += btn_dims.y + btn_spacing;

    if (menuUI.textButton(&self.menu_ui.commands, curr_btn_pos, "Abandon\n(Exit)", btn_dims, ui_scaling)) {
        self.paused = false;
        plat.exit();
    }

    curr_btn_pos.y += btn_dims.y + btn_spacing + 10 * ui_scaling;
    const seed_text = try utl.bufPrintLocal("Run seed: {x:}", .{self.run.seed});
    const seed_opt = draw.TextOpt{
        .center = true,
        .color = .white,
        .size = title_font.base_size * utl.as(u32, ui_scaling),
        .font = title_font,
        .smoothing = .none,
    };
    self.menu_ui.commands.append(.{
        .label = .{
            .pos = v2f(title_center.x, curr_btn_pos.y),
            .text = ImmUI.initLabel(seed_text),
            .opt = seed_opt,
        },
    }) catch unreachable;
}

fn update(self: *App) Error!void {
    self.menu_ui.commands.clear();
    if (self.options_open) {
        switch (try self.options.update(&self.menu_ui.commands)) {
            .close => self.options_open = false,
            else => {},
        }
    } else {
        switch (self.screen) {
            .menu => {
                try self.menuUpdate();
            },
            .run => {
                if (getPlat().input_buffer.keyIsJustPressed(.escape)) {
                    self.paused = !self.paused;
                }
                if (self.paused) {
                    try self.pauseMenuUpdate();
                } else {
                    try self.run.update();
                }
            },
        }
    }
    self.options.alwaysUpdate();
    self.sfx_player.update();
    self.curr_tick += 1;
}

fn render(self: *App) Error!void {
    const plat = getPlat();
    plat.clear(.black);

    switch (self.screen) {
        .menu => {
            plat.startRenderToTexture(self.ui_render_texture);
            plat.setBlend(.render_tex_alpha);
            plat.clear(.gray);
            try ImmUI.render(&self.menu_ui.commands);
            plat.endRenderToTexture();
        },
        .run => {
            try self.run.render(self.ui_render_texture, self.game_render_texture);
            if (self.paused) {
                plat.startRenderToTexture(self.ui_render_texture);
                plat.setBlend(.render_tex_alpha);
                try ImmUI.render(&self.menu_ui.commands);
                plat.endRenderToTexture();
            }
            plat.texturef(plat.game_canvas_screen_topleft_offset, self.game_render_texture.texture, .{
                .flip_y = true,
                .smoothing = .none,
                .uniform_scaling = plat.game_scaling,
            });
        },
    }

    if (!debug.hide_ui) {
        plat.texturef(.{}, self.ui_render_texture.texture, .{
            .flip_y = true,
            .smoothing = .none,
        });
    }

    if (debug.show_mouse_pos) {
        try plat.textf(v2f(10, 10), "mouse screen: {d}", .{plat.getMousePosScreen()}, .{ .color = .white });
        if (self.screen == .run) {
            try plat.textf(v2f(10, 40), "mouse world: {d}", .{plat.getMousePosWorld(self.run.room.camera)}, .{ .color = .white });
        }
    }
}

pub fn copyString(allocator: *std.mem.Allocator, str: []const u8) []u8 {
    const ptr = allocator.alloc(u8, str.len) catch @panic("OOM");
    std.mem.copyForwards(u8, ptr, str);
    return ptr;
}
