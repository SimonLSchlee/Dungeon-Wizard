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
        var arr: [num_slots][]const u8 = .{""} ** num_slots;
        for (idx_to_key, 0..) |key, i| {
            const key_str = @tagName(key);
            const c: [1]u8 = .{std.ascii.toUpper(key_str[0])};
            const str = "[" ++ &c ++ "]";
            arr[i] = str;
        }
        break :blk arr;
    };

    slots: [num_slots]?Slot = .{null} ** num_slots,
    selected: ?u8 = null,

    pub fn render(self: *const SpellSlots, _: *const Room, center_pos: V2f) Error!void {
        const plat = App.getPlat();
        const slot_dims = v2f(60, 80);
        const spacing: f32 = 20;
        const total_width = num_slots * slot_dims.x + (num_slots - 1) * spacing;
        const top_left = center_pos.sub(v2f(total_width * 0.5, slot_dims.y));

        for (self.slots, 0..) |_slot, i| {
            const key_str = idx_to_key_str[i];
            const offset = v2f(u.as(f32, i) * (slot_dims.x + spacing), 0);
            const pos = top_left.add(offset);
            var key_color = Colorf.gray;
            var border_color = Colorf.darkgray;
            plat.rectf(pos, slot_dims, .{ .fill_color = Colorf.black });
            if (_slot) |slot| {
                key_color = .white;
                border_color = .blue;
                if (self.selected) |selected| {
                    if (selected == i) {
                        border_color = Colorf.orange;
                    }
                }
                const name: []const u8 = @tagName(slot.spell.kind);
                const char = name[0];
                try plat.textf(pos.add(slot_dims.scale(0.5)), "{s}", .{&char}, .{ .color = .lightgray, .size = 40 });
            } else {
                //
            }
            plat.rectf(pos, slot_dims, .{ .outline_color = border_color, .outline_thickness = 4 });
            try plat.textf(pos.add(v2f(1, 1)), "{s}", .{key_str}, .{ .color = key_color });
        }
    }
};
