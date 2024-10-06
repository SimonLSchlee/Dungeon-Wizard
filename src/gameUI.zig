const std = @import("std");
const u = @import("util.zig");

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

pub const SpellSlots = struct {
    pub const Slot = struct {
        spell: Spell,
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
    const slot_dims = v2f(60, 80);
    const slot_spacing: f32 = 20;

    slots: [num_slots]?Slot = .{null} ** num_slots,
    selected: ?usize = null,

    pub fn getSlotRects() [num_slots]geom.Rectf {
        const plat = App.getPlat();
        const center_pos: V2f = v2f(plat.screen_dims_f.x * 0.5, plat.screen_dims_f.y - 50);
        const total_width = num_slots * slot_dims.x + (num_slots - 1) * slot_spacing;
        const top_left = center_pos.sub(v2f(total_width * 0.5, slot_dims.y));
        var ret: [num_slots]geom.Rectf = undefined;

        for (0..num_slots) |i| {
            const offset = v2f(u.as(f32, i) * (slot_dims.x + slot_spacing), 0);
            const pos = top_left.add(offset);
            ret[i] = .{
                .pos = pos,
                .dims = slot_dims,
            };
        }
        return ret;
    }

    pub fn getSelected(self: *const SpellSlots) ?Spell {
        if (self.selected) |i| {
            if (self.slots[i]) |slot| {
                return slot.spell;
            }
        }
        return null;
    }

    pub fn render(self: *const SpellSlots, _: *const Room) Error!void {
        const plat = App.getPlat();
        const rects = getSlotRects();

        for (self.slots, 0..) |_slot, i| {
            const key_str = idx_to_key_str[i];
            const rect = rects[i];
            var key_color = Colorf.gray;
            var border_color = Colorf.darkgray;
            plat.rectf(rect.pos, rect.dims, .{ .fill_color = Colorf.black });
            if (_slot) |slot| {
                key_color = .white;
                border_color = .blue;
                if (self.selected) |selected| {
                    if (selected == i) {
                        border_color = Colorf.orange;
                    }
                }
                const name: []const u8 = @tagName(slot.spell.kind);
                const spell_char = [1]u8{name[0]};
                // TODO spell image
                // spell letter
                try plat.textf(
                    rect.pos.add(slot_dims.scale(0.5)),
                    "{s}",
                    .{&spell_char},
                    .{
                        .color = .lightgray,
                        .size = 40,
                        .center = true,
                    },
                );
            } else {
                //
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
    }

    pub fn update(self: *SpellSlots, _: *Room) Error!void {
        const plat = App.getPlat();
        const rects = getSlotRects();
        const mouse_pressed = plat.input_buffer.mouseBtnIsJustPressed(.left);

        var selection: ?usize = null;
        for (0..num_slots) |i| {
            const rect = rects[i];
            if (mouse_pressed) {
                const mouse_pos = plat.input_buffer.getCurrMousePos();
                if (self.slots[i]) |_| {
                    if (geom.pointIsInRectf(mouse_pos, rect)) {
                        selection = i;
                        break;
                    }
                }
            } else {
                const key = idx_to_key[i];
                if (plat.input_buffer.keyIsJustPressed(key)) {
                    if (self.slots[i]) |_| {
                        selection = i;
                        break;
                    }
                }
            }
        }
        if (selection) |new| blk: {
            if (self.selected) |old| {
                if (new == old) {
                    self.selected = null;
                    break :blk;
                }
            }
            self.selected = new;
        } else if (self.selected) |_| {
            if (plat.input_buffer.mouseBtnIsJustPressed(.right)) {
                self.selected = null;
            }
        }
    }
};
