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
const Log = App.Log;
const Run = @import("Run.zig");
const Data = @import("Data.zig");
const menuUI = @import("menuUI.zig");
const ImmUI = @import("ImmUI.zig");
const Options = @This();

const ui_el_text_padding: V2f = v2f(5, 5);

pub const Display = struct {
    //monitor: i32 = 0, // TODO?
    mode: enum {
        windowed,
        borderless,
        fullscreen,
    } = .windowed,
    resolutions: std.BoundedArray(V2i, 24) = .{},
    resolutions_dropdown_open: bool = false,
    selected_resolution_idx: usize = 0,
    selected_resolution: V2i = .{},
    //vsync: bool = false, // TODO?
    pub const OptionSerialize = struct {
        mode: void,
        selected_resolution: void,
    };
};

pub const Controls = struct {
    pub const CastMethod = enum {
        left_click,
        quick_release,
        quick_press,
        pub const strings = std.EnumArray(CastMethod, []const u8).init(.{
            .left_click = "Left mouse click",
            .quick_release = "Release hotkey",
            .quick_press = "Press hotkey",
        });
    };
    cast_method: CastMethod = .quick_release,
    cast_method_dropdown_open: bool = false,
    //auto_self_cast: bool = true, // TODO?
    pub const OptionSerialize = struct {
        cast_method: void,
    };
};

pub const Kind = enum {
    controls,
    display,
};

controls: Controls = .{},
display: Display = .{},
kind_selected: Kind = .controls,

pub fn serialize(data: anytype, prefix: []const u8, file: std.fs.File, _: *Platform) void {
    const T = @TypeOf(data);
    inline for (std.meta.fields(T.OptionSerialize)) |s_field| {
        const field = utl.typeFieldByName(T, s_field.name);
        switch (@typeInfo(field.type)) {
            .@"enum" => |info| {
                file.writeAll("# Possible values:\n") catch {};
                inline for (info.fields) |efield| {
                    const e = utl.bufPrintLocal("# {s}\n", .{efield.name}) catch break;
                    file.writeAll(e) catch {};
                }
                const val_as_string = @tagName(@field(data, field.name));
                const line = utl.bufPrintLocal("{s}.{s}={s}\n", .{ prefix, field.name, val_as_string }) catch break;
                file.writeAll(line) catch break;
            },
            .@"struct" => {
                if (@hasDecl(field.type, "Serialize")) {
                    serialize(@field(data, field.name), prefix ++ "." ++ field.name, file);
                } else if (comptime std.mem.eql(u8, utl.typeBaseName(field.type), "V2i")) {
                    const v: V2i = @field(data, field.name);
                    const line = utl.bufPrintLocal("{s}.{s}={d}\n", .{ prefix, field.name, v }) catch break;
                    file.writeAll(line) catch break;
                } else {
                    @compileError("Idk how to serialize this struct");
                }
            },
            else => continue,
        }
    }
}

pub fn writeToTxt(self: *const Options, plat: *Platform) void {
    const options_file = std.fs.cwd().createFile("options.txt", .{}) catch {
        plat.log.warn("WARNING: Failed to open options.txt for writing\n", .{});
        return;
    };
    defer options_file.close();
    serialize(self.controls, "controls", options_file, plat);
    serialize(self.display, "display", options_file, plat);
}

pub fn initEmpty(plat: *Platform) Options {
    const ret = Options{};
    ret.writeToTxt(plat);
    return ret;
}

fn setValByName(plat: *Platform, T: type, data: *T, key: []const u8, val: []const u8) void {
    // check if we're at the leaf of the key  (key could be like controls.foo.bar, we do the actual setting at bar)
    switch (@typeInfo(T)) {
        .@"struct", .@"union" => {
            for (key, 0..) |c, i| {
                if (c == '.') {
                    const first_part_of_key = key[0..i];
                    const rest_of_key = key[i + 1 ..];
                    inline for (std.meta.fields(T)) |field| {
                        if (std.mem.eql(u8, first_part_of_key, field.name)) {
                            setValByName(plat, field.type, &@field(data, field.name), rest_of_key, val);
                            return;
                        }
                    } else {
                        plat.log.warn("{s}: Couldn't find key: \"{s}\"", .{ @src().fn_name, key });
                    }
                    return;
                }
            }
        },
        else => {},
    }

    switch (@typeInfo(T)) {
        .@"enum" => {
            if (std.meta.stringToEnum(T, val)) |v| {
                data.* = v;
            } else {
                plat.log.warn("{s}: Couldn't parse enum. key: \"{s}\", val: \"{s}\", type \"{s}\"", .{ @src().fn_name, key, val, @typeName(T) });
            }
        },
        .@"struct" => {
            if (comptime std.mem.eql(u8, utl.typeBaseName(T), "V2i")) {
                var v = V2i{};
                _ = V2i.parse(val, &v) catch {
                    plat.log.warn("{s}: Couldn't parse V2i key: \"{s}\", val: \"{s}\"", .{ @src().fn_name, key, val });
                };
                data.* = v;
                return;
            } else {
                inline for (std.meta.fields(T)) |f| {
                    if (std.mem.eql(u8, f.name, key)) {
                        setValByName(plat, f.type, &@field(data, f.name), "", val);
                        break;
                    }
                } else {
                    plat.log.warn("{s}: Couldn't parse key: \"{s}\", struct type \"{s}\"\n", .{ @src().fn_name, key, @typeName(T) });
                }
            }
        },
        else => {
            plat.log.warn("{s}: Couldn't parse key: \"{s}\", type \"{s}\"", .{ @src().fn_name, key, @typeName(T) });
        },
    }
}

pub fn updateScreenDims(plat: *Platform, dims: V2i) void {
    plat.screen_dims = dims;
    plat.screen_dims_f = dims.toV2f();
    // get ui scale - fit inside or equal screen dims
    var ui_scaling: i32 = 0;
    for (0..100) |_| {
        const ui_dims = core.min_resolution.scale(ui_scaling + 1);
        if (ui_dims.x > dims.x or ui_dims.y > dims.y) {
            break;
        }
        ui_scaling += 1;
    }
    plat.ui_scaling = utl.as(f32, ui_scaling);
    // get game scale
    if (false) {
        // cover screen
        var game_scaling: i32 = 1;
        for (0..100) |_| {
            const game_dims = core.min_resolution.scale(game_scaling);
            if (game_dims.x >= dims.x and game_dims.y >= dims.y) {
                plat.game_canvas_dims = game_dims;
                break;
            }
            const game_dims_wide = core.min_wide_resolution.scale(game_scaling);
            if (game_dims_wide.x >= dims.x and game_dims_wide.y >= dims.y) {
                plat.game_canvas_dims = game_dims_wide;
                break;
            }
            game_scaling += 1;
        }
        plat.game_scaling = utl.as(f32, game_scaling);
    } else {
        // fit into screen
        var game_scaling: i32 = 0;
        for (0..100) |_| {
            const game_dims = core.min_resolution.scale(game_scaling + 1);
            if (game_dims.x > dims.x and game_dims.y > dims.y) {
                plat.game_canvas_dims = core.min_resolution;
                break;
            }
            const game_dims_wide = core.min_wide_resolution.scale(game_scaling + 1);
            if (game_dims_wide.x > dims.x and game_dims_wide.y > dims.y) {
                plat.game_canvas_dims = core.min_wide_resolution;
                break;
            }
            game_scaling += 1;
        }
        plat.game_scaling = utl.as(f32, game_scaling);
    }
    plat.game_canvas_dims_f = plat.game_canvas_dims.toV2f();
    plat.game_canvas_screen_topleft_offset = plat.screen_dims_f.sub(plat.game_canvas_dims_f.scale(plat.game_scaling)).scale(0.5);
    plat.log.info("Scaling\n\tScreen: {}x{}\n\tGame: {}x{} scaled by {d}, offset by {d}", .{
        plat.screen_dims.x,      plat.screen_dims.y,
        plat.game_canvas_dims.x, plat.game_canvas_dims.y,
        plat.game_scaling,       plat.game_canvas_screen_topleft_offset,
    });

    const m_info = plat.getMonitorIdxAndDims();
    const m_dims = m_info.dims;
    plat.setWindowSize(dims);
    plat.setWindowPosition(m_dims.sub(dims).toV2f().scale(0.5).toV2i());
}

// this may be called when getPlat() doesn't work yet!
pub fn initTryLoad(plat: *App.Platform) Options {
    var ret = Options{};
    const options_file = std.fs.cwd().openFile("options.txt", .{}) catch return initEmpty(plat);
    const str = options_file.readToEndAlloc(plat.heap, 1024 * 1024) catch return initEmpty(plat);
    defer plat.heap.free(str);
    var line_it = std.mem.tokenizeScalar(u8, str, '\n');
    while (line_it.next()) |line_untrimmed| {
        const line = std.mem.trim(u8, line_untrimmed, &std.ascii.whitespace);
        if (line[0] == '#') continue;
        var equals_it = std.mem.tokenizeScalar(u8, line, '=');
        const key = equals_it.next() orelse continue;
        const val = equals_it.next() orelse continue;
        setValByName(plat, Options, &ret, key, val);
    }
    options_file.close();

    // fix up resolution
    {
        const resolutions = plat.getResolutions(&ret.display.resolutions.buffer);
        assert(resolutions.len > 0);
        ret.display.resolutions.resize(resolutions.len) catch unreachable;

        var best = resolutions[0];
        var best_idx: usize = 0;
        var best_diff = ret.display.selected_resolution.sub(resolutions[0]).mLen();
        for (resolutions[1..], 1..) |res, i| {
            const diff = ret.display.selected_resolution.sub(res).mLen();
            if (diff < best_diff) {
                best = res;
                best_idx = i;
                best_diff = diff;
            }
        }
        ret.display.selected_resolution = best;
        ret.display.selected_resolution_idx = best_idx;
    }

    ret.writeToTxt(plat);
    return ret;
}

const el_text_padding = v2f(4, 4);
const el_bg_color = Colorf.rgb(0.2, 0.2, 0.2);
const el_bg_color_hovered = Colorf.rgb(0.3, 0.3, 0.3);
const el_bg_color_selected = Colorf.rgb(0.4, 0.4, 0.4);

fn updateDisplay(self: *Options, cmd_buf: *ImmUI.CmdBuf, pos: V2f) Error!bool {
    var dirty: bool = false;
    const plat = App.getPlat();
    const data = App.getData();
    const font = data.fonts.get(.pixeloid);
    const text_opt = draw.TextOpt{
        .font = font,
        .size = font.base_size * utl.as(u32, plat.ui_scaling),
        .color = .white,
    };
    const ui_scaling = plat.ui_scaling;
    const mouse_pos = plat.getMousePosScreen();
    const mouse_clicked = plat.input_buffer.mouseBtnIsJustPressed(.left);
    const el_padding = el_text_padding.scale(ui_scaling);
    var curr_row_pos = pos;
    const row_height: f32 = utl.as(f32, text_opt.size) + el_padding.y * 2;
    {
        const cast_method_text = "Resolution:";
        const cast_method_text_dims = try plat.measureText(cast_method_text, text_opt);
        cmd_buf.appendAssumeCapacity(.{ .label = .{
            .pos = curr_row_pos,
            .text = ImmUI.initLabel(cast_method_text),
            .opt = text_opt,
        } });

        var dropdown_el_pos = pos.add(v2f(cast_method_text_dims.x + 4, 0));
        var dropdown_el_dims = try plat.measureText("10000x10000", text_opt);
        dropdown_el_dims = dropdown_el_dims.add(el_padding.scale(2));
        // selected
        cmd_buf.appendAssumeCapacity(.{ .rect = .{
            .pos = dropdown_el_pos,
            .dims = dropdown_el_dims,
            .opt = .{ .fill_color = el_bg_color_selected },
        } });
        const selected_res_str = try utl.bufPrintLocal("{d}x{d}", .{ self.display.selected_resolution.x, self.display.selected_resolution.y });
        cmd_buf.appendAssumeCapacity(.{ .label = .{
            .pos = dropdown_el_pos.add(el_padding),
            .text = ImmUI.initLabel(selected_res_str),
            .opt = text_opt,
        } });
        // open/close dropdown
        var mouse_clicked_inside_menu = false;
        if (mouse_clicked and geom.pointIsInRectf(mouse_pos, .{ .pos = dropdown_el_pos, .dims = dropdown_el_dims })) {
            self.display.resolutions_dropdown_open = !self.display.resolutions_dropdown_open;
            mouse_clicked_inside_menu = true;
        }
        dropdown_el_pos.y += dropdown_el_dims.y;
        var selection = self.display.selected_resolution;
        var selection_idx = self.display.selected_resolution_idx;
        if (self.display.resolutions_dropdown_open) {
            for (self.display.resolutions.constSlice(), 0..) |res, i| {
                const hovered = geom.pointIsInRectf(mouse_pos, .{ .pos = dropdown_el_pos, .dims = dropdown_el_dims });
                if (i == self.display.selected_resolution_idx) continue;
                cmd_buf.appendAssumeCapacity(.{ .rect = .{
                    .pos = dropdown_el_pos,
                    .dims = dropdown_el_dims,
                    .opt = .{
                        .fill_color = if (hovered) el_bg_color_hovered else el_bg_color,
                    },
                } });
                const res_str = try utl.bufPrintLocal("{d}x{d}", .{ res.x, res.y });
                cmd_buf.appendAssumeCapacity(.{ .label = .{
                    .pos = dropdown_el_pos.add(el_padding),
                    .text = ImmUI.initLabel(res_str),
                    .opt = text_opt,
                } });
                if (mouse_clicked and hovered) {
                    dirty = true;
                    selection = res;
                    selection_idx = i;
                    self.display.resolutions_dropdown_open = false;
                    mouse_clicked_inside_menu = true;
                    updateScreenDims(plat, selection);
                    App.get().reinitRenderTextures();
                }
                dropdown_el_pos.y += dropdown_el_dims.y;
            }
        }
        if (mouse_clicked and !mouse_clicked_inside_menu) {
            self.display.resolutions_dropdown_open = false;
        }
        self.display.selected_resolution_idx = selection_idx;
        self.display.selected_resolution = selection;
    }
    curr_row_pos.y += row_height;

    return dirty;
}

fn updateControls(self: *Options, cmd_buf: *ImmUI.CmdBuf, pos: V2f) Error!bool {
    var dirty: bool = false;
    const plat = App.getPlat();
    const data = App.getData();
    const font = data.fonts.get(.pixeloid);
    const text_opt = draw.TextOpt{
        .font = font,
        .size = font.base_size * utl.as(u32, plat.ui_scaling),
        .color = .white,
    };
    const ui_scaling = plat.ui_scaling;
    const mouse_pos = plat.getMousePosScreen();
    const mouse_clicked = plat.input_buffer.mouseBtnIsJustPressed(.left);
    const el_padding = el_text_padding.scale(ui_scaling);
    var curr_row_pos = pos;
    const row_height: f32 = utl.as(f32, text_opt.size) + el_padding.y * 2;
    {
        const cast_method_text = "Cast Method:";
        const cast_method_text_dims = try plat.measureText(cast_method_text, text_opt);
        cmd_buf.appendAssumeCapacity(.{ .label = .{
            .pos = curr_row_pos,
            .text = ImmUI.initLabel(cast_method_text),
            .opt = text_opt,
        } });

        var dropdown_el_pos = pos.add(v2f(cast_method_text_dims.x + 4, 0));
        var dropdown_el_dims = V2f{};
        for (Controls.CastMethod.strings.values) |str| {
            const str_dims = try plat.measureText(str, text_opt);
            if (str_dims.x > dropdown_el_dims.x) {
                dropdown_el_dims.x = str_dims.x;
            }
            if (str_dims.y > dropdown_el_dims.y) {
                dropdown_el_dims.y = str_dims.y;
            }
        }
        dropdown_el_dims = dropdown_el_dims.add(el_padding.scale(2));
        // selected
        cmd_buf.appendAssumeCapacity(.{ .rect = .{
            .pos = dropdown_el_pos,
            .dims = dropdown_el_dims,
            .opt = .{ .fill_color = el_bg_color_selected },
        } });
        cmd_buf.appendAssumeCapacity(.{ .label = .{
            .pos = dropdown_el_pos.add(el_padding),
            .text = ImmUI.initLabel(Controls.CastMethod.strings.get(self.controls.cast_method)),
            .opt = text_opt,
        } });
        // open/close dropdown
        var mouse_clicked_inside_menu = false;
        if (mouse_clicked and geom.pointIsInRectf(mouse_pos, .{ .pos = dropdown_el_pos, .dims = dropdown_el_dims })) {
            self.controls.cast_method_dropdown_open = !self.controls.cast_method_dropdown_open;
            mouse_clicked_inside_menu = true;
        }
        dropdown_el_pos.y += dropdown_el_dims.y;
        var selection = self.controls.cast_method;
        if (self.controls.cast_method_dropdown_open) {
            inline for (std.meta.fields(Controls.CastMethod)) |f| {
                const hovered = geom.pointIsInRectf(mouse_pos, .{ .pos = dropdown_el_pos, .dims = dropdown_el_dims });
                const cast_method: Controls.CastMethod = @enumFromInt(f.value);
                if (cast_method == self.controls.cast_method) comptime continue;
                cmd_buf.appendAssumeCapacity(.{ .rect = .{
                    .pos = dropdown_el_pos,
                    .dims = dropdown_el_dims,
                    .opt = .{
                        .fill_color = if (hovered) el_bg_color_hovered else el_bg_color,
                    },
                } });
                cmd_buf.appendAssumeCapacity(.{ .label = .{
                    .pos = dropdown_el_pos.add(el_padding),
                    .text = ImmUI.initLabel(Controls.CastMethod.strings.get(cast_method)),
                    .opt = text_opt,
                } });
                if (mouse_clicked and hovered) {
                    dirty = true;
                    selection = cast_method;
                    self.controls.cast_method_dropdown_open = false;
                    mouse_clicked_inside_menu = true;
                }
                dropdown_el_pos.y += dropdown_el_dims.y;
            }
        }
        if (mouse_clicked and !mouse_clicked_inside_menu) {
            self.controls.cast_method_dropdown_open = false;
        }
        self.controls.cast_method = selection;
    }
    curr_row_pos.y += row_height;

    return dirty;
}

pub const kind_rect_dims = v2f(300, 260);
pub const full_panel_padding = v2f(20, 20);
pub const top_bot_parts_height = 30;
pub const full_panel_dims = kind_rect_dims.add(v2f(0, top_bot_parts_height * 2)).add(full_panel_padding.scale(2));

pub fn update(self: *Options, cmd_buf: *ImmUI.CmdBuf) Error!enum { dont_close, close } {
    const plat = App.getPlat();
    const data = App.getData();
    const font = data.fonts.get(.pixeloid);
    const ui_scaling = plat.ui_scaling;

    const panel_dims = full_panel_dims.scale(ui_scaling);
    const kind_section_dims = kind_rect_dims.scale(ui_scaling);
    const panel_pos = plat.screen_dims_f.sub(panel_dims).scale(0.5);

    cmd_buf.appendAssumeCapacity(.{
        .rect = .{
            .pos = panel_pos,
            .dims = panel_dims,
            .opt = .{
                .fill_color = Colorf.rgb(0.1, 0.1, 0.1),
                .edge_radius = 0.1,
            },
        },
    });
    const padding = full_panel_padding.scale(ui_scaling);
    const selected_btn_dims = v2f(
        80,
        utl.as(f32, font.base_size) + 10,
    ).scale(ui_scaling);
    const selected_info = @typeInfo(Kind).@"enum";
    const num_selected_f = utl.as(f32, selected_info.fields.len);
    const selected_dims = v2f(panel_dims.x - padding.x * 2, selected_btn_dims.y);
    const selected_x_spacing = (selected_dims.x - (num_selected_f * selected_btn_dims.x)) / (num_selected_f - 1);
    var selected_curr_pos = panel_pos.add(padding);
    inline for (0..selected_info.fields.len) |i| {
        const kind: Kind = @enumFromInt(i);
        const enum_name = utl.enumToString(Kind, kind);
        const text = try utl.bufPrintLocal("{c}{s}", .{ std.ascii.toUpper(enum_name[0]), enum_name[1..] });
        if (menuUI.textButton(cmd_buf, selected_curr_pos, text, selected_btn_dims)) {
            self.kind_selected = kind;
        }
        selected_curr_pos.x += selected_btn_dims.x + selected_x_spacing;
    }

    const kind_section_pos = panel_pos.add(padding).add(v2f(0, top_bot_parts_height * ui_scaling));
    if (switch (self.kind_selected) {
        .controls => try self.updateControls(cmd_buf, kind_section_pos),
        .display => try self.updateDisplay(cmd_buf, kind_section_pos),
    }) {
        self.writeToTxt(plat);
    }

    const back_btn_pos = kind_section_pos.add(v2f(0, kind_section_dims.y));
    const back_btn_dims = v2f(60, top_bot_parts_height).scale(ui_scaling);
    if (menuUI.textButton(cmd_buf, back_btn_pos, "Back", back_btn_dims)) {
        return .close;
    }
    return .dont_close;
}
