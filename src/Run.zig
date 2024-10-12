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
const Spell = @import("Spell.zig");
const Thing = @import("Thing.zig");
const Data = @import("Data.zig");
const PackedRoom = @import("PackedRoom.zig");

const Reward = struct {
    spells: std.BoundedArray(Spell, 3),
};

gold: i32 = 0,
room: ?Room = null,
reward: ?Reward = null,
screen: enum {
    game,
    pause,
    reward,
    shop,
} = .game,
seed: u64,
rng: std.Random.DefaultPrng = undefined,
rooms_completed: std.BoundedArray(PackedRoom, 32) = .{},
room_pool: std.BoundedArray(PackedRoom, 32) = .{},
curr_room_num: usize = 0,
player_thing: ?Thing = null,
curr_tick: i64 = 0,

pub fn init(seed: u64) Error!Run {
    const app = App.get();

    var ret: Run = .{
        .rng = std.Random.DefaultPrng.init(seed),
        .seed = seed,
    };
    for (app.data.levels) |str| {
        const packed_room = try PackedRoom.init(str);
        ret.room_pool.append(packed_room) catch break;
    }
    assert(ret.room_pool.len > 0);
    const pr = ret.room_pool.get(0);
    ret.room = try Room.init(pr, 10, seed);

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
            assert(self.room != null);
            const room = &self.room.?;
            if (plat.input_buffer.keyIsJustPressed(.f4)) {
                try room.reset();
            }
            try room.update();
        },
        .pause => {},
        .reward => {
            assert(self.reward != null);
            const reward = &self.reward.?;
            _ = reward;
        },
        .shop => {},
    }
}

pub fn render(self: *Run) Error!void {
    const plat = getPlat();

    plat.clear(Colorf.magenta);
    switch (self.screen) {
        .game => {
            assert(self.room != null);
            const room = &self.room.?;
            try room.render();
            //const game_scale: i32 = 2;
            //const game_dims_scaled_f = game_dims.scale(game_scale).toV2f();
            //const topleft = p.screen_dims_f.sub(game_dims_scaled_f).scale(0.5);
            const game_texture_opt = .{
                .flip_y = true,
            };
            plat.texturef(.{}, room.render_texture.?.texture, game_texture_opt);
        },
        .pause => {},
        .reward => {
            assert(self.reward != null);
            const reward = &self.reward.?;
            _ = reward;
        },
        .shop => {},
    }
    { // gold
        const fill_color = Colorf.rgb(1, 0.9, 0);
        const text_color = Colorf.rgb(0.44, 0.3, 0.0);
        const poly_opt = .{ .fill_color = fill_color, .outline_color = text_color, .outline_thickness = 10 };
        const center = v2f(150, plat.screen_dims_f.y - 100);
        const num = 3;
        const lower = center.add(v2f(0, 7 * num));
        for (0..num) |i| {
            plat.circlef(lower.add(v2f(0, u.as(f32, i) * -7)), 55, poly_opt);
        }
        const gold_width = (try plat.measureText("Gold", .{ .size = 25 })).x;
        try plat.textf(center.sub(v2f(gold_width, 0)), "Gold: {}", .{self.gold}, .{
            .color = text_color,
            .size = 25,
        });
    }
}
