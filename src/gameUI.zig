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

        idx: usize,
        key: core.Key,
        key_str: [3]u8,
        kind: union(Kind) {
            spell: ?Spell,
            item: ?Item,
        },
        cooldown_timer: ?utl.TickCounter,
        hover_timer: utl.TickCounter,
    };
    pub const InitParams = struct {
        num_spell_slots: usize = 4, // populated from deck
        items: std.BoundedArray(?Item, max_item_slots) = .{},
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

    const spell_slot_dims = v2f(100, 120);
    const spell_slot_spacing: f32 = 20;

    const item_slot_dims = v2f(50, 50);
    const item_slot_spacing: f32 = 5;

    spells: std.BoundedArray(Slot, max_spell_slots) = .{},
    items: std.BoundedArray(Slot, max_item_slots) = .{},
    state: union(enum) {
        none,
        spell: struct {
            select_kind: SelectionKind,
            idx: usize,
        },
        item: struct {
            select_kind: SelectionKind,
            idx: usize,
        },
    } = .none,
    selected_method: Options.CastMethod = .left_click,

    pub fn init(room: *Room, params: InitParams) Slots {
        assert(params.num_spell_slots < max_spell_slots);

        var ret = Slots{};
        for (0..params.num_spell_slots) |i| {
            var slot = Slot{
                .idx = i,
                .key = spell_idx_to_key[i],
                .key_str = spell_idx_to_key_str[i],
                .kind = .{ .spell = null },
                .cooldown_timer = utl.TickCounter.initStopped(90),
                .hover_timer = utl.TickCounter.init(15),
            };
            if (room.drawSpell()) |spell| {
                slot.kind.spell = spell;
            }
            ret.spells.append(slot) catch unreachable;
        }

        for (params.items.constSlice(), 0..) |maybe_item, i| {
            const slot = Slot{
                .idx = i,
                .key = item_idx_to_key[i],
                .key_str = item_idx_to_key_str[i],
                .kind = .{ .item = maybe_item },
                .cooldown_timer = null,
                .hover_timer = utl.TickCounter.init(15),
            };
            ret.items.append(slot) catch unreachable;
        }

        return ret;
    }

    pub fn getSlotRects(self: *const Slots, kind: Slot.Kind) std.BoundedArray(geom.Rectf, @max(max_spell_slots, max_item_slots)) {
        const plat = App.getPlat();
        var ret = std.BoundedArray(geom.Rectf, @max(max_spell_slots, max_item_slots)){};
        const spells_center_pos: V2f = v2f(plat.screen_dims_f.x * 0.5, plat.screen_dims_f.y - 50 - spell_slot_dims.y * 0.5);
        switch (kind) {
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

    pub fn getSelectedSlot(self: *const Slots) ?Slot {
        switch (self.state) {
            .none => {},
            .spell => |s| {
                const slot = self.spells.get(s.idx);
                assert(std.meta.activeTag(slot.kind) == .spell);
                assert(slot.kind.spell != null);
                if (s.select_kind == .selected) {
                    return slot;
                }
            },
            .item => |s| {
                const slot = self.items.get(s.idx);
                assert(std.meta.activeTag(slot.kind) == .item);
                assert(slot.kind.item != null);
                if (s.select_kind == .selected) {
                    return slot;
                }
            },
        }
        return null;
    }

    pub fn clearItemSlot(self: *Slots, slot_idx: usize) void {
        assert(slot_idx < self.items.len);
        const slot = &self.items.slice()[slot_idx];
        assert(std.meta.activeTag(slot.kind) == .item);
        assert(slot.kind.item != null);
        slot.kind.item = null;
        switch (self.state) {
            .item => |s| {
                if (s.idx == slot_idx) {
                    self.state = .none;
                }
            },
            else => {},
        }
    }

    pub fn clearSpellSlot(self: *Slots, slot_idx: usize) void {
        assert(slot_idx < self.spells.len);
        const slot = &self.spells.slice()[slot_idx];
        assert(std.meta.activeTag(slot.kind) == .spell);
        assert(slot.kind.spell != null);
        slot.kind.spell = null;
        assert(slot.cooldown_timer != null);
        slot.cooldown_timer.?.restart();
        switch (self.state) {
            .spell => |s| {
                if (s.idx == slot_idx) {
                    self.state = .none;
                }
            },
            else => {},
        }
    }

    pub fn updateTimerAndDrawSpell(self: *Slots, room: *Room) void {
        for (self.spells.slice()) |*slot| {
            assert(std.meta.activeTag(slot.kind) == .spell);
            assert(slot.cooldown_timer != null);
            // only tick and draw into empty slots!
            if (slot.kind.spell == null) {
                if (slot.cooldown_timer.?.tick(false)) {
                    if (room.drawSpell()) |spell| {
                        slot.kind.spell = spell;
                    }
                }
            }
        }
    }

    fn updateSelectedSlots(self: *Slots, room: *const Room, caster: *const Thing, slots: []Slot, kind: Slot.Kind) bool {
        const plat = App.getPlat();
        const rects = self.getSlotRects(kind);
        const mouse_pressed = plat.input_buffer.mouseBtnIsJustPressed(.left);

        var ui_clicked = false;
        var selection_idx: ?usize = null;
        var cast_method: Options.CastMethod = .left_click;
        for (0..slots.len) |i| {
            const rect = rects.get(i);
            const slot = &slots[i];
            const mouse_pos = plat.input_buffer.getCurrMousePos();
            const hovered = geom.pointIsInRectf(mouse_pos, rect);

            if (hovered) {
                _ = slot.hover_timer.tick(false);
            } else {
                slot.hover_timer.restart();
            }

            switch (slot.kind) {
                .item => |_item| if (_item) |item| {
                    if (!item.canUse(room, caster)) continue;
                } else continue,
                .spell => |_spell| if (_spell == null) continue,
            }

            if (hovered and mouse_pressed) {
                ui_clicked = true;
                selection_idx = i;
                break;
            }

            if (plat.input_buffer.keyIsJustPressed(slot.key)) {
                selection_idx = i;
                cast_method = App.get().options.cast_method;
                break;
            }
        }

        if (selection_idx) |new_idx| {
            switch (kind) {
                .spell => {
                    self.state = .{ .spell = .{
                        .idx = new_idx,
                        .select_kind = .selected,
                    } };
                },
                .item => {
                    self.state = .{ .item = .{
                        .idx = new_idx,
                        .select_kind = .selected,
                    } };
                },
            }
            self.selected_method = cast_method;
        }

        return ui_clicked;
    }

    pub fn updateSelected(self: *Slots, room: *Room) void {
        const plat = App.getPlat();
        const caster = blk: {
            if (room.getConstPlayer()) |p| {
                if (p.hp.?.curr > 0) {
                    break :blk p;
                }
            }
            self.state = .none;
            return;
        };
        if (plat.input_buffer.mouseBtnIsJustPressed(.right)) {
            self.state = .none;
            return;
        }

        const clicked_a = self.updateSelectedSlots(room, caster, self.spells.slice(), .spell);
        const clicked_b = self.updateSelectedSlots(room, caster, self.items.slice(), .item);
        if (clicked_a or clicked_b) {
            room.ui_clicked = true;
        }
    }

    fn renderSlots(self: *const Slots, room: *const Room, caster: *const Thing, slots: []const Slot, kind: Slot.Kind, slots_are_enabled: bool) Error!void {
        const plat = App.getPlat();
        const rects = self.getSlotRects(kind);
        var slot_selected_or_buffered: ?struct { idx: usize, color: Colorf } = null;
        switch (self.state) {
            .none => {},
            .spell => |s| {
                if (kind == .spell) {
                    slot_selected_or_buffered = .{
                        .idx = s.idx,
                        .color = SelectionKind.colors.get(s.select_kind),
                    };
                }
            },
            .item => |s| {
                if (kind == .item) {
                    slot_selected_or_buffered = .{
                        .idx = s.idx,
                        .color = SelectionKind.colors.get(s.select_kind),
                    };
                }
            },
        }

        for (slots, 0..) |slot, i| {
            const slot_is_enabled = blk: {
                if (!slots_are_enabled) {
                    break :blk false;
                } else {
                    switch (slot.kind) {
                        .spell => |_spell| {
                            if (_spell) |_| break :blk true;
                        },
                        .item => |_item| {
                            if (_item) |item| break :blk item.canUse(room, caster);
                        },
                    }
                }
                break :blk false;
            };
            var rect = rects.get(i);
            const mouse_pos = plat.input_buffer.getCurrMousePos();
            const hovered = geom.pointIsInRectf(mouse_pos, rect);
            if (slot_is_enabled and hovered) {
                const new_dims = rect.dims.scale(1.1);
                rect.pos = rect.pos.sub(new_dims.sub(rect.dims).scale(0.5));
                rect.dims = new_dims;
            }
            const slot_center_pos = rect.pos.add(rect.dims.scale(0.5));
            const slot_icon_square_dims = V2f.splat(@min(rect.dims.x, rect.dims.y));

            plat.rectf(rect.pos, rect.dims, .{ .fill_color = Colorf.rgb(0.07, 0.05, 0.05) });

            var key_color = Colorf.gray;
            var border_color = Colorf.darkgray;
            if (slot_is_enabled) {
                border_color = .blue;
                key_color = .white;
            }

            const _render_info: ?sprites.RenderIconInfo = blk: switch (slot.kind) {
                .spell => |_spell| {
                    if (_spell) |spell| {
                        break :blk spell.getRenderIconInfo();
                    } else if (slot.cooldown_timer.?.running) {
                        const rads = slot.cooldown_timer.?.remapTo0_1() * utl.tau;
                        const radius = rect.dims.x * 0.5 * 0.7;
                        //std.debug.print("{d:.2}\n", .{rads});
                        plat.sectorf(slot_center_pos, radius, 0, rads, .{ .fill_color = .blue });
                    }
                    break :blk null;
                },
                .item => |_item| {
                    if (_item) |item| {
                        break :blk item.getRenderIconInfo();
                    }
                    break :blk null;
                },
            };
            if (slot_selected_or_buffered) |s| {
                if (s.idx == i) {
                    border_color = s.color;
                }
            }
            if (_render_info) |render_info| {
                switch (render_info) {
                    .frame => |frame| {
                        plat.texturef(slot_center_pos, frame.texture, .{
                            .origin = .center,
                            .src_pos = frame.pos.toV2f(),
                            .src_dims = frame.size.toV2f(),
                            .scaled_dims = slot_icon_square_dims.sub(V2f.splat(slot_icon_square_dims.x * 0.1)),
                        });
                    },
                    .letter => |letter| {
                        try plat.textf(
                            slot_center_pos,
                            "{s}",
                            .{&letter.str},
                            .{
                                .color = letter.color,
                                .size = utl.as(u32, @floor(slot_icon_square_dims.y)),
                                .center = true,
                            },
                        );
                    },
                }
            }
            // border
            plat.rectf(
                rect.pos,
                rect.dims,
                .{
                    .fill_color = null,
                    .outline_color = border_color,
                    .outline_thickness = 4,
                },
            );
            // hotkey
            try plat.textf(
                rect.pos.add(v2f(1, 1)),
                "{s}",
                .{&slot.key_str},
                .{ .color = key_color },
            );
        }
        for (slots, 0..) |slot, i| {
            const rect = rects.get(i);
            if (!slot.hover_timer.running) {
                switch (slot.kind) {
                    .spell => |_spell| {
                        if (_spell) |spell| {
                            try spell.renderToolTip(rect.pos.add(v2f(rect.dims.x, 0)));
                        }
                    },
                    .item => |_item| {
                        if (_item) |item| {
                            try item.renderToolTip(rect.pos.add(v2f(rect.dims.x, 0)));
                        }
                    },
                }
            }
        }
    }

    pub fn render(self: *const Slots, room: *const Room) Error!void {
        const plat = App.getPlat();
        const caster = blk: {
            if (room.getConstPlayer()) |p| {
                if (p.hp.?.curr > 0) {
                    break :blk p;
                }
            }
            return;
        };
        const slots_are_enabled = caster.hp.?.curr > 0;

        {
            const rects = self.getSlotRects(.spell);
            const last_rect = rects.get(rects.len - 1);
            const p = last_rect.pos.add(v2f(last_rect.dims.x + 10, 0));
            try plat.textf(p, "draw: {}\ndiscard: {}\n", .{ room.draw_pile.len, room.discard_pile.len }, .{ .color = .white });
        }

        try self.renderSlots(room, caster, self.spells.constSlice(), .spell, slots_are_enabled);
        try self.renderSlots(room, caster, self.items.constSlice(), .item, slots_are_enabled);
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
            const mouse_pos = plat.screenPosToCamPos(room.camera, plat.input_buffer.getCurrMousePos());
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
            const mouse_pos = plat.screenPosToCamPos(room.camera, plat.input_buffer.getCurrMousePos());
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
