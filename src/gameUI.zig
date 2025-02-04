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
        slot.clicked = slot.hovered and plat.input_buffer.mouseBtnIsJustPressed(.left) and slot.hovered;

        _ = slot.long_hover.update(slot.hovered);

        cmd_buf.append(.{ .rect = .{
            .pos = slot.rect.pos,
            .dims = slot.rect.dims,
            .opt = if (poly_opt) |opt| opt else .{
                .fill_color = slot_bg_color,
                .edge_radius = 0.2,
            },
        } }) catch @panic("Fail to append rect cmd");

        return enabled and slot.clicked;
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

    pub fn hotkeyIsReleased(slot: *const UISlot) bool {
        const maybe_binding = App.get().options.controls.getBindingByCommand(slot.command);
        var ret = false;

        if (maybe_binding) |binding| {
            const plat = getPlat();

            if (binding.inputs.len == 0) return false;
            for (binding.inputs.constSlice()) |b| switch (b) {
                .mouse_button => |btn| ret = ret or !plat.input_buffer.mouseBtnIsDown(btn),
                .keyboard_key => |key| ret = ret or !plat.input_buffer.keyIsDown(key),
            };
            return ret;
        }
        return false;
    }

    pub fn unqHotKey(slot: *UISlot, cmd_buf: *ImmUI.CmdBuf, enabled: bool) Error!bool {
        const maybe_binding = App.get().options.controls.getBindingByCommand(slot.command);
        var ret = false;

        if (maybe_binding) |binding| {
            const data = App.get().data;
            const plat = getPlat();
            const ui_scaling: f32 = plat.ui_scaling;

            if (binding.inputs.len == 0) return false;
            if (enabled) {
                for (binding.inputs.constSlice()) |b| switch (b) {
                    .mouse_button => |btn| ret = ret or plat.input_buffer.mouseBtnIsJustPressed(btn),
                    .keyboard_key => |key| ret = ret or plat.input_buffer.keyIsJustPressed(key),
                };
            }
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

pub const SpellSlot = struct {
    ui_slot: UISlot,
    spell: ?Spell = null,
};

pub const ItemSlot = struct {
    pub const TossBtn = struct {
        long_hover: menuUI.LongHover = .{},
        rect: geom.Rectf = .{},
        clicked: bool = false,
        hovered: bool = false,
    };
    ui_slot: UISlot,
    item: ?Item = null,
    toss_btn: TossBtn = .{},
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

// game slots
pub const Slots = struct {
    pub const SelectState = enum {
        none,
        selected,
        buffered,
        pub const colors = std.EnumArray(SelectState, Colorf).init(.{
            .none = Colorf.blank,
            .selected = Colorf.orange,
            .buffered = Colorf.green,
        });
    };

    pub const text_box_padding = V2f.splat(2);

    room_ui_bg_rect: geom.Rectf = .{},
    run_ui_bg_rect: geom.Rectf = .{},
    casting_bar_rect: geom.Rectf = .{},
    item_menu_open: ?usize = null,
    mana_rect: geom.Rectf = .{},
    hp_rect: geom.Rectf = .{},

    // Actions
    spells: std.BoundedArray(SpellSlot, max_spell_slots) = .{},
    items: std.BoundedArray(ItemSlot, max_item_slots) = .{},
    discard_slot: ?UISlot = null,
    action_selected: ?struct {
        command: Options.Controls.InputBinding.Command,
        cast_method: Options.Controls.CastMethod = .left_click,
        select_state: union(SelectState) {
            none,
            selected,
            buffered: Spell.Params,
        },
    } = null,

    // Non-Action Commands
    pause_slot: UISlot = UISlot.init(.pause),

    pub fn init(self: *Slots, num_spell_slots: usize, items: []const ?Item, discard_button: bool) void {
        assert(num_spell_slots <= max_spell_slots);

        self.* = .{};
        for (0..num_spell_slots) |i| {
            const slot = SpellSlot{
                .ui_slot = UISlot.init(.{ .action = .{ .kind = .spell, .slot_idx = i } }),
            };
            self.spells.appendAssumeCapacity(slot);
        }

        for (items, 0..) |maybe_item, i| {
            const slot = ItemSlot{
                .ui_slot = UISlot.init(.{ .action = .{ .kind = .item, .slot_idx = i } }),
                .item = maybe_item,
            };
            self.items.appendAssumeCapacity(slot);
        }

        if (discard_button) {
            self.discard_slot = UISlot.init(.{ .action = .{ .kind = .discard } });
        }

        self.reflowRects();
    }

    pub fn beginRoom(self: *Slots, room: *Room, draw_spells: bool) void {
        for (self.spells.slice()) |*slot| {
            slot.spell = null;
            slot.ui_slot.cooldown_timer = null;
            if (draw_spells) {
                if (room.drawSpell()) |spell| {
                    slot.spell = spell;
                }
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
            slot.ui_slot.rect = items_rects.get(i);
            slot.ui_slot.key_rect_pos = slot.ui_slot.rect.pos.sub(V2f.splat(8).scale(ui_scaling));
            slot.toss_btn.rect.dims = V2f.splat(9).scale(ui_scaling);
            slot.toss_btn.rect.pos = slot.ui_slot.rect.pos.add(v2f(slot.ui_slot.rect.dims.x - slot.toss_btn.rect.dims.x, 0)).add(v2f(2, -4).scale(ui_scaling));
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
            slot.ui_slot.rect = .{
                .pos = spells_topleft.add(v2f(x_off, 0)),
                .dims = spell_slot_dims,
            };
            slot.ui_slot.key_rect_pos = slot.ui_slot.rect.pos.sub(V2f.splat(6).scale(ui_scaling));
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

    pub fn getSelectedActionCommand(self: *const Slots) ?Options.Controls.InputBinding.Command {
        if (self.action_selected) |a| {
            return a.command;
        }
        return null;
    }

    pub fn getSelectedAction(self: *const Slots, select_state: SelectState) ?player.Action.KindData {
        if (select_state == .none) return null;
        if (self.action_selected) |a| {
            if (a.select_state != select_state) return null;
            if (std.meta.activeTag(a.command) != .action) return null;
            const slot_idx = a.command.action.slot_idx orelse 0;
            switch (a.command.action.kind) {
                .spell => {
                    const slot = &self.spells.buffer[slot_idx];
                    if (slot.spell) |spell| {
                        return .{ .spell = spell };
                    }
                },
                .item => {
                    const slot = &self.items.buffer[slot_idx];
                    if (slot.item) |item| {
                        return .{ .item = item };
                    }
                },
                .discard => {
                    return .{ .discard = .{} };
                },
            }
        }
        return null;
    }

    pub fn getCastAction(self: *const Slots, run: *const Run) ?player.Action.KindData {
        if (self.action_selected) |a| {
            if (a.select_state != .selected) return null;
            if (std.meta.activeTag(a.command) != .action) return null;
            const slot_idx = a.command.action.slot_idx orelse 0;
            const ui_slot: *const UISlot = switch (a.command.action.kind) {
                .spell => &self.spells.buffer[slot_idx].ui_slot,
                .item => &self.items.buffer[slot_idx].ui_slot,
                .discard => if (self.discard_slot) |*d| d else return null,
            };
            const plat = App.getPlat();
            const casted = switch (a.cast_method) {
                .left_click => !run.ui_clicked and plat.input_buffer.mouseBtnIsJustPressed(.left),
                .quick_press => true,
                .quick_release => ui_slot.hotkeyIsReleased(),
            };
            if (casted) {
                return self.getSelectedAction(.selected);
            }
        }
        return null;
    }

    pub fn bufferSelectedAction(self: *Slots, run: *Run, caster: *const Thing) bool {
        const plat = App.getPlat();
        const room = &run.room;
        const mouse_pos = plat.getMousePosWorld(room.camera);

        if (self.getCastAction(run)) |action| {
            const _params: ?Spell.Params = switch (action) {
                inline else => |a| if (std.meta.hasMethod(@TypeOf(a), "getTargetParams"))
                    a.getTargetParams(room, caster, mouse_pos)
                else
                    null,
            };
            if (_params) |params| {
                switch (action) {
                    .spell => |s| if (caster.mana) |*mana| {
                        if (s.mana_cost.getActualCost(caster)) |cost| {
                            assert(mana.curr >= cost);
                        }
                    },
                    else => {},
                }
                self.action_selected.?.select_state = .{ .buffered = params };
                return true;
            } else if (action == .discard) {
                self.action_selected.?.select_state = .{ .buffered = .{ .target_kind = .self } };
                return true;
            } else {
                self.unselectAction();
            }
        }
        return false;
    }

    pub fn tryUnbufferAction(self: *Slots, run: *Run, caster: *Thing) ?player.Action.Buffered {
        const room = &run.room;
        const maybe_action = self.getSelectedAction(.buffered);
        if (maybe_action == null) return null;
        const action = maybe_action.?;
        const params = self.action_selected.?.select_state.buffered;
        const slot_idx = self.action_selected.?.command.action.slot_idx orelse 0;

        switch (action) {
            .spell => |spell| {
                const slot = &self.spells.buffer[slot_idx];
                slot.spell = null;

                if (spell.mislay) {
                    room.mislaySpell(spell);
                } else {
                    room.discardSpell(spell);
                }
                if (caster.mana) |*mana| {
                    if (spell.mana_cost.getActualCost(caster)) |cost| {
                        assert(mana.curr >= cost);
                        mana.curr -= cost;
                    }
                }
                if (caster.statuses.get(.quickdraw).stacks > 0) {
                    slot.ui_slot.cooldown_timer = utl.TickCounter.init(0);
                    caster.statuses.getPtr(.quickdraw).addStacks(caster, -1);
                } else if (spell.draw_immediate) {
                    slot.ui_slot.cooldown_timer = utl.TickCounter.init(0);
                } else if (room.init_params.mode == .mandy_3_mana) {
                    slot.ui_slot.cooldown_timer = null;
                } else {
                    // otherwise normal cooldown
                    slot.ui_slot.cooldown_timer = utl.TickCounter.init(spell.getSlotCooldownTicks());
                }
            },
            .item => {
                self.items.buffer[slot_idx].item = null;
            },
            else => {},
        }
        self.unselectAction();

        return .{
            .action = action,
            .params = params,
        };
    }

    pub fn cancelSelectedActionSlotIfInvalid(self: *Slots, run: *const Run, caster: *const Thing) void {
        if (self.getSelectedAction(.selected)) |*slot| {
            _ = slot;
            _ = run;
            _ = caster;
            // TODO
            //if (!canActivateSlot(slot, run, caster)) {
            //    self.unselectSlot();
            //}
        }
    }

    pub fn getNextEmptyItemSlot(self: *Slots) ?*ItemSlot {
        for (self.items.slice()) |*slot| {
            if (slot.item == null) return slot;
        }
        return null;
    }

    pub fn selectAction(self: *Slots, command: Options.Controls.InputBinding.Command, cast_method: Options.Controls.CastMethod) void {
        if (command != .action) return;
        self.action_selected = .{
            .command = command,
            .cast_method = cast_method,
            .select_state = .selected,
        };
    }

    pub fn unselectAction(self: *Slots) void {
        self.action_selected = null;
    }

    pub fn updateTimerAndDrawSpell(self: *Slots, room: *Room) void {
        for (self.spells.slice()) |*slot| {
            if (slot.ui_slot.cooldown_timer) |*timer| {
                if (timer.tick(false)) {
                    if (room.drawSpell()) |spell| {
                        slot.spell = spell;
                        slot.ui_slot.cooldown_timer = null;
                    }
                }
            }
        }
        if (self.discard_slot) |*slot| {
            if (slot.cooldown_timer) |*timer| {
                if (timer.tick(false)) {
                    slot.cooldown_timer = null;
                }
            }
        }
    }

    pub const RunItemAction = enum {
        toss,
    };

    pub fn unqTossBtn(btn: *ItemSlot.TossBtn, cmd_buf: *ImmUI.CmdBuf, tooltip_cmd_buf: *ImmUI.CmdBuf) Error!bool {
        const plat = getPlat();
        const data = App.getData();
        const mouse_pos = plat.getMousePosScreen();
        const ui_scaling = plat.ui_scaling;
        const font = data.fonts.get(.pixeloid);
        const text_opt = draw.TextOpt{
            .font = font,
            .size = font.base_size * utl.as(u32, ui_scaling),
            .smoothing = .none,
            .color = .white,
            .center = true,
            .border = .{
                .dist = ui_scaling,
            },
        };

        btn.hovered = geom.pointIsInRectf(mouse_pos, btn.rect);
        btn.clicked = btn.hovered and plat.input_buffer.mouseBtnIsJustPressed(.left) and btn.hovered;

        _ = btn.long_hover.update(btn.hovered);

        cmd_buf.append(.{
            .rect = .{
                .pos = btn.rect.pos,
                .dims = btn.rect.dims,
                .opt = .{
                    .fill_color = if (btn.hovered) .red else Colorf.rgb(0.7, 0, 0),
                    .edge_radius = 0.2,
                },
            },
        }) catch @panic("Fail to append rect cmd");
        cmd_buf.append(.{ .label = .{
            .text = ImmUI.initLabel("x"),
            .pos = btn.rect.pos.add(btn.rect.dims.scale(0.5).add(v2f(0, -1).scale(ui_scaling))),
            .opt = text_opt,
        } }) catch @panic("Fail to append label");

        if (btn.long_hover.is) {
            const tooltip_pos = btn.rect.pos.add(v2f(btn.rect.dims.x, 0));
            const tt = Tooltip{
                .title = Tooltip.Title.fromSlice("Discard item") catch unreachable,
            };
            try tt.unqRender(tooltip_cmd_buf, tooltip_pos, ui_scaling);
        }

        return btn.clicked;
    }

    pub fn unqItemRunUISlot(self: *Slots, slot: *ItemSlot, cmd_buf: *ImmUI.CmdBuf, tooltip_cmd_buf: *ImmUI.CmdBuf, interact: bool) Error!?RunItemAction {
        const plat = App.getPlat();
        const ui_scaling: f32 = plat.ui_scaling;
        const ui_slot = &slot.ui_slot;
        var ret: ?RunItemAction = null;
        var opt = draw.PolyOpt{
            .fill_color = slot_bg_color,
            .edge_radius = 0.2,
        };
        opt.outline = self.getActionBorder(ui_slot.command);

        _ = try ui_slot.unqRectHoverClick(cmd_buf, false, opt);

        if (slot.item) |item| {
            const tooltip_scaling: f32 = plat.ui_scaling;
            const tooltip_pos = slot.ui_slot.rect.pos.add(v2f(slot.ui_slot.rect.dims.x, 0));

            try item.unqRenderIcon(cmd_buf, slot.ui_slot.rect.pos, ui_scaling);
            if (interact) {
                if (try unqTossBtn(&slot.toss_btn, cmd_buf, tooltip_cmd_buf)) {
                    ret = .toss;
                }
                if (tooltip_cmd_buf.len == 0 and ui_slot.long_hover.is) {
                    try item.unqRenderTooltip(tooltip_cmd_buf, tooltip_pos, tooltip_scaling);
                }
            }
        }
        return ret;
    }

    pub fn unqItemRoomUISlot(self: *Slots, slot: *UISlot, cmd_buf: *ImmUI.CmdBuf, tooltip_cmd_buf: *ImmUI.CmdBuf, caster: *const Thing, maybe_item: ?Item) Error!?Options.Controls.CastMethod {
        const plat = App.getPlat();
        const ui_scaling: f32 = plat.ui_scaling;
        const enabled = if (maybe_item) |item| item.canUse(caster) else false;
        var default_cast_method = App.get().options.controls.cast_method;
        var activation: ?Options.Controls.CastMethod = null;
        var opt = draw.PolyOpt{
            .fill_color = slot_bg_color,
            .edge_radius = 0.2,
        };
        opt.outline = self.getActionBorder(slot.command);

        if (try slot.unqRectHoverClick(cmd_buf, enabled, opt)) {
            activation = .left_click;
        }

        if (maybe_item) |item| {
            if (item.targeting_data.kind == .self) {
                default_cast_method = .quick_release;
                if (activation != null) {
                    activation = default_cast_method;
                }
            }
            const tooltip_scaling: f32 = plat.ui_scaling;
            const tooltip_pos = slot.rect.pos.add(v2f(slot.rect.dims.x, 0));
            var slot_contents_pos = slot.rect.pos;
            if (enabled and slot.hovered) slot_contents_pos = slot_contents_pos.add(v2f(0, -5));

            try item.unqRenderIconTint(cmd_buf, slot_contents_pos, ui_scaling, if (enabled) .white else Colorf.white.fade(0.7));
            if (slot.long_hover.is) {
                try item.unqRenderTooltip(tooltip_cmd_buf, tooltip_pos, tooltip_scaling);
            }
        }

        if (try slot.unqHotKey(cmd_buf, enabled)) {
            activation = default_cast_method;
        }

        return activation;
    }

    pub fn unqSpellUISlot(self: *Slots, slot: *UISlot, cmd_buf: *ImmUI.CmdBuf, tooltip_cmd_buf: *ImmUI.CmdBuf, caster: *const Thing, maybe_spell: ?Spell) Error!?Options.Controls.CastMethod {
        const plat = App.getPlat();
        const ui_scaling: f32 = plat.ui_scaling;
        const enabled = if (maybe_spell) |spell| spell.canUse(caster) else false;
        var default_cast_method = App.get().options.controls.cast_method;
        var activation: ?Options.Controls.CastMethod = null;
        var opt = draw.PolyOpt{
            .fill_color = slot_bg_color,
            .edge_radius = 0.2,
        };
        opt.outline = self.getActionBorder(slot.command);

        if (try slot.unqRectHoverClick(cmd_buf, enabled, opt)) {
            activation = .left_click;
        }

        if (maybe_spell) |spell| {
            if (spell.targeting_data.kind == .self) {
                default_cast_method = .quick_release;
                if (activation != null) {
                    activation = default_cast_method;
                }
            }
            const tooltip_scaling: f32 = plat.ui_scaling;
            const tooltip_pos = slot.rect.pos.add(v2f(slot.rect.dims.x, 0));
            var slot_contents_pos = slot.rect.pos;
            if (enabled and slot.hovered) slot_contents_pos = slot_contents_pos.add(v2f(0, -5));

            spell.unqRenderCard(cmd_buf, slot_contents_pos, caster, ui_scaling);
            if (slot.long_hover.is) {
                try spell.unqRenderTooltip(tooltip_cmd_buf, tooltip_pos, tooltip_scaling);
            }
        } else if (slot.cooldown_timer) |_| {
            try slot.unqCooldownTimer(cmd_buf);
        }

        if (try slot.unqHotKey(cmd_buf, enabled)) {
            activation = default_cast_method;
        }

        return activation;
    }

    pub fn getActionBorder(self: *const Slots, command: Options.Controls.InputBinding.Command) ?draw.LineOpt {
        if (command != .action) return null;
        if (self.action_selected) |a| {
            if (a.command.eql(command)) {
                const color: Colorf = switch (a.select_state) {
                    .selected => .orange,
                    .buffered => .green,
                    .none => return null,
                };
                return draw.LineOpt{
                    .color = color,
                    .thickness = 3,
                };
            }
        }
        return null;
    }

    pub fn unqDiscardUISlot(self: *Slots, slot: *UISlot, cmd_buf: *ImmUI.CmdBuf, tooltip_cmd_buf: *ImmUI.CmdBuf, user: *const Thing) Error!bool {
        const plat = App.getPlat();
        const data = App.getData();
        const ui_scaling: f32 = plat.ui_scaling;
        const enabled = user.canAct();
        var activation: bool = false;
        var opt = draw.PolyOpt{
            .fill_color = slot_bg_color,
            .edge_radius = 0.2,
        };
        opt.outline = self.getActionBorder(slot.command);

        if (try slot.unqRectHoverClick(cmd_buf, enabled, opt)) {
            activation = true;
        }

        if (slot.cooldown_timer) |_| {
            try slot.unqCooldownTimer(cmd_buf);
        } else {
            const tooltip_scaling: f32 = plat.ui_scaling;
            const tooltip_pos = slot.rect.pos.add(v2f(slot.rect.dims.x, 0));
            var slot_contents_pos = slot.rect.pos;
            if (slot.hovered) slot_contents_pos = slot_contents_pos.add(v2f(0, -5));

            const sprite_name = Data.MiscIcon.discard;
            const info = sprites.RenderIconInfo{ .frame = data.misc_icons.getRenderFrame(sprite_name).? };
            try info.unqRender(cmd_buf, slot_contents_pos, ui_scaling);
            if (slot.long_hover.is) {
                const tt = Tooltip{
                    .title = Tooltip.Title.fromSlice("Discard hand") catch unreachable,
                };
                try tt.unqRender(tooltip_cmd_buf, tooltip_pos, tooltip_scaling);
            }
        }

        if (try slot.unqHotKey(cmd_buf, enabled)) {
            activation = true;
        }
        return activation;
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

    pub fn updateHPandMana(self: *Slots, cmd_buf: *ImmUI.CmdBuf, tooltip_cmd_buf: *ImmUI.CmdBuf, caster: *const Thing) Error!void {
        _ = tooltip_cmd_buf;
        const plat = getPlat();
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
        try cmd_buf.append(.{ .rect = .{
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
                try cmd_buf.append(.{ .texture = .{
                    .pos = heart_pos,
                    .texture = rf.texture,
                    .opt = opt,
                } });
            }
            const text_pos = self.hp_rect.pos.add((v2f(cropped_dims.x, 0).add(text_box_padding).scale(ui_scaling)));
            try cmd_buf.append(.{
                .label = .{
                    .pos = text_pos,
                    .text = ImmUI.initLabel(try utl.bufPrintLocal("{d:.0}/{d:.0}", .{ hp.curr, hp.max })),
                    .opt = hp_mana_text_opt,
                },
            });
        }

        try cmd_buf.append(.{ .rect = .{
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
                try cmd_buf.append(.{ .texture = .{
                    .pos = mana_crystal_pos,
                    .texture = rf.texture,
                    .opt = opt,
                } });
            }
            const text_pos = self.mana_rect.pos.add((v2f(cropped_dims.x, 0).add(text_box_padding).scale(ui_scaling)));
            try cmd_buf.append(.{
                .label = .{
                    .pos = text_pos,
                    .text = ImmUI.initLabel(try utl.bufPrintLocal("{d:.0}/{d:.0}", .{ mana.curr, mana.max })),
                    .opt = hp_mana_text_opt,
                },
            });
            if (mana.regen) |regen| {
                const bar_max_dims = v2f(self.mana_rect.dims.x - 9 * ui_scaling, 2 * ui_scaling);
                try cmd_buf.append(.{ .rect = .{
                    .pos = self.mana_rect.pos.add(v2f(7 * ui_scaling, self.mana_rect.dims.y - 2 * ui_scaling)),
                    .dims = v2f(regen.timer.remapTo0_1() * bar_max_dims.x, bar_max_dims.y),
                    .opt = .{
                        .fill_color = draw.Coloru.rgb(161, 133, 238).toColorf(),
                    },
                } });
            }
        }
    }

    pub fn roomOnlyUpdate(self: *Slots, cmd_buf: *ImmUI.CmdBuf, tooltip_cmd_buf: *ImmUI.CmdBuf, run: *Run, caster: *const Thing) Error!void {
        const plat = getPlat();
        const room = &run.room;

        // big rect, check ui clicked
        cmd_buf.append(.{ .rect = .{
            .pos = self.room_ui_bg_rect.pos,
            .dims = self.room_ui_bg_rect.dims.add(v2f(0, 20 * plat.ui_scaling)),
            .opt = .{
                .fill_color = Colorf.rgb(0.13, 0.09, 0.15),
                .edge_radius = 0.1,
            },
        } }) catch @panic("Fail to append rect cmd");
        const mouse_pos = plat.getMousePosScreen();
        const hovered = geom.pointIsInRectf(mouse_pos, self.room_ui_bg_rect);
        const clicked = hovered and (plat.input_buffer.mouseBtnIsJustPressed(.left) or plat.input_buffer.mouseBtnIsJustPressed(.right));
        run.ui_hovered = run.ui_hovered or hovered;
        run.ui_clicked = run.ui_clicked or clicked;

        for (self.spells.slice()) |*slot| {
            if (try self.unqSpellUISlot(&slot.ui_slot, cmd_buf, tooltip_cmd_buf, caster, slot.spell)) |cast_method| {
                self.selectAction(slot.ui_slot.command, cast_method);
            }
        }
        if (self.discard_slot) |*d| {
            if (try self.unqDiscardUISlot(d, cmd_buf, tooltip_cmd_buf, caster)) {
                self.selectAction(.{ .action = .{ .kind = .discard } }, .quick_release);
            }
        }
        if (try unqCommandUISlot(&self.pause_slot, cmd_buf, tooltip_cmd_buf, run, run.room.paused)) {
            room.paused = !room.paused;
        }
    }

    pub fn runUpdate(self: *Slots, cmd_buf: *ImmUI.CmdBuf, tooltip_cmd_buf: *ImmUI.CmdBuf, run: *Run, caster: *const Thing) Error!void {
        const plat = getPlat();
        cmd_buf.append(.{ .rect = .{
            .pos = self.run_ui_bg_rect.pos,
            .dims = self.run_ui_bg_rect.dims.add(v2f(0, 20 * plat.ui_scaling)),
            .opt = .{
                .fill_color = Colorf.rgb(0.13, 0.11, 0.13),
                .edge_radius = 0.1,
            },
        } }) catch @panic("Fail to append rect cmd");

        const mouse_pos = plat.getMousePosScreen();
        const hovered = geom.pointIsInRectf(mouse_pos, self.run_ui_bg_rect);
        const clicked = hovered and (plat.input_buffer.mouseBtnIsJustPressed(.left) or plat.input_buffer.mouseBtnIsJustPressed(.right));
        run.ui_hovered = run.ui_hovered or hovered;
        run.ui_clicked = run.ui_clicked or clicked;

        for (self.items.slice()) |*slot| {
            switch (run.screen) {
                .room => if (try self.unqItemRoomUISlot(&slot.ui_slot, cmd_buf, tooltip_cmd_buf, caster, slot.item)) |cast_method| {
                    self.selectAction(slot.ui_slot.command, cast_method);
                },
                .reward, .shop => if (try self.unqItemRunUISlot(slot, cmd_buf, tooltip_cmd_buf, true)) |run_item_action| {
                    switch (run_item_action) {
                        .toss => {
                            slot.item = null;
                        },
                    }
                },
                else => {
                    _ = try self.unqItemRunUISlot(slot, cmd_buf, tooltip_cmd_buf, false);
                },
            }
        }
        try self.updateHPandMana(cmd_buf, tooltip_cmd_buf, caster);
    }

    pub fn roomUpdate(self: *Slots, cmd_buf: *ImmUI.CmdBuf, tooltip_cmd_buf: *ImmUI.CmdBuf, run: *Run, caster: *const Thing) Error!void {
        const plat = getPlat();

        try self.roomOnlyUpdate(cmd_buf, tooltip_cmd_buf, run, caster);
        try self.runUpdate(cmd_buf, tooltip_cmd_buf, run, caster);
        // casting progress bar
        const ui_scaling: f32 = plat.ui_scaling;
        switch (caster.controller) {
            .player => |c| {
                if (c.action_casting != null) {
                    const pad = V2f.splat(1 * ui_scaling);
                    const curr_x = c.cast_counter.remapTo0_1() * self.casting_bar_rect.dims.x;
                    try cmd_buf.append(.{ .rect = .{
                        .pos = self.casting_bar_rect.pos,
                        .dims = self.casting_bar_rect.dims,
                        .opt = .{
                            .fill_color = .black,
                            .edge_radius = 0.8,
                        },
                    } });
                    try cmd_buf.append(.{ .rect = .{
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
