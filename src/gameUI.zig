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

// unq == update and queue (render)
// Handle all updating and rendering of a generic action Slot, returning a CastMethod if it was activated
pub fn unqActionSlot(cmd_buf: *ImmUI.CmdBuf, slot_rect: geom.Rectf, slot: *Slots.Slot, caster: *const Thing, room: *Room) Error!?Options.CastMethod {
    const plat = getPlat();

    var ret: ?Options.CastMethod = null;
    const mouse_pos = plat.getMousePosScreen();
    const hovered = geom.pointIsInRectf(mouse_pos, slot_rect);
    const clicked = hovered and plat.input_buffer.mouseBtnIsJustPressed(.left);
    // TODO anything else here?
    const slot_enabled = slot.kind != null and caster.isAliveCreature() and (if (slot.cooldown_timer) |timer| !timer.running else true);
    const can_activate_slot = slot_enabled and switch (slot.kind.?) {
        inline else => |a| !std.meta.hasMethod(@TypeOf(a), "canUse") or a.canUse(room, caster),
    };
    const bg_color = Colorf.rgb(0.07, 0.05, 0.05);
    var rect = slot_rect;
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
        rect.pos = slot_rect.pos.add(v2f(0, -5));
    }
    cmd_buf.append(.{ .rect = .{
        .pos = rect.pos,
        .dims = rect.dims,
        .opt = .{
            .fill_color = bg_color,
        },
    } }) catch @panic("Fail to append rect cmd");

    // slot contents
    if (slot_enabled) {
        const kind_data = slot.kind.?;

        if (can_activate_slot) {
            key_color = .white;
            border_color = if (slot.selection_kind) |s| Slots.SelectionKind.colors.get(s) else .blue;
            // activated this frame?
            var activated = false;
            if (hovered and clicked) {
                activated = true;
                room.ui_clicked = true;
            } else if (plat.input_buffer.keyIsJustPressed(slot.key)) {
                activated = true;
            }
            if (activated) {
                ret = App.get().options.cast_method;
                // auto-target self-cast
                switch (kind_data) {
                    inline else => |k| {
                        if (@hasField(@TypeOf(k), "targeting_data")) {
                            if (k.targeting_data.kind == .self) {
                                ret = .quick_release;
                            }
                        }
                    },
                }
            }
        }

        // render
        switch (kind_data) {
            .discard => {
                const data = App.get().data;
                const info = sprites.RenderIconInfo{ .frame = data.misc_icons.getRenderFrame(.discard).? };
                try info.unqRenderTint(cmd_buf, rect, Colorf.rgb(0.7, 0, 0));
            },
            inline else => |inner| try inner.unqRenderIcon(cmd_buf, rect),
        }
        if (caster.mana) |mana| {
            switch (kind_data) {
                .spell => |spell| {
                    spell.renderManaCost(rect);
                    if (mana.curr < spell.mana_cost) {
                        // red insufficient mana overlay
                        cmd_buf.append(.{
                            .rect = .{
                                .pos = rect.pos,
                                .dims = rect.dims,
                                .opt = .{ .fill_color = Colorf.red.fade(0.25) },
                            },
                        }) catch @panic("Fail to append rect cmd");
                    }
                    // TODO mana cost circles
                    //spell.renderManaCost(rect);
                },
                else => {},
            }
        }
    }
    if (slot.cooldown_timer) |*timer| {
        // NOTE rn the timers are ticked in updateTimerAndDrawSpell, that's fine...
        if (timer.running) {
            menuUI.unqSectorTimer(
                cmd_buf,
                rect.pos.add(rect.dims.scale(0.5)),
                rect.dims.x * 0.5 * 0.7,
                timer,
                .{ .fill_color = .blue },
            );
        }
    }

    // border
    cmd_buf.append(.{ .rect = .{
        .pos = rect.pos,
        .dims = rect.dims,
        .opt = .{
            .fill_color = null,
            .outline_color = border_color,
            .outline_thickness = 4,
        },
    } }) catch @panic("Fail to append rect cmd");

    // hotkey
    cmd_buf.append(.{ .label = .{
        .pos = rect.pos.add(v2f(1, 1)),
        .text = ImmUI.Command.LabelString.initTrunc(&slot.key_str),
        .opt = .{
            .color = key_color,
            .size = 20,
        },
    } }) catch @panic("Fail to append label cmd");

    return ret;
}

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
        pub const Kind = player.Action.Kind;
        pub const KindData = player.Action.KindData;

        idx: usize,
        key: core.Key,
        key_str: [3]u8,
        kind: ?KindData = null,
        cooldown_timer: ?utl.TickCounter = null,
        hover_timer: utl.TickCounter = utl.TickCounter.init(15),
        is_long_hovered: bool = false,
        selection_kind: ?SelectionKind = null,
    };
    pub const InitParams = struct {
        num_spell_slots: usize = 4, // populated from deck
        items: std.BoundedArray(?Item, max_item_slots) = .{},
        discard_button: bool = false,
    };

    pub const max_spell_slots = 6;
    pub const max_item_slots = 8;

    pub const spell_idx_to_key = [max_spell_slots]core.Key{ .q, .w, .e, .r, .t, .y };
    pub const spell_idx_to_key_str = blk: {
        var arr: [max_spell_slots][3]u8 = undefined;
        for (spell_idx_to_key, 0..) |key, i| {
            const key_str = @tagName(key);
            const c: [1]u8 = .{std.ascii.toUpper(key_str[0])};
            const str = "[" ++ &c ++ "]";
            arr[i] = str.*;
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
    pub const discard_key_str = "[D]".*;

    const spell_slot_dims = v2f(72, 72);
    const spell_slot_spacing: f32 = 12;

    const item_slot_dims = v2f(48, 48);
    const item_slot_spacing: f32 = 8;

    spells: std.BoundedArray(Slot, max_spell_slots) = .{},
    items: std.BoundedArray(Slot, max_item_slots) = .{},
    select_state: ?struct {
        select_kind: SelectionKind,
        slot_kind: Slot.Kind,
        slot_idx: usize,
    } = null,
    selected_method: Options.CastMethod = .left_click,
    discard_slot: ?Slot = null,
    immui: struct {
        commands: ImmUI.CmdBuf = .{},
    } = .{},

    pub fn init(room: *Room, params: InitParams) Slots {
        assert(params.num_spell_slots < max_spell_slots);

        var ret = Slots{};
        for (0..params.num_spell_slots) |i| {
            var slot = Slot{
                .idx = i,
                .key = spell_idx_to_key[i],
                .key_str = spell_idx_to_key_str[i],
                .cooldown_timer = utl.TickCounter.init(90),
            };
            if (room.drawSpell()) |spell| {
                slot.kind = .{ .spell = spell };
            }
            ret.spells.append(slot) catch unreachable;
        }

        for (params.items.constSlice(), 0..) |maybe_item, i| {
            var slot = Slot{
                .idx = i,
                .key = item_idx_to_key[i],
                .key_str = item_idx_to_key_str[i],
            };
            if (maybe_item) |item| {
                slot.kind = .{ .item = item };
            }
            ret.items.append(slot) catch unreachable;
        }

        if (params.discard_button) {
            ret.discard_slot = .{
                .idx = 0,
                .key = discard_key,
                .key_str = discard_key_str,
                .kind = .discard,
            };
        }

        return ret;
    }

    pub fn getSlotRects(self: *const Slots, kind: Slot.Kind) std.BoundedArray(geom.Rectf, @max(max_spell_slots, max_item_slots)) {
        const plat = getPlat();
        var ret = std.BoundedArray(geom.Rectf, @max(max_spell_slots, max_item_slots)){};
        const spells_center_pos: V2f = plat.native_rect_cropped_offset.add(v2f(
            plat.native_rect_cropped_dims.x * 0.5,
            plat.native_rect_cropped_dims.y - 60 - spell_slot_dims.y * 0.5,
        ));
        switch (kind) {
            .discard => {
                assert(ret.buffer.len > 0);
                const spell_rects = self.getSlotRects(.spell);
                const last = spell_rects.get(spell_rects.len - 1);
                const right_middle = last.pos.add(v2f(last.dims.x, last.dims.y * 0.5));
                const discard_btn_dims = v2f(48, 48);
                const rect_center = right_middle.add(v2f(spell_slot_spacing + discard_btn_dims.x * 0.5, 0));
                ret.append(.{
                    .pos = rect_center.sub(discard_btn_dims.scale(0.5)),
                    .dims = discard_btn_dims,
                }) catch unreachable;
            },
            .spell => {
                ret.resize(self.spells.len) catch unreachable;
                layoutRectsFixedSize(self.spells.len, spell_slot_dims, spells_center_pos, .{ .space_between = spell_slot_spacing }, ret.slice());
            },
            .item => {
                const center_pos: V2f = spells_center_pos.sub(v2f(0, (spell_slot_dims.y + item_slot_dims.y) * 0.5 + 10));
                ret.resize(self.items.len) catch unreachable;
                layoutRectsFixedSize(self.items.len, item_slot_dims, center_pos, .{ .space_between = item_slot_spacing }, ret.slice());
            },
        }
        return ret;
    }

    pub fn getSlotsByKind(self: *Slots, kind: Slot.Kind) []Slot {
        return switch (kind) {
            .spell => self.spells.slice(),
            .item => self.items.slice(),
            .discard => (&self.discard_slot.?)[0..1],
        };
    }

    pub fn getSlotsByKindConst(self: *const Slots, kind: Slot.Kind) []const Slot {
        return switch (kind) {
            .spell => self.spells.constSlice(),
            .item => self.items.constSlice(),
            .discard => (&self.discard_slot.?)[0..1],
        };
    }

    pub fn getSelectedSlot(self: *const Slots) ?Slot {
        if (self.select_state) |state| {
            if (state.select_kind == .selected) {
                const slots = self.getSlotsByKindConst(state.slot_kind);
                return slots[state.slot_idx];
            }
        }
        return null;
    }

    pub fn getNextEmptyItemSlot(self: *const Slots) ?Slot {
        for (self.items.constSlice()) |slot| {
            if (slot.kind == null) return slot;
        }
        return null;
    }

    pub fn setSlotCooldown(self: *Slots, slot_idx: usize, slot_kind: Slot.Kind, ticks: ?i64) void {
        const slots = self.getSlotsByKind(slot_kind);
        const slot = &slots[slot_idx];
        slot.cooldown_timer = if (ticks) |t| utl.TickCounter.init(t) else null;
    }

    pub fn clearSlotByKind(self: *Slots, slot_idx: usize, slot_kind: Slot.Kind) void {
        const slots = self.getSlotsByKind(slot_kind);
        const slot = &slots[slot_idx];

        slot.kind = null;
        slot.selection_kind = null;

        if (self.select_state) |*s| {
            if (s.slot_kind == slot_kind and s.slot_idx == slot_idx) {
                self.select_state = null;
            }
        }
    }

    pub fn selectSlot(self: *Slots, kind: Slot.Kind, cast_method: Options.CastMethod, idx: usize) void {
        switch (kind) {
            .spell => assert(idx < self.spells.len),
            .item => assert(idx < self.items.len),
            .discard => assert(idx == 0),
        }
        self.unselectSlot();
        const slots = self.getSlotsByKind(kind);
        self.select_state = .{
            .slot_idx = idx,
            .select_kind = .selected,
            .slot_kind = kind,
        };
        self.selected_method = cast_method;
        slots[idx].selection_kind = .selected;
    }

    pub fn changeSelectedSlotToBuffered(self: *Slots) void {
        if (self.select_state) |*s| {
            const slots = self.getSlotsByKind(s.slot_kind);
            s.select_kind = .buffered;
            slots[s.slot_idx].selection_kind = .buffered;
        }
    }

    pub fn unselectSlot(self: *Slots) void {
        if (self.select_state) |*s| {
            const slots = self.getSlotsByKind(s.slot_kind);
            s.select_kind = .buffered;
            slots[s.slot_idx].selection_kind = null;
        }
    }

    pub fn updateTimerAndDrawSpell(self: *Slots, room: *Room) void {
        for (self.spells.slice()) |*slot| {
            if (slot.cooldown_timer) |*timer| {
                if (slot.kind) |k| {
                    assert(std.meta.activeTag(k) == .spell);
                    // only tick and draw into empty slots!
                } else if (timer.tick(false)) {
                    if (room.drawSpell()) |spell| {
                        slot.kind = .{ .spell = spell };
                    }
                }
            }
        }
        if (self.discard_slot) |*slot| {
            if (slot.cooldown_timer) |*timer| {
                if (timer.tick(false)) {
                    slot.kind = .discard;
                }
            }
        }
    }

    fn unqSlots(self: *Slots, room: *Room, caster: *const Thing, slots: []Slot, kind: Slot.Kind) Error!void {
        const rects = self.getSlotRects(kind);
        assert(rects.len == slots.len);
        for (slots, 0..) |*slot, i| {
            if (try unqActionSlot(&self.immui.commands, rects.get(i), slot, caster, room)) |cast_method| {
                self.selectSlot(kind, cast_method, i);
            }
        }
    }

    pub fn update(self: *Slots, room: *Room, caster: *const Thing) Error!void {
        self.immui.commands.clear();
        try self.unqSlots(room, caster, self.spells.slice(), .spell);
        try self.unqSlots(room, caster, self.items.slice(), .item);
        if (self.discard_slot) |*d| {
            try self.unqSlots(room, caster, d[0..1], .discard);
        }
    }

    pub fn renderToolTips(self: *const Slots, slots: []const Slot, kind: Slot.Kind) Error!void {
        const rects = self.getSlotRects(kind);
        for (slots, 0..) |slot, i| {
            const rect = rects.get(i);
            const pos = rect.pos.add(v2f(rect.dims.x, 0));
            if (!slot.hover_timer.running) {
                if (slot.kind) |k| {
                    switch (k) {
                        .discard => {
                            // TODO
                        },
                        inline else => |inner| try inner.renderToolTip(pos),
                    }
                }
            }
        }
    }

    pub fn render(self: *const Slots, room: *const Room) Error!void {
        const plat = App.getPlat();
        const right_side_rect = if (self.discard_slot) |_| self.getSlotRects(.discard).get(0) else self.getSlotRects(.spell).get(self.spells.len - 1);
        const right_center = right_side_rect.pos.add(v2f(right_side_rect.dims.x, right_side_rect.dims.y * 0.5));

        { // debug deck stuff
            const p = right_center.add(v2f(10, -30));
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
        // tooltips on top of everything
        if (self.discard_slot) |slot| {
            if (slot.is_long_hovered) {
                try menuUI.renderToolTip("Discard hand", "", right_center);
            }
        }
        try self.renderToolTips(self.spells.constSlice(), .spell);
        try self.renderToolTips(self.items.constSlice(), .item);
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

    const radius = 24;
    const select_radius = 28;
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
                self.selected = last_path_pos.dist(self.pos) <= ExitDoor.radius + 10;
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
                .outline_color = rim_color,
            };
            if (mouse_pos.dist(self.pos) <= select_radius) {
                opt.fill_color = open_hover_color;
            }
            plat.circlef(self.pos.add(v2f(0, 2)), radius - 1, opt);
        } else {
            const opt = draw.PolyOpt{
                .fill_color = closed_color,
                .outline_color = rim_color,
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
                const range = 20;
                const base = self.pos.sub(v2f(0, 100 + range * t));
                const end = base.add(v2f(0, 70));
                plat.arrowf(base, end, 15, color);
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
