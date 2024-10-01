const std = @import("std");
const utl = @import("../util.zig");

pub const Platform = @import("../raylib.zig");
const core = @import("../core.zig");
const Error = core.Error;
const Key = core.Key;
const debug = @import("../debug.zig");
const assert = debug.assert;
const draw = @import("../draw.zig");
const Colorf = draw.Colorf;
const geom = @import("../geometry.zig");
const V2f = @import("../V2f.zig");
const v2f = V2f.v2f;
const V2i = @import("../V2i.zig");
const v2i = V2i.v2i;

const App = @import("../App.zig");
const getPlat = App.getPlat;
const Room = @import("../Room.zig");
const Thing = @import("../Thing.zig");
const TileMap = @import("../TileMap.zig");

const Spell = @import("../Spell.zig");
const TargetKind = Spell.TargetKind;
const TargetingData = Spell.TargetingData;
const Params = Spell.Params;

pub const enum_name = "unherring";
pub const Controllers = [_]type{Projectile};

pub const proto = Spell.makeProto(
    .unherring,
    .{
        .color = .red,
        .targeting_data = .{
            .kind = .thing,
            .target_enemy = true,
        },
    },
);

damage: f32 = 10,

pub fn render(self: *const Thing, room: *const Room) Error!void {
    _ = self;
    _ = room;
}

pub const Projectile = struct {
    pub const controller_enum_name = enum_name ++ "_projectile";

    pub fn update(self: *Thing, room: *Room) Error!void {
        const spell = self.controller.spell.spell;
        const params = self.controller.spell.params;
        const target_id = params.target.thing;
        const damage = spell.kind.unherring.damage;
        var done = false;
        if (room.getThingById(target_id)) |target| {
            const v = target.pos.sub(self.pos);
            if (v.length() < self.coll_radius + target.coll_radius) {
                // hit em
                // explode?
                std.debug.print("{} damageu!\n", .{damage});
                done = true;
            } else {
                self.updateVel(v.normalized(), self.accel_params);
                self.updateDir(self.vel, .{ .ang_accel = 999, .max_ang_vel = 999 });
                try self.moveAndCollide(room);
            }
        } else {
            done = true;
        }
        if (done) {
            self.deferFree(room);
        }
    }
};

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    assert(std.meta.activeTag(params.target) == Spell.TargetKind.thing);
    assert(utl.unionTagEql(params.target, .{ .thing = .{} }));

    var herring = Thing{
        .kind = .projectile,
        .coll_radius = 5,
        .accel_params = .{
            .accel = 0.5,
            .max_speed = 5,
        },
        .controller = .{ .spell = .{
            .spell = self.*,
            .params = params,
            .controller = .{ .unherring_projectile = .{} },
        } },
        .renderer = .{ .default = .{
            .draw_color = .white,
            .draw_radius = 5,
        } },
    };
    try herring.init();
    defer herring.deinit();
    _ = try room.queueSpawnThing(&herring, caster.pos);
}
