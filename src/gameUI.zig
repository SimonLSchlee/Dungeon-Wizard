const std = @import("std");
const utl = @import("util.zig");

pub const Platform = @import("raylib.zig");
const core = @import("core.zig");
const Error = core.Error;
const Key = core.Key;
const debug = @import("debug.zig");
const assert = debug.assert;
const draw = @import("draw.zig");
const Colorf = draw.Colorf;
const geom = @import("geometry.zig");
const V2f = @import("V2f.zig");
const v2f = V2f.v2f;
const V2i = @import("V2i.zig");
const v2i = V2i.v2i;

const App = @import("App.zig");
const getPlat = App.getPlat;
const Data = @import("Data.zig");
const Room = @import("Room.zig");
const Run = @import("Run.zig");
const Thing = @import("Thing.zig");
const Spell = @import("Spell.zig");
const Options = @import("Options.zig");
const sprites = @import("sprites.zig");
const Item = @import("Item.zig");
const player = @import("player.zig");
const menuUI = @import("menuUI.zig");
const ImmUI = @import("ImmUI.zig");
const Tooltip = @import("Tooltip.zig");

const slot_bg_color = Colorf.rgb(0.07, 0.05, 0.05);

pub const max_spell_slots = 6;
pub const max_item_slots = 8;

pub const bottom_screen_margin: f32 = 6;

pub const UISlot = struct {
    command: Options.Controls.InputBinding.Command,
    key_rect_pos: V2f = .{},
    cooldown_timer: ?utl.TickCounter = null,
    hover_timer: utl.TickCounter = utl.TickCounter.init(15),
    long_hover: menuUI.LongHover = .{},
    rect: geom.Rectf = .{},
    clicked: bool = false,
    hovered: bool = false,

    pub fn init(command: Options.Controls.InputBinding.Command) UISlot {
        return .{
            .command = command,
        };
    }

    pub fn unqRectHoverClick(slot: *UISlot, cmd_buf: *ImmUI.CmdBuf, enabled: bool, poly_opt: ?draw.PolyOpt) Error!bool {
        const plat = getPlat();
        const mouse_pos = plat.getMousePosScreen();
        slot.hovered = geom.pointIsInRectf(mouse_pos, slot.rect);
        slot.clicked = slot.hovered and plat.input_buffer.mouseBtnIsJustPressed(.left);

        _ = slot.long_hover.update(slot.hovered);

        cmd_buf.append(.{ .rect = .{
            .pos = slot.rect.pos,
            .dims = slot.rect.dims,
            .opt = if (poly_opt) |opt| opt else .{
                .fill_color = slot_bg_color,
                .edge_radius = 0.2,
            },
        } }) catch @panic("Fail to append rect cmd");

        return enabled and slot.hovered and slot.clicked and geom.pointIsInRectf(mouse_pos, slot.rect);
    }

    pub fn unqCooldownTimer(slot: *UISlot, cmd_buf: *ImmUI.CmdBuf) Error!void {
        if (slot.cooldown_timer) |*timer| {
            if (timer.running) {
                menuUI.unqSectorTimer(
                    cmd_buf,
                    slot.rect.pos.add(slot.rect.dims.scale(0.5)),
                    slot.rect.dims.x * 0.5 * 0.7,
                    timer,
                    .{ .fill_color = .blue },
                );
            }
        }
    }

    pub fn unqHotKey(slot: *UISlot, cmd_buf: *ImmUI.CmdBuf, enabled: bool) Error!bool {
        const maybe_binding = App.get().options.controls.getBindingByCommand(slot.command);
        var ret = false;

        if (maybe_binding) |binding| {
            const data = App.get().data;
            const plat = getPlat();
            const ui_scaling: f32 = plat.ui_scaling;

            if (binding.inputs.len == 0) return false;
            for (binding.inputs.constSlice()) |b| switch (b) {
                .mouse_button => |btn| ret = ret or plat.input_buffer.mouseBtnIsJustPressed(btn),
                .keyboard_key => |key| ret = ret or plat.input_buffer.keyIsJustPressed(key),
            };
            const first_binding = binding.inputs.buffer[0];
            const key_color = if (enabled) Colorf.white else Colorf.gray;

            // hotkey
            const font = data.fonts.get(.pixeloid);
            const key_text_opt = draw.TextOpt{
                .color = key_color,
                .size = font.base_size * utl.as(u32, ui_scaling),
                .font = font,
                .smoothing = .none,
            };
            const key_str = try utl.bufPrintLocal("[{s}]", .{first_binding.getIconText()});
            const str_sz = try plat.measureText(key_str, key_text_opt);
            cmd_buf.append(.{ .rect = .{
                .pos = slot.key_rect_pos,
                .dims = str_sz.add(V2f.splat(4).scale(ui_scaling)),
                .opt = .{
                    .fill_color = Colorf.black.fade(0.7),
                    .edge_radius = 0.25,
                },
            } }) catch @panic("Fail to append label cmd");
            cmd_buf.append(.{ .label = .{
                .pos = slot.key_rect_pos.add(v2f(2, 2).scale(ui_scaling)),
                .text = ImmUI.initLabel(key_str),
                .opt = key_text_opt,
            } }) catch @panic("Fail to append label cmd");
        }

        return ret;
    }
};

pub fn getItemsRects() std.BoundedArray(geom.Rectf, max_item_slots) {
    const plat = getPlat();
    const ui_scaling = plat.ui_scaling;
    const item_slot_dims = v2f(24, 24).scale(ui_scaling);
    const item_slot_spacing: V2f = v2f(4, 10).scale(ui_scaling);
    const items_margin: V2f = v2f(12, 8).scale(ui_scaling);

    var rects = std.BoundedArray(geom.Rectf, max_item_slots){};
    // items bottom left
    const max_items_rows: usize = 2;
    const max_items_per_row = max_item_slots / max_items_rows;
    const max_items_dims = v2f(
        utl.as(f32, max_items_per_row) * (item_slot_dims.x + item_slot_spacing.x) - item_slot_spacing.x,
        utl.as(f32, max_items_rows) * (item_slot_dims.y + item_slot_spacing.y) - item_slot_spacing.y,
    );
    const items_topleft = v2f(
        items_margin.x,
        plat.screen_dims_f.y - bottom_screen_margin * ui_scaling - max_items_dims.y,
    );
    for (0..max_items_rows) |j| {
        const y_off = (item_slot_dims.x + item_slot_spacing.y) * utl.as(f32, j);
        for (0..max_items_per_row) |i| {
            const x_off = (item_slot_dims.x + item_slot_spacing.x) * utl.as(f32, i);
            rects.appendAssumeCapacity(.{
                .pos = items_topleft.add(v2f(x_off, y_off)),
                .dims = item_slot_dims,
            });
        }
    }

    return rects;
}

// unq == update and queue (render)
// Handle all updating and rendering of a generic action Slot, returning a CastMethod if it was activated
pub fn unqSlot(cmd_buf: *ImmUI.CmdBuf, tooltip_cmd_buf: *ImmUI.CmdBuf, slot: *Slots.Slot, caster: *const Thing, run: *Run) Error!?Options.Controls.CastMethod {
    const data = App.get().data;
    const plat = getPlat();
    const ui_scaling: f32 = plat.ui_scaling;
    const room = &run.room;

    var ret: ?Options.Controls.CastMethod = null;
    const mouse_pos = plat.getMousePosScreen();
    const hovered = geom.pointIsInRectf(mouse_pos, slot.rect);
    const clicked = hovered and plat.input_buffer.mouseBtnIsJustPressed(.left);
    const slot_enabled = Slots.slotIsEnabled(slot, caster);
    const can_activate_slot = Slots.canActivateSlot(slot, run, caster);
    const bg_color = slot_bg_color;
    var slot_contents_pos = slot.rect.pos;
    var border_color = Colorf.darkgray;
    var key_color = Colorf.gray;

    // background rect
    if (can_activate_slot and hovered) {
        // TODO animate
        slot_contents_pos = slot.rect.pos.add(v2f(0, -5));
    }
    cmd_buf.append(.{ .rect = .{
        .pos = slot.rect.pos,
        .dims = slot.rect.dims,
        .opt = .{
            .fill_color = bg_color,
            .edge_radius = 0.2,
        },
    } }) catch @panic("Fail to append rect cmd");

    // slot contents
    if (slot_enabled) {
        const kind_data = slot.kind.?;

        if (can_activate_slot) {
            key_color = .white;
            border_color = if (slot.selection_kind) |s| Slots.SelectionKind.colors.get(s) else Colorf.cyan.fade(0.8);
            // activated this frame?
            var activated = false;
            if (hovered and clicked) {
                ret = .left_click;
                activated = true;
            } else if (plat.input_buffer.keyIsJustPressed(slot.key)) {
                ret = App.get().options.controls.cast_method;
                activated = true;
            }
            if (activated) {
                // auto-target self-cast and discard
                switch (kind_data) {
                    .pause => {
                        ret = .quick_release;
                    },
                    .action => |a| switch (a) {
                        .discard => ret = .quick_release,
                        inline else => |k| {
                            if (@hasField(@TypeOf(k), "targeting_data")) {
                                if (k.targeting_data.kind == .self) {
                                    ret = .quick_release;
                                }
                            }
                        },
                    },
                }
            }

            // border
            if (slot.selection_kind != null) {
                var border_rect = slot.rect;
                var border_thickness: f32 = 4;
                var border_edge_radius: f32 = 0.2;
                switch (kind_data) {
                    .action => |a| switch (a) {
                        .spell => {
                            border_rect = .{
                                .pos = slot_contents_pos.add(v2f(2, 2)),
                                .dims = slot.rect.dims.sub(v2f(4, 4)),
                            };
                            border_thickness = 6;
                            border_edge_radius = 0.12;
                        },
                        else => {},
                    },
                    else => {},
                }
                cmd_buf.appendAssumeCapacity(.{ .rect = .{
                    .pos = border_rect.pos,
                    .dims = border_rect.dims,
                    .opt = .{
                        .fill_color = null,
                        .outline = .{
                            .color = border_color,
                            .thickness = border_thickness,
                        },
                        .edge_radius = border_edge_radius,
                    },
                } });
            }
        }

        // card/icon
        switch (kind_data) {
            .pause => {
                const sprite_name = if (room.paused) Data.MiscIcon.hourglass_down else Data.MiscIcon.hourglass_up;
                const info = sprites.RenderIconInfo{ .frame = data.misc_icons.getRenderFrame(sprite_name).? };
                try info.unqRender(cmd_buf, slot_contents_pos, ui_scaling);
            },
            .action => |a| switch (a) {
                .discard => {
                    const info = sprites.RenderIconInfo{ .frame = data.misc_icons.getRenderFrame(.discard).? };
                    try info.unqRender(cmd_buf, slot_contents_pos, ui_scaling);
                },
                .spell => |*spell| {
                    // TODO maybe?
                    //const scaling = if (slot.is_long_hovered) ui_scaling + 1 else ui_scaling;
                    spell.unqRenderCard(cmd_buf, slot_contents_pos, caster, ui_scaling);
                },
                .item => |*item| {
                    try item.unqRenderIcon(cmd_buf, slot_contents_pos, ui_scaling);
                },
            },
        }
        // tooltip
        if (slot.long_hover.update(hovered)) {
            const tooltip_scaling: f32 = plat.ui_scaling;
            const tooltip_pos = slot.rect.pos.add(v2f(slot.rect.dims.x, 0));
            switch (kind_data) {
                .pause => {
                    const tt = Tooltip{
                        .title = Tooltip.Title.fromSlice("Pause") catch unreachable,
                    };
                    try tt.unqRender(tooltip_cmd_buf, tooltip_pos, tooltip_scaling);
                },
                .action => |a| switch (a) {
                    .discard => {
                        const tt = Tooltip{
                            .title = Tooltip.Title.fromSlice("Discard hand") catch unreachable,
                        };
                        try tt.unqRender(tooltip_cmd_buf, tooltip_pos, tooltip_scaling);
                    },
                    .spell => |*spell| {
                        try spell.unqRenderTooltip(tooltip_cmd_buf, tooltip_pos, tooltip_scaling);
                    },
                    .item => |*item| {
                        try item.unqRenderTooltip(tooltip_cmd_buf, tooltip_pos, tooltip_scaling);
                    },
                },
            }
        }
    }
    if (slot.cooldown_timer) |*timer| {
        // NOTE rn the timers are ticked in updateTimerAndDrawSpell, that's fine...
        if (timer.running) {
            menuUI.unqSectorTimer(
                cmd_buf,
                slot.rect.pos.add(slot.rect.dims.scale(0.5)),
                slot.rect.dims.x * 0.5 * 0.7,
                timer,
                .{ .fill_color = .blue },
            );
        }
    }

    // hotkey
    const font = data.fonts.get(.pixeloid);
    const key_text_opt = draw.TextOpt{
        .color = key_color,
        .size = font.base_size * utl.as(u32, ui_scaling),
        .font = font,
        .smoothing = .none,
    };
    const key_str = slot.key_str.constSlice();
    const str_sz = try plat.measureText(key_str, key_text_opt);
    cmd_buf.append(.{ .rect = .{
        .pos = slot.key_rect_pos,
        .dims = str_sz.add(V2f.splat(4).scale(ui_scaling)),
        .opt = .{
            .fill_color = Colorf.black.fade(0.7),
            .edge_radius = 0.25,
        },
    } }) catch @panic("Fail to append label cmd");
    cmd_buf.append(.{ .label = .{
        .pos = slot.key_rect_pos.add(v2f(2, 2).scale(ui_scaling)),
        .text = ImmUI.initLabel(key_str),
        .opt = key_text_opt,
    } }) catch @panic("Fail to append label cmd");

    return ret;
}

// game slots
pub const Slots = struct {
    pub const SelectionKind = enum {
        selected,
        buffered,

        pub const colors = std.EnumArray(SelectionKind, Colorf).init(.{
            .selected = Colorf.orange,
            .buffered = Colorf.green,
        });
    };
    pub const Slot = struct {
        pub const Kind = enum {
            action,
            pause,
        };
        pub const KindData = union(Kind) {
            action: player.Action.KindData,
            pause,
        };
        pub const KeyStr = utl.BoundedString(8);

        idx: usize,
        key: core.Key,
        key_str: KeyStr,
        key_rect_pos: V2f = .{},
        kind: ?KindData = null,
        cooldown_timer: ?utl.TickCounter = null,
        hover_timer: utl.TickCounter = utl.TickCounter.init(15),
        long_hover: menuUI.LongHover = .{},
        selection_kind: ?SelectionKind = null,
        rect: geom.Rectf = .{},
    };

    pub const text_box_padding = V2f.splat(2);

    pub const spell_idx_to_key = [max_spell_slots]core.Key{ .q, .w, .e, .r, .t, .y };
    pub const spell_idx_to_key_str = blk: {
        var arr: [max_spell_slots][3]u8 = undefined;
        for (spell_idx_to_key, 0..) |key, i| {
            const key_str = @tagName(key);
            const c: [1]u8 = .{std.ascii.toUpper(key_str[0])};
            arr[i] = .{ '[', c[0], ']' };
        }
        break :blk arr;
    };
    pub const item_idx_to_key = [max_item_slots]core.Key{ .one, .two, .three, .four, .five, .six, .seven, .eight };
    pub const item_idx_to_key_str = blk: {
        var arr: [max_item_slots][3]u8 = undefined;
        for (item_idx_to_key, 0..) |_, i| {
            arr[i] = .{ '[', '1' + i, ']' };
        }
        break :blk arr;
    };
    pub const discard_key = core.Key.d;

    room_ui_bg_rect: geom.Rectf = .{},
    run_ui_bg_rect: geom.Rectf = .{},
    casting_bar_rect: geom.Rectf = .{},
    spells: std.BoundedArray(Slot, max_spell_slots) = .{},
    items: std.BoundedArray(Slot, max_item_slots) = .{},
    item_menu_open: ?usize = null,
    select_state: ?struct {
        select_kind: SelectionKind,
        slot_kind: Slot.Kind,
        action_kind: ?player.Action.Kind,
        slot_idx: usize,
    } = null,
    selected_method: Options.Controls.CastMethod = .left_click,
    discard_slot: ?Slot = null,
    pause_slot: UISlot = UISlot.init(.pause),
    mana_rect: geom.Rectf = .{},
    hp_rect: geom.Rectf = .{},
    immui: struct {
        commands: ImmUI.CmdBuf = .{},
    } = .{},
    tooltip_immui: struct {
        commands: ImmUI.CmdBuf = .{},
    } = .{},

    pub fn init(self: *Slots, num_spell_slots: usize, items: []const ?Item, discard_button: bool) void {
        assert(num_spell_slots <= max_spell_slots);

        self.* = .{};
        for (0..num_spell_slots) |i| {
            const slot = Slot{
                .idx = i,
                .key = spell_idx_to_key[i],
                .key_str = Slot.KeyStr.fromSlice(&spell_idx_to_key_str[i]) catch unreachable,
                .cooldown_timer = null,
            };
            self.spells.append(slot) catch unreachable;
        }

        for (items, 0..) |maybe_item, i| {
            var slot = Slot{
                .idx = i,
                .key = item_idx_to_key[i],
                .key_str = Slot.KeyStr.fromSlice(&item_idx_to_key_str[i]) catch unreachable,
            };
            if (maybe_item) |item| {
                slot.kind = .{ .action = .{ .item = item } };
            }
            self.items.append(slot) catch unreachable;
        }

        if (discard_button) {
            self.discard_slot = .{
                .idx = 0,
                .key = discard_key,
                .key_str = Slot.KeyStr.fromSlice("[D]") catch unreachable,
                .kind = .{ .action = .discard },
            };
        }

        self.reflowRects();
    }

    pub fn beginRoom(self: *Slots, room: *Room) void {
        for (self.spells.slice()) |*slot| {
            slot.kind = null;
            slot.cooldown_timer = null;
            if (room.drawSpell()) |spell| {
                slot.kind = .{ .action = .{ .spell = spell } };
            }
        }
    }

    pub fn reflowRects(self: *Slots) void {
        const plat = getPlat();
        // TODO Options?
        const ui_scaling: f32 = plat.ui_scaling;
        const spell_item_margin = 10 * ui_scaling;

        // run rect bottom left;
        // items
        const items_rects = getItemsRects();
        const rightmost_items_x = blk: {
            var best_x = -std.math.inf(f32);
            for (items_rects.constSlice()) |rect| {
                const x = rect.pos.x + rect.dims.x;
                if (x > best_x) {
                    best_x = x;
                }
            }
            break :blk best_x;
        };
        const items_width = rightmost_items_x + spell_item_margin;
        for (self.items.slice(), 0..) |*slot, i| {
            slot.rect = items_rects.get(i);
            slot.key_rect_pos = slot.rect.pos.sub(V2f.splat(8).scale(ui_scaling));
        }

        // hp and mana above items
        const big_hp_txt = "9999/9999";
        const big_mana_txt = "99/99";
        const hp_mana_font = App.getData().fonts.get(.pixeloid);
        const hp_mana_padding = text_box_padding.scale(ui_scaling);
        const font_sz_f = utl.as(f32, hp_mana_font.base_size) * ui_scaling;
        const hp_mana_text_opt = draw.TextOpt{
            .font = hp_mana_font,
            .size = utl.as(u32, font_sz_f),
        };
        const hp_text_max_dims = plat.measureText(big_hp_txt, hp_mana_text_opt) catch v2f(font_sz_f, 100 * ui_scaling);
        const mana_text_max_dims = plat.measureText(big_mana_txt, hp_mana_text_opt) catch v2f(font_sz_f, 70 * ui_scaling);
        const hp_dims = hp_text_max_dims.add(v2f(6 * ui_scaling, 0)).add(hp_mana_padding.scale(2));
        const mana_dims = mana_text_max_dims.add(v2f(6 * ui_scaling, 0)).add(hp_mana_padding.scale(2));
        const mana_topleft = items_rects.get(0).pos.sub(v2f(0, hp_dims.y + 34 * ui_scaling));
        const hp_topleft = mana_topleft.sub(v2f(0, hp_dims.y + 5 * ui_scaling));
        self.hp_rect = .{
            .pos = hp_topleft,
            .dims = hp_dims,
        };
        self.mana_rect = .{
            .pos = mana_topleft,
            .dims = mana_dims,
        };
        // background rect for "run" elements; items, hp, mana
        const run_bg_rect_pos = v2f(
            0,
            hp_topleft.y - 7 * ui_scaling,
        );
        const run_bg_rect_dims = v2f(
            items_width,
            plat.screen_dims_f.y - run_bg_rect_pos.y,
        );
        self.run_ui_bg_rect = .{
            .pos = run_bg_rect_pos,
            .dims = run_bg_rect_dims,
        };

        // spells anchored to run rect, or in center if big enough screen
        const spell_slot_dims = Spell.card_dims.scale(ui_scaling);
        const spell_slot_spacing = 7 * ui_scaling;
        const spells_dims = v2f(
            (utl.as(f32, self.spells.len)) * (spell_slot_dims.x + spell_slot_spacing) - spell_slot_spacing,
            spell_slot_dims.y,
        );
        const space_for_spells_center = plat.screen_dims_f.x - items_width * 2 - spell_item_margin * 2;
        const spells_topleft_x = if (space_for_spells_center > spells_dims.x) (plat.screen_dims_f.x - spells_dims.x) * 0.5 else items_width + spell_item_margin;
        const spells_topleft_y = plat.screen_dims_f.y - bottom_screen_margin * ui_scaling - spell_slot_dims.y;
        const spells_topleft = v2f(spells_topleft_x, spells_topleft_y);
        for (self.spells.slice(), 0..) |*slot, i| {
            const x_off = (spell_slot_dims.x + spell_slot_spacing) * utl.as(f32, i);
            slot.rect = .{
                .pos = spells_topleft.add(v2f(x_off, 0)),
                .dims = spell_slot_dims,
            };
            slot.key_rect_pos = slot.rect.pos.sub(V2f.splat(6).scale(ui_scaling));
        }

        // discard and pause to the right
        const spells_botright = spells_topleft.add(spells_dims);
        const pause_discard_btn_dims = v2f(24, 24).scale(ui_scaling);
        const pause_topleft = spells_botright.add(v2f(7 * ui_scaling, -pause_discard_btn_dims.y));
        self.pause_slot.rect = .{
            .pos = pause_topleft,
            .dims = pause_discard_btn_dims,
        };
        self.pause_slot.key_rect_pos = self.pause_slot.rect.pos.sub(v2f(3, 17).scale(ui_scaling));
        if (self.discard_slot) |*slot| {
            slot.rect = .{
                .pos = pause_topleft.add(v2f(0, -20 * ui_scaling - pause_discard_btn_dims.y)),
                .dims = pause_discard_btn_dims,
            };
            slot.key_rect_pos = slot.rect.pos.sub(v2f(5, 17).scale(ui_scaling));
        }

        // background rect covers everything at bottom of screen
        const room_bg_rect_pos = spells_topleft.sub(v2f(spell_item_margin, 10 * ui_scaling));
        const room_bg_rect_dims = plat.screen_dims_f.sub(room_bg_rect_pos);
        self.room_ui_bg_rect = .{
            .pos = room_bg_rect_pos,
            .dims = room_bg_rect_dims,
        };
        // casting rect in center just above
        const casting_bar_dims = v2f(100, 5).scale(ui_scaling);
        self.casting_bar_rect = .{
            .pos = v2f(
                plat.screen_dims_f.sub(casting_bar_dims).scale(0.5).x,
                self.room_ui_bg_rect.pos.y - casting_bar_dims.y - 10 * ui_scaling,
            ),
            .dims = casting_bar_dims,
        };

        plat.centerGameRect(.{}, self.getGameScreenRect());
    }

    pub fn getGameScreenRect(self: *Slots) V2f {
        const plat = getPlat();
        return plat.screen_dims_f.sub(v2f(0, self.room_ui_bg_rect.dims.y));
    }

    pub fn getSlotsByActionKind(self: *Slots, action_kind: player.Action.Kind) []Slot {
        return switch (action_kind) {
            .spell => self.spells.slice(),
            .item => self.items.slice(),
            .discard => if (self.discard_slot) |*d| (d)[0..1] else &.{},
        };
    }

    pub fn getSlotsByActionKindConst(self: *const Slots, action_kind: player.Action.Kind) []const Slot {
        return @constCast(self).getSlotsByActionKind(action_kind);
    }

    pub fn getSelectedActionSlot(self: *const Slots) ?Slot {
        if (self.select_state) |state| {
            if (state.select_kind == .selected) {
                if (state.action_kind) |action_kind| {
                    const slots = self.getSlotsByActionKindConst(action_kind);
                    return slots[state.slot_idx];
                }
            }
        }
        return null;
    }

    pub fn slotIsEnabled(slot: *const Slot, caster: *const Thing) bool {
        return slot.kind != null and caster.isAliveCreature() and (if (slot.cooldown_timer) |timer| !timer.running else true);
    }

    pub fn canActivateSlot(slot: *const Slot, run: *const Run, caster: *const Thing) bool {
        const room = &run.room;
        return slotIsEnabled(slot, caster) and switch (slot.kind.?) {
            .pause => run.room_exists,
            .action => |a| if (run.room_exists) switch (a) {
                inline else => |k| !std.meta.hasMethod(@TypeOf(k), "canUse") or k.canUse(room, caster),
            } else switch (a) {
                inline else => |k| !std.meta.hasMethod(@TypeOf(k), "canUseInRun") or k.canUseInRun(caster, run),
            },
        };
    }

    pub fn cancelSelectedActionSlotIfInvalid(self: *Slots, run: *const Run, caster: *const Thing) void {
        if (self.getSelectedActionSlot()) |*slot| {
            if (!canActivateSlot(slot, run, caster)) {
                self.unselectSlot();
            }
        }
    }

    pub fn getNextEmptyItemSlot(self: *const Slots) ?Slot {
        for (self.items.constSlice()) |slot| {
            if (slot.kind == null) return slot;
        }
        return null;
    }

    pub fn setActionSlotCooldown(self: *Slots, slot_idx: usize, action_kind: player.Action.Kind, ticks: ?i64) void {
        const slots = self.getSlotsByActionKind(action_kind);
        const slot = &slots[slot_idx];
        slot.cooldown_timer = if (ticks) |t| utl.TickCounter.init(t) else null;
    }

    pub fn clearSlotByActionKind(self: *Slots, slot_idx: usize, action_kind: player.Action.Kind) void {
        const slots = self.getSlotsByActionKind(action_kind);
        const slot = &slots[slot_idx];

        slot.kind = null;
        slot.selection_kind = null;

        if (self.select_state) |*s| {
            if (s.slot_kind == .action and s.action_kind.? == action_kind and s.slot_idx == slot_idx) {
                self.select_state = null;
            }
        }
    }

    pub fn selectSlot(self: *Slots, slot_kind: Slot.Kind, action_kind: ?player.Action.Kind, cast_method: Options.Controls.CastMethod, idx: usize) void {
        self.unselectSlot();
        switch (slot_kind) {
            .pause => {
                // REMOVED
            },
            .action => {
                switch (action_kind.?) {
                    .spell => assert(idx < self.spells.len),
                    .item => assert(idx < self.items.len),
                    .discard => assert(idx == 0),
                }
                const slots = self.getSlotsByActionKind(action_kind.?);
                self.select_state = .{
                    .slot_idx = idx,
                    .select_kind = .selected,
                    .slot_kind = .action,
                    .action_kind = action_kind.?,
                };
                slots[idx].selection_kind = .selected;
            },
        }

        self.selected_method = cast_method;
    }

    pub fn changeSelectedSlotToBuffered(self: *Slots) void {
        if (self.select_state) |*s| {
            s.select_kind = .buffered;
            switch (s.slot_kind) {
                .pause => {
                    // REMOVED
                },
                .action => {
                    const slots = self.getSlotsByActionKind(s.action_kind.?);
                    slots[s.slot_idx].selection_kind = .buffered;
                },
            }
        }
    }

    pub fn unselectSlot(self: *Slots) void {
        if (self.select_state) |*s| {
            switch (s.slot_kind) {
                .pause => {
                    // REMOVED
                },
                .action => {
                    const slots = self.getSlotsByActionKind(s.action_kind.?);
                    slots[s.slot_idx].selection_kind = null;
                },
            }
        }
        self.select_state = null;
    }

    pub fn updateTimerAndDrawSpell(self: *Slots, room: *Room) void {
        for (self.spells.slice()) |*slot| {
            if (slot.cooldown_timer) |*timer| {
                if (slot.kind) |k| {
                    assert(std.meta.activeTag(k) == .action);
                    assert(std.meta.activeTag(k.action) == .spell);
                    // only tick and draw into empty slots!
                } else if (timer.tick(false)) {
                    if (room.drawSpell()) |spell| {
                        slot.kind = .{ .action = .{ .spell = spell } };
                    }
                }
            }
        }
        if (self.discard_slot) |*slot| {
            if (slot.cooldown_timer) |*timer| {
                if (timer.tick(false)) {
                    slot.kind = .{ .action = .discard };
                }
            }
        }
    }

    fn unqActionSlots(self: *Slots, run: *Run, caster: *const Thing, slots: []Slot, action_kind: player.Action.Kind) Error!void {
        for (slots, 0..) |*slot, i| {
            if (try unqSlot(&self.immui.commands, &self.tooltip_immui.commands, slot, caster, run)) |cast_method| {
                self.selectSlot(.action, action_kind, cast_method, i);
            }
        }
    }

    pub fn unqCommandUISlot(slot: *UISlot, cmd_buf: *ImmUI.CmdBuf, tooltip_cmd_buf: *ImmUI.CmdBuf, run: *Run, selected: bool) Error!bool {
        const plat = App.getPlat();
        const data = App.getData();
        const ui_scaling: f32 = plat.ui_scaling;
        var activation: bool = false;
        var opt = draw.PolyOpt{
            .fill_color = slot_bg_color,
            .edge_radius = 0.2,
        };
        if (selected) {
            opt.outline = .{
                .color = .orange,
                .thickness = 3,
            };
        }
        if (try slot.unqRectHoverClick(cmd_buf, true, opt)) {
            activation = true;
        }

        const tooltip_scaling: f32 = plat.ui_scaling;
        const tooltip_pos = slot.rect.pos.add(v2f(slot.rect.dims.x, 0));
        var slot_contents_pos = slot.rect.pos;
        if (slot.hovered) slot_contents_pos = slot_contents_pos.add(v2f(0, -5));

        switch (slot.command) {
            .pause => {
                assert(run.room_exists);
                const room = &run.room;
                const sprite_name = if (room.paused) Data.MiscIcon.hourglass_down else Data.MiscIcon.hourglass_up;
                const info = sprites.RenderIconInfo{ .frame = data.misc_icons.getRenderFrame(sprite_name).? };
                try info.unqRender(cmd_buf, slot_contents_pos, ui_scaling);
                if (slot.long_hover.is) {
                    const tt = Tooltip{
                        .title = Tooltip.Title.fromSlice("Pause") catch unreachable,
                    };
                    try tt.unqRender(tooltip_cmd_buf, tooltip_pos, tooltip_scaling);
                }
            },
            else => {},
        }
        if (try slot.unqHotKey(cmd_buf, true)) {
            activation = true;
        }
        return activation;
    }

    pub fn update(self: *Slots, run: *Run, caster: *const Thing) Error!void {
        const plat = getPlat();
        const room = &run.room;
        self.tooltip_immui.commands.clear();
        self.immui.commands.clear();
        // big rects, check ui clicked
        self.immui.commands.append(.{ .rect = .{
            .pos = self.run_ui_bg_rect.pos,
            .dims = self.run_ui_bg_rect.dims.add(v2f(0, 20 * plat.ui_scaling)),
            .opt = .{
                .fill_color = Colorf.rgb(0.13, 0.11, 0.13),
                .edge_radius = 0.1,
            },
        } }) catch @panic("Fail to append rect cmd");
        self.immui.commands.append(.{ .rect = .{
            .pos = self.room_ui_bg_rect.pos,
            .dims = self.room_ui_bg_rect.dims.add(v2f(0, 20 * plat.ui_scaling)),
            .opt = .{
                .fill_color = Colorf.rgb(0.13, 0.09, 0.15),
                .edge_radius = 0.1,
            },
        } }) catch @panic("Fail to append rect cmd");
        const mouse_pos = plat.getMousePosScreen();
        const hovered = geom.pointIsInRectf(mouse_pos, self.run_ui_bg_rect) or geom.pointIsInRectf(mouse_pos, self.room_ui_bg_rect);
        const clicked = hovered and (plat.input_buffer.mouseBtnIsJustPressed(.left) or plat.input_buffer.mouseBtnIsJustPressed(.right));
        run.ui_hovered = hovered;
        run.ui_clicked = clicked;

        try self.unqActionSlots(run, caster, self.spells.slice(), .spell);
        try self.unqActionSlots(run, caster, self.items.slice(), .item);
        if (self.discard_slot) |*d| {
            if (try unqSlot(&self.immui.commands, &self.tooltip_immui.commands, d, caster, run)) |_| {
                self.selectSlot(.action, .discard, .quick_release, 0);
            }
        }
        if (try unqCommandUISlot(&self.pause_slot, &self.immui.commands, &self.tooltip_immui.commands, run, run.room.paused)) {
            room.paused = !room.paused;
        }

        { // hp and mana and casting bar
            const ui_scaling: f32 = plat.ui_scaling;
            const icon_scaling = ui_scaling * 2;
            const data = App.get().data;
            const hp_mana_rect_opt = draw.PolyOpt{
                .edge_radius = 0.2,
                .fill_color = slot_bg_color,
            };
            const font = data.fonts.get(.pixeloid);
            const hp_mana_text_opt = draw.TextOpt{
                .font = font,
                .size = font.base_size * utl.as(u32, ui_scaling),
                .smoothing = .none,
                .color = .white,
            };
            try self.immui.commands.append(.{ .rect = .{
                .pos = self.hp_rect.pos,
                .dims = self.hp_rect.dims,
                .opt = hp_mana_rect_opt,
            } });
            if (caster.hp) |hp| {
                const cropped_dims = data.text_icons.sprite_dims_cropped.?.get(.heart);

                if (data.text_icons.getRenderFrame(.heart)) |rf| {
                    const heart_pos = self.hp_rect.pos.sub(v2f(cropped_dims.x * 0.5 * (icon_scaling), 0));
                    var opt = rf.toTextureOpt(icon_scaling);
                    opt.src_dims = cropped_dims;
                    opt.tint = .red;
                    opt.origin = .topleft;
                    opt.round_to_pixel = true;
                    try self.immui.commands.append(.{ .texture = .{
                        .pos = heart_pos,
                        .texture = rf.texture,
                        .opt = opt,
                    } });
                }
                const text_pos = self.hp_rect.pos.add((v2f(cropped_dims.x, 0).add(text_box_padding).scale(ui_scaling)));
                try self.immui.commands.append(.{
                    .label = .{
                        .pos = text_pos,
                        .text = ImmUI.initLabel(try utl.bufPrintLocal("{d:.0}/{d:.0}", .{ hp.curr, hp.max })),
                        .opt = hp_mana_text_opt,
                    },
                });
            }

            try self.immui.commands.append(.{ .rect = .{
                .pos = self.mana_rect.pos,
                .dims = self.mana_rect.dims,
                .opt = hp_mana_rect_opt,
            } });
            if (caster.mana) |mana| {
                const cropped_dims = data.text_icons.sprite_dims_cropped.?.get(.mana_crystal);
                if (data.text_icons.getRenderFrame(.mana_crystal)) |rf| {
                    const mana_crystal_pos = self.mana_rect.pos.sub(v2f(cropped_dims.x * 0.5 * (icon_scaling), 0));
                    var opt = rf.toTextureOpt(icon_scaling);
                    opt.src_dims = cropped_dims;
                    opt.origin = .topleft;
                    opt.round_to_pixel = true;
                    try self.immui.commands.append(.{ .texture = .{
                        .pos = mana_crystal_pos,
                        .texture = rf.texture,
                        .opt = opt,
                    } });
                }
                const text_pos = self.mana_rect.pos.add((v2f(cropped_dims.x, 0).add(text_box_padding).scale(ui_scaling)));
                try self.immui.commands.append(.{
                    .label = .{
                        .pos = text_pos,
                        .text = ImmUI.initLabel(try utl.bufPrintLocal("{d:.0}/{d:.0}", .{ mana.curr, mana.max })),
                        .opt = hp_mana_text_opt,
                    },
                });
                if (caster.controller == .player) {
                    if (caster.controller.player.mana_regen) |regen| {
                        const bar_max_dims = v2f(self.mana_rect.dims.x - 9 * ui_scaling, 2 * ui_scaling);
                        try self.immui.commands.append(.{ .rect = .{
                            .pos = self.mana_rect.pos.add(v2f(7 * ui_scaling, self.mana_rect.dims.y - 2 * ui_scaling)),
                            .dims = v2f(regen.timer.remapTo0_1() * bar_max_dims.x, bar_max_dims.y),
                            .opt = .{
                                .fill_color = draw.Coloru.rgb(161, 133, 238).toColorf(),
                            },
                        } });
                    }
                }
            }
            switch (caster.controller) {
                .player => |c| {
                    if (c.action_casting != null) {
                        const pad = V2f.splat(1 * ui_scaling);
                        const curr_x = c.cast_counter.remapTo0_1() * self.casting_bar_rect.dims.x;
                        try self.immui.commands.append(.{ .rect = .{
                            .pos = self.casting_bar_rect.pos,
                            .dims = self.casting_bar_rect.dims,
                            .opt = .{
                                .fill_color = .black,
                                .edge_radius = 0.8,
                            },
                        } });
                        try self.immui.commands.append(.{ .rect = .{
                            .pos = self.casting_bar_rect.pos.add(pad),
                            .dims = v2f(curr_x, self.casting_bar_rect.dims.y).sub(pad.scale(2)),
                            .opt = .{
                                .fill_color = .lightgray,
                                .edge_radius = 0.8,
                            },
                        } });
                    }
                },
                else => {},
            }
        }
    }

    pub fn render(self: *const Slots, room: *const Room) Error!void {
        const plat = App.getPlat();

        { // debug deck stuff
            const p = self.pause_slot.rect.pos.add(v2f(100, -40));
            try plat.textf(
                p,
                "deck: {}\ndiscard: {}\nmislayed: {}\n",
                .{
                    room.draw_pile.len,
                    room.discard_pile.len,
                    room.mislay_pile.len,
                },
                .{ .color = .white },
            );
        }

        try ImmUI.render(&self.immui.commands);
        try ImmUI.render(&self.tooltip_immui.commands);
    }
};

pub const LayoutParams = struct {
    direction: enum {
        horizontal,
        vertical,
    } = .horizontal,
    space_between: f32 = 10,
};

pub fn layoutRectsFixedSize(num: usize, dims: V2f, center_pos: V2f, layout: LayoutParams, buf: []geom.Rectf) void {
    assert(num <= buf.len);
    if (num == 0) return;
    const dir_idx: usize = switch (layout.direction) {
        .horizontal => 0,
        .vertical => 1,
    };
    const other_idx = (dir_idx + 1) % 2;
    const dims_arr = dims.toArr();
    const total_size_in_dir = utl.as(f32, num - 1) * (dims_arr[dir_idx] + layout.space_between) + dims_arr[dir_idx];
    const total_dims_arr = blk: {
        var ret: [2]f32 = undefined;
        ret[dir_idx] = total_size_in_dir;
        ret[other_idx] = dims_arr[other_idx];
        break :blk ret;
    };
    const total_dims_v = V2f.fromArr(total_dims_arr);
    const top_left = center_pos.sub(total_dims_v.scale(0.5));
    const inc_v_arr = blk: {
        var ret: [2]f32 = .{ 0, 0 };
        ret[dir_idx] = dims_arr[dir_idx] + layout.space_between;
        break :blk ret;
    };
    const inc_v = V2f.fromArr(inc_v_arr);
    for (0..num) |i| {
        buf[i] = .{
            .pos = top_left.add(inc_v.scale(utl.as(f32, i))),
            .dims = dims,
        };
    }
}
