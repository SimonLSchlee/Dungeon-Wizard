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

pub const SpellSlots = struct {
    pub const Slot = struct {
        idx: usize,
        spell: ?Spell = null,
        draw_counter: utl.TickCounter = utl.TickCounter.initStopped(90),
    };
    pub const num_slots = 4;
    pub const idx_to_key = [num_slots]core.Key{ .q, .w, .e, .r };
    pub const idx_to_key_str = blk: {
        var arr: [num_slots][3]u8 = undefined;
        for (idx_to_key, 0..) |key, i| {
            const key_str = @tagName(key);
            const c: [1]u8 = .{std.ascii.toUpper(key_str[0])};
            const str = "[" ++ &c ++ "]";
            arr[i] = str.*;
        }
        break :blk arr;
    };
    const slot_dims = v2f(100, 120);
    const slot_spacing: f32 = 20;

    slots: [num_slots]Slot = blk: {
        var ret: [num_slots]Slot = undefined;
        for (0..num_slots) |i| {
            ret[i] = .{
                .idx = i,
            };
        }
        break :blk ret;
    },
    state: union(enum) {
        none,
        selected: usize,
        buffered: usize,
    } = .none,
    selected_method: Options.CastMethod = .left_click,

    pub fn init(room: *Room) SpellSlots {
        var ret = SpellSlots{};
        for (&ret.slots) |*slot| {
            if (room.drawSpell()) |spell| {
                slot.spell = spell;
            }
        }
        return ret;
    }

    pub fn getSlotRects() [num_slots]geom.Rectf {
        const plat = App.getPlat();
        const center_pos: V2f = v2f(plat.screen_dims_f.x * 0.5, plat.screen_dims_f.y - 50 - slot_dims.y * 0.5);
        var ret: [num_slots]geom.Rectf = undefined;
        layoutRectsFixedSize(num_slots, slot_dims, center_pos, .{ .space_between = slot_spacing }, &ret);
        return ret;
    }

    pub fn getSelectedSlot(self: *const SpellSlots) ?Slot {
        switch (self.state) {
            .selected => |i| {
                assert(self.slots[i].spell != null);
                return self.slots[i];
            },
            else => {},
        }
        return null;
    }

    pub fn render(self: *const SpellSlots, room: *const Room) Error!void {
        const plat = App.getPlat();
        const data = App.get().data;
        const rects = getSlotRects();

        const slots_are_enabled = if (room.getConstPlayer()) |p|
            p.hp.?.curr > 0
        else
            false;

        for (self.slots, 0..) |slot, i| {
            const key_str = idx_to_key_str[i];
            const rect = rects[i];
            const slot_center_pos = rect.pos.add(slot_dims.scale(0.5));
            var key_color = Colorf.gray;
            var border_color = Colorf.darkgray;
            plat.rectf(rect.pos, rect.dims, .{ .fill_color = Colorf.black });
            if (slot.spell) |spell| {
                key_color = .white;
                if (slots_are_enabled) {
                    border_color = .blue;
                    switch (self.state) {
                        .selected => |idx| {
                            if (idx == i) {
                                border_color = Colorf.orange;
                            }
                        },
                        .buffered => |idx| {
                            if (idx == i) {
                                border_color = Colorf.green;
                            }
                        },
                        else => {},
                    }
                }
                const name: []const u8 = @tagName(spell.kind);
                const kind = std.meta.activeTag(spell.kind);
                //const kind = std.meta.stringToEnum(Spell.Kind, name).?;
                const spell_char = [1]u8{std.ascii.toUpper(name[0])};
                // spell image
                if (data.spell_icons_indices.get(kind)) |idx| {
                    const sheet = data.spell_icons;
                    const frame = sheet.frames[utl.as(usize, idx)];
                    plat.texturef(slot_center_pos, sheet.texture, .{
                        .origin = .center,
                        .src_pos = frame.pos.toV2f(),
                        .src_dims = frame.size.toV2f(),
                        .uniform_scaling = 4,
                    });
                } else {
                    // spell letter
                    try plat.textf(
                        slot_center_pos,
                        "{s}",
                        .{&spell_char},
                        .{
                            .color = spell.color,
                            .size = 40,
                            .center = true,
                        },
                    );
                }
            } else if (slot.draw_counter.running) {
                const rads = slot.draw_counter.remapTo0_1() * utl.tau;
                const radius = slot_dims.x * 0.5 * 0.7;
                //std.debug.print("{d:.2}\n", .{rads});
                plat.sectorf(slot_center_pos, radius, 0, rads, .{ .fill_color = .blue });
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
                .{&key_str},
                .{ .color = key_color },
            );
        }

        {
            const last_rect = rects[rects.len - 1];
            const p = last_rect.pos.add(v2f(last_rect.dims.x + 10, 0));
            try plat.textf(p, "draw: {}\ndiscard: {}\n", .{ room.draw_pile.len, room.discard_pile.len }, .{ .color = .white });
        }
    }

    pub fn clearSlot(self: *SpellSlots, slot_idx: usize) void {
        assert(slot_idx < num_slots);
        const slot = &self.slots[slot_idx];
        assert(slot.spell != null);
        slot.spell = null;
        slot.draw_counter.restart();
        switch (self.state) {
            .selected => |idx| {
                if (idx == slot_idx) {
                    self.state = .none;
                }
            },
            .buffered => |idx| {
                if (idx == slot_idx) {
                    self.state = .none;
                }
            },
            else => {},
        }
    }

    pub fn updateTimerAndDrawSpell(self: *SpellSlots, room: *Room) void {
        for (&self.slots) |*slot| {
            // only tick and draw into empty slots!
            if (slot.spell == null) {
                if (slot.draw_counter.tick(false)) {
                    if (room.drawSpell()) |spell| {
                        slot.spell = spell;
                    }
                }
            }
        }
    }

    pub fn updateSelected(self: *SpellSlots, room: *Room) void {
        const plat = App.getPlat();
        const rects = getSlotRects();
        const mouse_pressed = plat.input_buffer.mouseBtnIsJustPressed(.left);
        const slots_are_enabled = if (room.getConstPlayer()) |p|
            p.hp.?.curr > 0
        else
            false;

        var selection_idx: ?usize = null;
        var cast_method: Options.CastMethod = .left_click;
        for (0..num_slots) |i| {
            const rect = rects[i];
            const slot = &self.slots[i];
            if (slot.spell != null) {
                if (slots_are_enabled) {
                    if (selection_idx == null and mouse_pressed) {
                        const mouse_pos = plat.input_buffer.getCurrMousePos();
                        if (geom.pointIsInRectf(mouse_pos, rect)) {
                            room.ui_clicked = true;
                            selection_idx = i;
                            break;
                        }
                    } else {
                        const key = idx_to_key[i];
                        if (plat.input_buffer.keyIsJustPressed(key)) {
                            selection_idx = i;
                            cast_method = App.get().options.cast_method;
                            break;
                        }
                    }
                }
            }
        }

        if (selection_idx) |new| {
            self.state = .{ .selected = new };
            self.selected_method = cast_method;
        } else if (plat.input_buffer.mouseBtnIsJustPressed(.right)) {
            self.state = .none;
        }
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
