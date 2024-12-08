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
const Options = @This();

pub const UIShortString = utl.BoundedString(32);

const ui_text_opt = draw.TextOpt{
    .color = .white,
    .size = 20,
};
const ui_el_text_padding: V2f = v2f(5, 5);

pub const ClickableLabel = struct {
    rect: geom.Rectf,
    text: UIShortString,
};

pub const UIElementType = enum {
    dropdown,
};

pub const UIElement = struct {
    rect: geom.Rectf,
    value_rect: geom.Rectf = .{},
    kind: union(UIElementType) {
        dropdown: struct {
            label: UIShortString,
            items: std.BoundedArray(ClickableLabel, 8),
            selected_idx: usize,
            menu_open: bool = false,
        },
    },
};

pub const CastMethod = enum {
    left_click,
    quick_press,
    quick_release,
};

cast_method: CastMethod = .quick_release,
// keep this at the end cos the other fields are parsed at comptime in order
ui: struct {
    rect: geom.Rectf = .{},
    labels_width: f32 = 0, // values width = rect.dims.x - labels_width
    elements: std.BoundedArray(UIElement, 8) = .{},
    back_button: menuUI.Button = .{},
} = .{},

pub fn writeToTxt(self: Options) void {
    const options_file = std.fs.cwd().createFile("options.txt", .{}) catch {
        Log.warn("WARNING: Failed to open options.txt for writing\n", .{});
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
                else => comptime continue,
            }
        }
    }
    Log.warn("WARNING: Options parse fail. key: \"{s}\", val: \"{s}\"\n", .{ key, val });
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
    ret.layoutUI();
    return ret;
}

pub fn update(self: *Options) Error!enum { dont_close, close } {
    const plat = App.getPlat();
    _ = plat;
    for (self.ui.elements.slice()) |el| {
        switch (el.kind) {
            .dropdown => |dropdown| {
                _ = dropdown;
            },
        }
    }
    if (self.ui.back_button.isClicked()) {
        return .close;
    }
    return .dont_close;
}

pub fn render(self: *Options, render_texture: Platform.RenderTexture2D) Error!void {
    const plat = App.getPlat();

    plat.startRenderToTexture(render_texture);
    plat.setBlend(.render_tex_alpha);

    plat.rectf(self.ui.rect.pos, self.ui.rect.dims, .{
        .fill_color = Colorf.rgba(0.1, 0.1, 0.1, 0.8),
    });

    const origin = self.ui.rect.pos;

    for (self.ui.elements.slice()) |el| {
        plat.rectf(origin.add(el.value_rect.pos), el.value_rect.dims, .{
            .fill_color = null,
            .outline = .{ .color = Colorf.rgb(0.8, 0.8, 0.0) },
        });
        switch (el.kind) {
            .dropdown => |dropdown| {
                const label_pos = origin.add(el.rect.pos).add(ui_el_text_padding);
                try plat.textf(label_pos, "{s}", .{dropdown.label.constSlice()}, ui_text_opt);
                const selected: ClickableLabel = dropdown.items.get(dropdown.selected_idx);
                try plat.textf(origin.add(el.value_rect.pos.add(ui_el_text_padding)), "{s}", .{selected.text.constSlice()}, ui_text_opt);
                //const el_origin = origin.add(el.rect.pos);
            },
        }
    }

    try self.ui.back_button.render();
}

pub fn layoutUI(self: *Options) void {
    const plat = App.getPlat();
    self.ui.elements.len = 0;

    var element_label_max_width: f32 = 0;
    var element_value_max_width: f32 = 0;
    var curr_element_pos: V2f = .{};

    inline for (std.meta.fields(Options)) |sfield| {
        const el = blk: switch (@typeInfo(sfield.type)) {
            .@"enum" => |info| {
                var dropdown_el: UIElement = .{
                    .rect = .{ .pos = curr_element_pos },
                    .value_rect = .{ .pos = curr_element_pos },
                    .kind = .{
                        .dropdown = .{
                            .label = UIShortString.fromSlice(sfield.name) catch unreachable,
                            .items = .{},
                            .selected_idx = if (sfield.default_value) |vptr| @intFromEnum(@as(*const sfield.type, @ptrCast(vptr)).*) else 0,
                        },
                    },
                };
                const el_label_dims = plat.measureText(sfield.name, ui_text_opt) catch @panic("measure text fail");
                dropdown_el.rect.dims.y = el_label_dims.y + ui_el_text_padding.y * 2;
                element_label_max_width = @max(element_label_max_width, el_label_dims.x);
                curr_element_pos.y += dropdown_el.rect.dims.y;

                var curr_label_pos: V2f = .{};
                var label_max_width: f32 = 0;
                inline for (info.fields) |efield| {
                    var label: ClickableLabel = .{
                        .text = UIShortString.fromSlice(efield.name) catch unreachable,
                        .rect = .{
                            .pos = curr_label_pos,
                        },
                    };
                    const label_dims = plat.measureText(efield.name, ui_text_opt) catch @panic("measure text fail");
                    label.rect.dims.y = label_dims.y + ui_el_text_padding.y * 2;
                    curr_label_pos.y += label.rect.dims.y;
                    label_max_width = @max(label_dims.x, label_max_width);
                    dropdown_el.kind.dropdown.items.append(label) catch comptime continue;
                }
                element_value_max_width = @max(element_value_max_width, label_max_width);
                for (dropdown_el.kind.dropdown.items.slice()) |*label| {
                    label.rect.dims.x = label_max_width;
                }
                break :blk dropdown_el;
            },
            else => comptime continue,
        };
        self.ui.elements.append(el) catch comptime continue;
    }
    const total_width = element_label_max_width + element_value_max_width + ui_el_text_padding.x * 4;
    const label_total_width = element_label_max_width + ui_el_text_padding.x * 2;
    for (self.ui.elements.slice()) |*el| {
        el.rect.dims.x = total_width;
        el.value_rect.pos.x += label_total_width;
        el.value_rect.dims = v2f(total_width - label_total_width, el.rect.dims.y);
    }
    // back button
    {
        const btn_dims = v2f(80, 30);
        self.ui.back_button = .{
            .text_padding = ui_el_text_padding,
            .text_rel_pos = btn_dims.scale(0.5),
            .text_opt = .{
                .center = true,
            },
            .poly_opt = .{
                .fill_color = .orange,
            },
            .clickable_rect = .{
                .rect = .{
                    .pos = curr_element_pos.add(ui_el_text_padding),
                    .dims = btn_dims,
                },
            },
        };
        self.ui.back_button.text = @TypeOf(self.ui.back_button.text).fromSlice("Back") catch unreachable;
        curr_element_pos.y += btn_dims.y + ui_el_text_padding.y * 2;
    }
    // ui rect finally
    self.ui.rect = .{
        .dims = v2f(total_width, curr_element_pos.y),
    };
    self.ui.labels_width = element_label_max_width + ui_el_text_padding.y * 2;
    // TODO ??
    // center it?
    self.ui.rect.pos = plat.screen_dims_f.sub(self.ui.rect.dims).scale(0.5);
    self.ui.back_button.clickable_rect.rect.pos = self.ui.back_button.clickable_rect.rect.pos.add(self.ui.rect.pos);
}
