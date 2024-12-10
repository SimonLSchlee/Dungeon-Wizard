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
pub fn unqSlot(cmd_buf: *ImmUI.CmdBuf, tooltip_cmd_buf: *ImmUI.CmdBuf, slot: *Slots.Slot, caster: *const Thing, room: *Room) Error!?Options.Controls.CastMethod {
    const data = App.get().data;
    const plat = getPlat();
    const ui_scaling: f32 = plat.ui_scaling;

    var ret: ?Options.Controls.CastMethod = null;
    const mouse_pos = plat.getMousePosScreen();
    const hovered = geom.pointIsInRectf(mouse_pos, slot.rect);
    const clicked = hovered and plat.input_buffer.mouseBtnIsJustPressed(.left);
    const slot_enabled = Slots.slotIsEnabled(slot, caster);
    const can_activate_slot = Slots.canActivateSlot(slot, room, caster);
    const bg_color = slot_bg_color;
    var slot_contents_pos = slot.rect.pos;
    var border_color = Colorf.darkgray;
    var key_color = Colorf.gray;

    if (hovered) {
        _ = slot.hover_timer.tick(false);
    } else {
        slot.hover_timer.restart();
    }
    slot.is_long_hovered = (hovered and !slot.hover_timer.running);

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
        if (slot.is_long_hovered) {
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

// Run slots (just items, and some additional data)
// Used to populate Slots but also state in Run
pub const RunSlots = struct {
    pub const ItemSlot = struct {
        item: ?Item,
        rect: geom.Rectf = .{},
        long_hover: menuUI.LongHover = .{},
    };
    num_spell_slots: usize = 4, // populated from deck
    items: std.BoundedArray(ItemSlot, max_item_slots) = .{},
    item_menu_open: ?usize = null,
    discard_button: bool = false,
};

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
        is_long_hovered: bool = false,
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

    ui_bg_rect: geom.Rectf = .{},
    spells: std.BoundedArray(Slot, max_spell_slots) = .{},
    items: std.BoundedArray(Slot, max_item_slots) = .{},
    select_state: ?struct {
        select_kind: SelectionKind,
        slot_kind: Slot.Kind,
        action_kind: ?player.Action.Kind,
        slot_idx: usize,
    } = null,
    selected_method: Options.Controls.CastMethod = .left_click,
    discard_slot: ?Slot = null,
    pause_slot: Slot = undefined, // Slots are for player.Action's
    mana_rect: geom.Rectf = .{},
    hp_rect: geom.Rectf = .{},
    immui: struct {
        commands: ImmUI.CmdBuf = .{},
    } = .{},
    tooltip_immui: struct {
        commands: ImmUI.CmdBuf = .{},
    } = .{},

    pub fn init(self: *Slots, room: *Room, run_slots: RunSlots) void {
        assert(run_slots.num_spell_slots <= max_spell_slots);

        self.* = .{};
        for (0..run_slots.num_spell_slots) |i| {
            var slot = Slot{
                .idx = i,
                .key = spell_idx_to_key[i],
                .key_str = Slot.KeyStr.fromSlice(&spell_idx_to_key_str[i]) catch unreachable,
                .cooldown_timer = utl.TickCounter.init(90),
            };
            if (room.drawSpell()) |spell| {
                slot.kind = .{ .action = .{ .spell = spell } };
            }
            self.spells.append(slot) catch unreachable;
        }

        for (run_slots.items.constSlice(), 0..) |item_slot, i| {
            var slot = Slot{
                .idx = i,
                .key = item_idx_to_key[i],
                .key_str = Slot.KeyStr.fromSlice(&item_idx_to_key_str[i]) catch unreachable,
            };
            if (item_slot.item) |item| {
                slot.kind = .{ .action = .{ .item = item } };
            }
            self.items.append(slot) catch unreachable;
        }

        if (run_slots.discard_button) {
            self.discard_slot = .{
                .idx = 0,
                .key = discard_key,
                .key_str = Slot.KeyStr.fromSlice("[D]") catch unreachable,
                .kind = .{ .action = .discard },
            };
        }

        self.pause_slot = .{
            .idx = 0,
            .key_str = Slot.KeyStr.fromSlice("[SPC]") catch unreachable,
            .key = .space,
            .kind = .pause,
        };
        self.reflowRects();
    }

    pub fn reflowRects(self: *Slots) void {
        const plat = getPlat();
        // TODO Options?
        const ui_scaling: f32 = plat.ui_scaling;

        // items bottom left
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
        const items_width = rightmost_items_x - items_rects.get(0).dims.x;
        for (self.items.slice(), 0..) |*slot, i| {
            slot.rect = items_rects.get(i);
            slot.key_rect_pos = slot.rect.pos.sub(V2f.splat(8).scale(ui_scaling));
        }

        // spells anchored to items, or in center if big enough screen
        const spell_slot_dims = Spell.card_dims.scale(ui_scaling);
        const spell_slot_spacing = 7 * ui_scaling;
        const spell_item_margin = 14 * ui_scaling;
        const spells_dims = v2f(
            (utl.as(f32, self.spells.len)) * (spell_slot_dims.x + spell_slot_spacing) - spell_slot_spacing,
            spell_slot_dims.y,
        );
        const space_for_spells_center = plat.screen_dims_f.x - items_width * 2 - spell_item_margin * 2;
        const spells_topleft_x = if (space_for_spells_center > spells_dims.x) (plat.screen_dims_f.x - spells_dims.x) * 0.5 else rightmost_items_x + spell_item_margin;
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

        // hp and mana above
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
        const hp_topleft = items_rects.get(0).pos.sub(v2f(0, hp_dims.y + 30 * ui_scaling));
        const mana_topleft = hp_topleft.add(v2f(hp_dims.x + 8 * ui_scaling, 0));
        self.hp_rect = .{
            .pos = hp_topleft,
            .dims = hp_dims,
        };
        self.mana_rect = .{
            .pos = mana_topleft,
            .dims = mana_dims,
        };

        // discard and pause to the right
        {
            const spells_botright = spells_topleft.add(spells_dims);
            const btn_dims = v2f(24, 24).scale(ui_scaling);
            const pause_topleft = spells_botright.add(v2f(7 * ui_scaling, -btn_dims.y));
            self.pause_slot.rect = .{
                .pos = pause_topleft,
                .dims = btn_dims,
            };
            self.pause_slot.key_rect_pos = self.pause_slot.rect.pos.sub(v2f(3, 17).scale(ui_scaling));
            if (self.discard_slot) |*slot| {
                slot.rect = .{
                    .pos = pause_topleft.add(v2f(0, -20 * ui_scaling - btn_dims.y)),
                    .dims = btn_dims,
                };
                slot.key_rect_pos = slot.rect.pos.sub(v2f(5, 17).scale(ui_scaling));
            }
        }
        // background rect covers everything at bottom of screen
        const bg_rect_pos = v2f(
            0,
            @min(spells_topleft.y, items_rects.get(0).pos.y) - 10 * ui_scaling,
        );
        const bg_rect_dims = v2f(
            plat.screen_dims_f.x,
            plat.screen_dims_f.y - bg_rect_pos.y,
        );
        self.ui_bg_rect = .{
            .pos = bg_rect_pos,
            .dims = bg_rect_dims,
        };
        plat.centerGameRect(.{}, self.getGameScreenRect());
    }

    pub fn getGameScreenRect(self: *Slots) V2f {
        const plat = getPlat();
        return plat.screen_dims_f.sub(v2f(0, self.ui_bg_rect.dims.y));
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

    pub fn canActivateSlot(slot: *const Slot, room: *const Room, caster: *const Thing) bool {
        return slotIsEnabled(slot, caster) and switch (slot.kind.?) {
            .pause => true,
            .action => |a| switch (a) {
                inline else => |k| !std.meta.hasMethod(@TypeOf(k), "canUse") or k.canUse(room, caster),
            },
        };
    }

    pub fn cancelSelectedActionSlotIfInvalid(self: *Slots, room: *const Room, caster: *const Thing) void {
        if (self.getSelectedActionSlot()) |*slot| {
            if (!canActivateSlot(slot, room, caster)) {
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
                assert(idx == 0);
                self.select_state = .{
                    .slot_idx = idx,
                    .select_kind = .selected,
                    .slot_kind = .pause,
                    .action_kind = undefined,
                };
                self.pause_slot.selection_kind = .selected;
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
                    self.pause_slot.selection_kind = .buffered;
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
                    self.pause_slot.selection_kind = null;
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

    fn unqActionSlots(self: *Slots, room: *Room, caster: *const Thing, slots: []Slot, action_kind: player.Action.Kind) Error!void {
        for (slots, 0..) |*slot, i| {
            if (try unqSlot(&self.immui.commands, &self.tooltip_immui.commands, slot, caster, room)) |cast_method| {
                self.selectSlot(.action, action_kind, cast_method, i);
            }
        }
    }

    pub fn update(self: *Slots, room: *Room, caster: *const Thing) Error!void {
        const plat = getPlat();
        self.tooltip_immui.commands.clear();
        self.immui.commands.clear();
        // big rect, check ui clicked
        self.immui.commands.append(.{ .rect = .{
            .pos = self.ui_bg_rect.pos,
            .dims = self.ui_bg_rect.dims,
            .opt = .{
                .fill_color = Colorf.rgb(0.13, 0.11, 0.13),
            },
        } }) catch @panic("Fail to append rect cmd");
        const mouse_pos = plat.getMousePosScreen();
        const hovered = geom.pointIsInRectf(mouse_pos, self.ui_bg_rect);
        const clicked = hovered and (plat.input_buffer.mouseBtnIsJustPressed(.left) or plat.input_buffer.mouseBtnIsJustPressed(.right));
        room.ui_hovered = hovered;
        room.ui_clicked = clicked;

        try self.unqActionSlots(room, caster, self.spells.slice(), .spell);
        try self.unqActionSlots(room, caster, self.items.slice(), .item);
        if (self.discard_slot) |*d| {
            if (try unqSlot(&self.immui.commands, &self.tooltip_immui.commands, d, caster, room)) |_| {
                self.selectSlot(.action, .discard, .quick_release, 0);
            }
        }
        if (try unqSlot(&self.immui.commands, &self.tooltip_immui.commands, &self.pause_slot, caster, room)) |_| {
            room.paused = !room.paused;
        }
        if (room.paused) {
            self.pause_slot.selection_kind = .selected;
        } else {
            self.pause_slot.selection_kind = null;
        }
        {
            const ui_scaling: f32 = plat.ui_scaling;
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
                    const heart_pos = self.hp_rect.pos.sub(v2f(cropped_dims.x * 0.5 * (ui_scaling + 2), 0));
                    var opt = rf.toTextureOpt(ui_scaling + 2);
                    opt.src_dims = cropped_dims;
                    opt.tint = .red;
                    opt.origin = .topleft;
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
                    const mana_crystal_pos = self.mana_rect.pos.sub(v2f(cropped_dims.x * 0.5 * (ui_scaling + 2), 0));
                    var opt = rf.toTextureOpt(ui_scaling + 2);
                    opt.src_dims = cropped_dims;
                    opt.origin = .topleft;
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

pub const ExitDoor = struct {
    pub const RewardPreview = enum {
        none,
        gold,
        item,
        shop,
        end,
    };
    pub const ChallengePreview = enum {
        none,
        boss,
    };

    const radius = 12;
    const select_radius = 14;
    const closed_color = Colorf.rgb(0.4, 0.4, 0.4);
    const rim_color = Colorf.rgb(0.4, 0.3, 0.4);
    const open_color_1 = Colorf.rgb(0.2, 0.1, 0.2);
    const open_color_2 = Colorf.rgb(0.4, 0.1, 0.4);
    const open_hover_color = Colorf.rgb(0.4, 0.1, 0.4);
    const arrow_hover_color = Colorf.rgb(0.7, 0.5, 0.7);

    pos: V2f,
    reward_preview: RewardPreview = .none,
    challenge_preview: ChallengePreview = .none,
    selected: bool = false,

    pub fn updateSelected(self: *ExitDoor, room: *Room) Error!bool {
        //const plat = App.getPlat();
        if (room.getConstPlayer()) |p| {
            if (p.path.len > 0) {
                const last_path_pos = p.path.buffer[p.path.len - 1];
                self.selected = last_path_pos.dist(self.pos) <= ExitDoor.radius + 5;
                if (self.selected) {
                    if (p.pos.dist(self.pos) <= select_radius) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    pub fn render(self: *const ExitDoor, room: *const Room) Error!void {
        const plat = App.getPlat();

        // rim
        plat.circlef(self.pos, ExitDoor.radius, .{ .fill_color = ExitDoor.rim_color });
        // fill
        if (room.progress_state == .won) {
            const mouse_pos = plat.getMousePosWorld(room.camera);
            const tick_60 = @mod(room.curr_tick, 360);
            const f = utl.pi * utl.as(f32, tick_60) / 360;
            const t = @sin(f);
            var opt = draw.PolyOpt{
                .fill_color = open_color_1.lerp(open_color_2, t),
                .outline = .{ .color = rim_color },
            };
            if (mouse_pos.dist(self.pos) <= select_radius) {
                opt.fill_color = open_hover_color;
            }
            plat.circlef(self.pos.add(v2f(0, 2)), radius - 1, opt);
        } else {
            const opt = draw.PolyOpt{
                .fill_color = closed_color,
                .outline = .{ .color = rim_color },
            };
            plat.circlef(self.pos.add(v2f(0, 2)), radius - 1, opt);
        }
    }
    pub fn renderOver(self: *const ExitDoor, room: *const Room) Error!void {
        const plat = App.getPlat();
        if (room.progress_state == .won) {
            const mouse_pos = plat.getMousePosWorld(room.camera);
            if (self.selected or mouse_pos.dist(self.pos) <= select_radius) {
                const tick_60 = @mod(room.curr_tick, 60);
                const f = utl.pi * utl.as(f32, tick_60) / 60;
                const t = @sin(f);
                var color = arrow_hover_color;
                if (self.selected) {
                    color = Colorf.white;
                }
                const range = 10;
                const base = self.pos.sub(v2f(0, 50 + range * t));
                const end = base.add(v2f(0, 35));
                plat.arrowf(base, end, .{ .thickness = 7.5, .color = color });
            }
        }
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
