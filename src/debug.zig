const std = @import("std");
const utl = @import("util.zig");
const core = @import("core.zig");
const Error = core.Error;
const App = @import("App.zig");
const DateTime = @import("DateTime.zig");
const config = @import("config");
pub const assert = std.debug.assert;

pub const enable_debug_controls = false;

// misc
pub const show_mouse_pos = false;
pub const hide_ui = false;

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
