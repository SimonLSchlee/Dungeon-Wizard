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
const Thing = @import("Thing.zig");
const Room = @import("Room.zig");
const Goat = @This();

pub const AI = struct {
    wander_dir: V2f = V2f.down,
};

pub fn protoype() Error!Thing {
    var ret = Thing{
        .kind = .goat,
        .spawn_state = .instance,
        .coll_radius = 20,
        .draw_color = Colorf.yellow,
        .vision_range = 160,
        .ai = .{ .goat = .{} },
        .coll_mask = Thing.CollMask.initMany(&.{ .creature, .tile }),
        .coll_layer = Thing.CollMask.initMany(&.{.creature}),
    };
    try ret.init();
    return ret;
}

pub fn render(self: *const Thing, room: *const Room) Error!void {
    const plat = getPlat();

    try Thing.defaultRender(self, room);

    if (debug.show_goat_ai) {
        {
            const txt_topleft = self.pos.add(v2f(self.coll_radius, -self.coll_radius - 10));
            try plat.textf(txt_topleft, "{}", .{self.kind.goat.last_command_id}, .{ .color = Colorf.red });
        }
        {
            plat.circlef(self.pos, self.coll_radius + self.vision_range, .{ .fill_color = null, .outline_color = Colorf.yellow.fade(0.5) });
        }
    }
}

pub fn update(self: *Thing, room: *Room) Error!void {
    assert(self.spawn_state == .spawned);

    var things_in_view: std.BoundedArray(*Thing, 16) = .{};
    for (&room.things.items) |*thing| {
        if (!thing.isActive()) continue;
        if (thing.id.eql(self.id)) continue;

        const dist = thing.pos.dist(self.pos);
        const range = @max(dist - self.coll_radius - thing.coll_radius, 0);

        if (range < self.vision_range) {
            things_in_view.append(thing) catch break;
        }
    }
    const ai = &self.ai.?.goat;
    const coll = Thing.getCircleCollisionWithTiles(self.pos.add(self.vel), self.coll_radius, room);
    if (coll.collided) {
        if (coll.normal.dot(ai.wander_dir) < 0) {
            ai.wander_dir = ai.wander_dir.neg();
        }
    }
    const follow_dir = ai.wander_dir;
    self.updateVel(follow_dir, .{});
    if (!self.vel.isZero()) {
        self.dir = self.vel.normalized();
    }
    try self.moveAndCollide(room);
}
