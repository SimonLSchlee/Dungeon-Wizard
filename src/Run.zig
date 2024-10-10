const std = @import("std");
const assert = std.debug.assert;
const u = @import("util.zig");

pub const Platform = @import("raylib.zig");
const core = @import("core.zig");
const Error = core.Error;
const Key = core.Key;
const draw = @import("draw.zig");
const Colorf = draw.Colorf;
const geom = @import("geometry.zig");
const V2f = @import("V2f.zig");
const v2f = V2f.v2f;
const V2i = @import("V2i.zig");
const v2i = V2i.v2i;

const Run = @This();
const App = @import("App.zig");
const getPlat = App.getPlat;
const Room = @import("Room.zig");
const Thing = @import("Thing.zig");
const Data = @import("Data.zig");

gold: i32 = 0,
room: ?Room = null,
screen: enum {
    game,
} = .game,
seed: u64,
rng: std.Random.DefaultPrng = undefined,
curr_room_num: usize = 0,
player_thing: ?Thing = null,
curr_tick: i64 = 0,

pub fn init(seed: u64) Error!Run {
    const ret: Run = .{
        .room = try Room.init(seed),
        .rng = std.Random.DefaultPrng.init(seed),
        .seed = seed,
    };

    return ret;
}

pub fn reset(self: *Run) Error!*Run {
    self.deinit();
    self.* = .{};
    try self.init();
    return self;
}

pub fn deinit(self: *Run) void {
    if (self.room) |*room| {
        room.deinit();
    }
}

pub fn update(self: *Run) Error!void {
    const plat = getPlat();
    switch (self.screen) {
        .game => {
            if (self.room) |*room| {
                if (plat.input_buffer.keyIsJustPressed(.f4)) {
                    try room.reset();
                }
                try room.update();
            }
        },
    }
}

pub fn render(self: *Run) Error!void {
    const plat = getPlat();
    switch (self.screen) {
        .game => {
            plat.clear(Colorf.magenta);
            if (self.room) |*room| {
                try room.render();
                //const game_scale: i32 = 2;
                //const game_dims_scaled_f = game_dims.scale(game_scale).toV2f();
                //const topleft = p.screen_dims_f.sub(game_dims_scaled_f).scale(0.5);
                const game_texture_opt = .{
                    .flip_y = true,
                };
                plat.texturef(.{}, room.render_texture.?.texture, game_texture_opt);
            }
        },
    }
}
