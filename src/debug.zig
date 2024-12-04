const std = @import("std");

pub const assert = std.debug.assert;

pub const enable_debug_controls = false;

// ai stuff
pub const show_thing_paths = false;
pub const show_thing_coords_searched = false;
pub const show_ai_decision = false;
pub const show_hiding_places = false;

// various Room stuff
pub const show_thing_collisions = false;
pub const show_tilemap_grid = false;
pub const show_hitboxes = false;
pub const show_selectable = false;
pub const show_waves = false;

// stats n whatnot
pub const show_num_enemies = false;
pub const show_highest_num_things_in_room = false;

pub fn errorAndStackTrace(e: anytype) void {
    std.debug.print("ERROR: {any}\n", .{e});
    std.debug.dumpCurrentStackTrace(null);
}
