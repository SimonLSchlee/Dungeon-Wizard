const std = @import("std");
const assert = std.debug.assert;
const utl = @import("util.zig");

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

const App = @import("App.zig");
const getPlat = App.getPlat;
const Data = @import("Data.zig");
const Thing = @import("Thing.zig");
const Room = @import("Room.zig");
const Spell = @import("Spell.zig");
const Item = @import("Item.zig");
const gameUI = @import("gameUI.zig");
const sprites = @import("sprites.zig");
const StatusEffect = @import("StatusEffect.zig");
const TileMap = @import("TileMap.zig");
const Action = @This();

pub const Gobarrow = struct {
    pub const enum_name = "gobarrow";
    state: enum {
        in_flight,
        hitting,
        destroyed,
    } = .in_flight,

    pub fn update(self: *Thing, room: *Room) Error!void {
        assert(self.spawn_state == .spawned);
        var controller = &self.controller.projectile.kind.gobarrow;
        switch (controller.state) {
            .in_flight => {
                const done = self.last_coll != null or if (self.hitbox) |h| !h.active else false;
                if (done) {
                    controller.state = .hitting;
                    self.vel = .{};
                    return;
                }
                self.updateVel(self.dir, self.accel_params);
            },
            .hitting => {
                // TODO anim
                self.deferFree(room);
                return;
            },
            .destroyed => {
                // TODO anim
                self.deferFree(room);
                return;
            },
        }
    }

    pub fn proto(room: *Room) Thing {
        var arrow = Thing{
            .kind = .projectile,
            .coll_radius = 2.5,
            .accel_params = .{
                .accel = 2,
                .friction = 0,
                .max_speed = 2.2,
            },
            .coll_mask = Thing.Collision.Mask.initMany(&.{.wall}),
            .controller = .{ .projectile = .{ .kind = .{
                .gobarrow = .{},
            } } },
            .renderer = .{ .shape = .{
                .kind = .{ .arrow = .{
                    .length = 17.5,
                    .thickness = 1.5,
                } },
                .poly_opt = .{ .fill_color = draw.Coloru.rgb(220, 172, 89).toColorf() },
            } },
            .hitbox = .{
                .deactivate_on_hit = true,
                .deactivate_on_update = false,
                .effect = .{ .damage = 6 },
                .radius = 2,
                .rel_pos = V2f.right.scale(14),
            },
        };
        arrow.hitbox.?.activate(room);
        return arrow;
    }
};

pub const FireBlaze = struct {
    pub const enum_name = "fire_blaze";
    const AnimRef = struct {
        var loop = Data.Ref(Data.SpriteAnim).init("trailblaze-loop");
        var end = Data.Ref(Data.SpriteAnim).init("trailblaze-end");
    };

    loops_til_end: i32 = 2,
    state: enum {
        loop,
        end,
    } = .loop,

    pub fn update(self: *Thing, room: *Room) Error!void {
        const controller: *@This() = &self.controller.projectile.kind.fire_blaze;
        const renderer = &self.renderer.sprite;
        switch (controller.state) {
            .loop => {
                const events = renderer.playNormal(AnimRef.loop, .{ .loop = true });
                if (events.contains(.end)) {
                    controller.loops_til_end -= 1;
                    if (controller.loops_til_end <= 0) {
                        controller.state = .end;
                    }
                } else if (events.contains(.hit)) {
                    self.hitbox.?.activate(room);
                }
            },
            .end => {
                if (renderer.playNormal(AnimRef.end, .{}).contains(.end)) {
                    self.deferFree(room);
                }
            },
        }
    }

    pub fn proto(_: *Room) Thing {
        var ret = Thing{
            .kind = .projectile,
            .spawn_state = .instance,
            .controller = .{ .projectile = .{ .kind = .{
                .fire_blaze = .{},
            } } },
            .renderer = .{ .sprite = .{} },
            .hitbox = .{
                .mask = Thing.Faction.Mask.initFull(),
                .radius = 12.5,
                .sweep_to_rel_pos = v2f(0, -12.5),
                .deactivate_on_hit = false,
                .deactivate_on_update = true,
                .effect = .{
                    .damage = 0,
                    .can_be_blocked = false,
                    .status_stacks = StatusEffect.StacksArray.initDefault(0, .{ .lit = 1 }),
                },
            },
        };
        _ = AnimRef.loop.get();
        _ = AnimRef.end.get();
        ret.renderer.sprite.setNormalAnim(AnimRef.loop);
        return ret;
    }
};

pub const Gobbomb = struct {
    pub const enum_name = "gobbomb";

    const AnimRef = struct {
        var loop = Data.Ref(Data.SpriteAnim).init("bomb-loop");
        var explode = Data.Ref(Data.SpriteAnim).init("gobbomb-explode");
        var got: bool = false;
    };

    state: enum {
        in_flight,
        hitting,
        destroyed,
    } = .in_flight,
    target_pos: V2f = .{},
    timer: utl.TickCounter = .{},
    z_vel: f32 = 0,
    z_accel: f32 = 0,

    pub fn update(self: *Thing, room: *Room) Error!void {
        assert(self.spawn_state == .spawned);
        var controller = &self.controller.projectile.kind.gobbomb;
        const renderer = &self.renderer.sprite;
        renderer.scale = core.game_sprite_scaling * 0.5;

        switch (controller.state) {
            .in_flight => {
                _ = renderer.playNormal(AnimRef.loop, .{ .loop = true });
                if (self.hitbox) |*h| {
                    h.rel_pos = controller.target_pos.sub(self.pos);
                }
                _ = controller.timer.tick(false);
                controller.z_vel += controller.z_accel;
                renderer.rel_pos.y += -controller.z_vel;
                if (self.pos.dist(controller.target_pos) < self.accel_params.max_speed) {
                    self.vel = .{};
                    if (self.hitbox) |*h| {
                        h.activate(room);
                    }
                    controller.state = .hitting;
                } else {
                    self.updateVel(self.dir, self.accel_params);
                }
            },
            .hitting => {
                if (renderer.playNormal(AnimRef.explode, .{}).contains(.end)) {
                    self.deferFree(room);
                    return;
                }
            },
            else => {
                self.deferFree(room);
                return;
            },
        }
    }

    fn proto(_: *Room) Thing {
        const flight_ticks = core.secsToTicks(2);
        const max_y: f32 = 150;
        const v0: f32 = 2 * max_y / utl.as(f32, flight_ticks);
        const g = -2 * v0 / utl.as(f32, flight_ticks);
        var bomb = Thing{
            .kind = .projectile,
            .accel_params = .{
                .accel = 2,
                .friction = 0,
                .max_speed = 1,
            },
            .controller = .{ .projectile = .{ .kind = .{
                .gobbomb = .{
                    .timer = utl.TickCounter.init(flight_ticks),
                    .z_vel = v0,
                    .z_accel = g,
                },
            } } },
            .renderer = .{ .sprite = .{} },
            .hitbox = .{
                .active = false,
                .deactivate_on_hit = false,
                .deactivate_on_update = true,
                .effect = .{ .damage = 10 },
                .radius = 17.5,
            },
        };
        _ = AnimRef.loop.get();
        _ = AnimRef.explode.get();
        bomb.renderer.sprite.setNormalAnim(AnimRef.loop);
        return bomb;
    }
};

pub const SlimePuddle = struct {
    pub const enum_name = "slimepuddle";

    timer: utl.TickCounter = utl.TickCounter.init(7 * core.fups_per_sec),
    state: enum {
        loop,
        end,
    } = .loop,

    pub fn update(self: *Thing, room: *Room) Error!void {
        const controller: *@This() = &self.controller.projectile.kind.slimepuddle;
        const Ref = struct {
            var loop = Data.Ref(Data.SpriteAnim).init("slime-puddle-loop");
            var end = Data.Ref(Data.SpriteAnim).init("slime-puddle-end");
            var got: bool = false;
        };
        if (!Ref.got) {
            _ = Ref.loop.get();
            _ = Ref.end.get();
            Ref.got = true;
        }
        const renderer = &self.renderer.sprite;
        switch (controller.state) {
            .loop => {
                _ = renderer.playNormal(Ref.loop, .{ .loop = true });
                if (controller.timer.tick(false)) {
                    controller.state = .end;
                    self.hitbox.?.active = false;
                }
            },
            .end => {
                if (renderer.playNormal(Ref.end, .{}).contains(.end)) {
                    self.deferFree(room);
                }
            },
        }
    }

    pub fn proto(_: *Room) Thing {
        var ret = Thing{
            .kind = .projectile,
            .spawn_state = .instance,
            .controller = .{ .projectile = .{ .kind = .{
                .slimepuddle = .{},
            } } },
            .renderer = .{ .sprite = .{
                .draw_normal = false,
                .draw_under = true,
            } },
            .hitbox = .{
                .active = true, // id-less hit effect
                .deactivate_on_hit = false,
                .deactivate_on_update = false,
                .mask = Thing.Faction.Mask.initFull(),
                .path_mask = TileMap.PathLayer.Mask.initOne(.normal),
                .radius = 12.5,
                .effect = .{
                    .damage = 0,
                    .can_be_blocked = false,
                    .status_stacks = StatusEffect.StacksArray.initDefault(0, .{ .slimed = 1 }),
                },
            },
        };
        ret.renderer.sprite.setNormalAnim(Data.Ref(Data.SpriteAnim).init("slime-puddle-loop"));
        return ret;
    }
};

pub const DjinnCrescent = struct {
    pub const enum_name = "djinncrescent";
    const AnimRef = struct {
        var crescent_projectile = Data.Ref(Data.SpriteAnim).init("spell-projectile-djinn-crescent");
    };
    target_pos: V2f = undefined,
    lifetimer: utl.TickCounter = utl.TickCounter.init(core.secsToTicks(3)),
    state: enum {
        in_flight,
        hitting,
        destroyed,
    } = .in_flight,

    pub fn update(self: *Thing, room: *Room) Error!void {
        assert(self.spawn_state == .spawned);
        var controller = &self.controller.projectile.kind.djinncrescent;
        const renderer = &self.renderer.sprite;
        switch (controller.state) {
            .in_flight => {
                const done = controller.lifetimer.tick(false) or self.last_coll != null or if (self.hitbox) |h| !h.active else false;
                if (done) {
                    controller.state = .hitting;
                    self.vel = .{};
                    return;
                }
                self.dir = controller.target_pos.sub(self.pos).normalizedChecked() orelse V2f.right;
                self.updateVel(self.dir, self.accel_params);
                _ = renderer.tickCurrAnim(.{ .loop = true });
            },
            .hitting => {
                // TODO anim
                self.deferFree(room);
                return;
            },
            .destroyed => {
                // TODO anim
                self.deferFree(room);
                return;
            },
        }
    }

    pub fn proto(room: *Room) Thing {
        var crescent = Thing{
            .kind = .projectile,
            .coll_radius = 2.5,
            .accel_params = .{
                .accel = 0.1,
                .friction = 0.001,
                .max_speed = 2,
            },
            .coll_mask = Thing.Collision.Mask.initMany(&.{.wall}),
            .controller = .{ .projectile = .{ .kind = .{
                .djinncrescent = .{},
            } } },
            .renderer = .{
                .sprite = .{
                    .draw_over = false,
                    .draw_normal = true,
                    .rotate_to_dir = true,
                    .flip_x_to_dir = true,
                    .rel_pos = v2f(0, -14),
                },
            },
            .hitbox = .{
                .deactivate_on_hit = true,
                .deactivate_on_update = false,
                .effect = .{ .damage = 7 },
                .radius = 8,
            },
            .shadow_radius_x = 8,
        };
        crescent.hitbox.?.activate(room);
        crescent.renderer.sprite.setNormalAnim(AnimRef.crescent_projectile);
        return crescent;
    }
};

pub const Snowball = struct {
    pub const enum_name = "snowball";
    const AnimRef = struct {
        var ball_projectile = Data.Ref(Data.SpriteAnim).init("spell-projectile-snowball");
    };
    state: enum {
        in_flight,
        hitting,
        destroyed,
    } = .in_flight,

    pub fn update(self: *Thing, room: *Room) Error!void {
        assert(self.spawn_state == .spawned);
        var controller = &self.controller.projectile.kind.snowball;
        switch (controller.state) {
            .in_flight => {
                const done = self.last_coll != null or if (self.hitbox) |h| !h.active else false;
                if (done) {
                    controller.state = .hitting;
                    self.vel = .{};
                    return;
                }
                self.updateVel(self.dir, self.accel_params);
            },
            .hitting => {
                // TODO anim
                self.deferFree(room);
                return;
            },
            .destroyed => {
                // TODO anim
                self.deferFree(room);
                return;
            },
        }
    }

    pub fn proto(room: *Room) Thing {
        var ball = Thing{
            .kind = .projectile,
            .coll_radius = 3,
            .accel_params = .{
                .accel = 2.5,
                .friction = 0,
                .max_speed = 2.5,
            },
            .coll_mask = Thing.Collision.Mask.initMany(&.{.wall}),
            .controller = .{ .projectile = .{ .kind = .{
                .snowball = .{},
            } } },
            .renderer = .{ .sprite = .{
                .draw_over = false,
                .draw_normal = true,
                .rotate_to_dir = true,
                .flip_x_to_dir = true,
                .rel_pos = v2f(0, -12),
            } },
            .hitbox = .{
                .deactivate_on_hit = true,
                .deactivate_on_update = false,
                .effect = .{
                    .damage = 3,
                    .damage_kind = .ice,
                    .status_stacks = StatusEffect.StacksArray.initDefault(0, .{ .cold = 1 }),
                },
                .radius = 4,
            },
            .shadow_radius_x = 4,
        };
        ball.hitbox.?.activate(room);
        ball.renderer.sprite.setNormalAnim(AnimRef.ball_projectile);
        return ball;
    }
};

pub const FairyBall = struct {
    pub const enum_name = "fairy_ball";

    target_pos: V2f = .{},
    target_thing: Thing.Id = undefined,
    target_radius: f32 = 30,
    state: enum {
        loop,
        end,
    } = .loop,

    pub fn update(self: *Thing, room: *Room) Error!void {
        var controller = &self.controller.projectile.kind.fairy_ball;

        const target_id = controller.target_thing;
        const maybe_target_thing = room.getThingById(target_id);
        if (maybe_target_thing) |thing| {
            controller.target_pos = thing.pos;
        }
        const target_dir = if (controller.target_pos.sub(self.pos).normalizedChecked()) |d| d else V2f.right;

        switch (controller.state) {
            .loop => {
                self.updateVel(target_dir, self.accel_params);
                if (self.vel.normalizedChecked()) |n| {
                    self.dir = n;
                }
                self.accel_params.accel += 0.01;
                _ = self.renderer.sprite.tickCurrAnim(.{ .loop = true });

                const dist_to_target = self.pos.dist(controller.target_pos);
                if (dist_to_target <= @max(10, self.accel_params.accel)) {
                    if (maybe_target_thing) |target| {
                        if (target.hurtbox) |*hurtbox| {
                            hurtbox.hit(target, room, self.hitbox.?.effect, null);
                        }
                    }
                    controller.state = .end;
                    self.vel = .{};
                }
            },
            .end => {
                self.deferFree(room);
            },
        }
    }
    pub fn proto(_: *Room) Thing {
        const ball = Thing{
            .kind = .projectile,
            .accel_params = .{
                .accel = 3.5,
                .friction = 0.001,
                .max_speed = 3.5,
            },
            .controller = .{ .projectile = .{ .kind = .{
                .fairy_ball = .{},
            } } },
            .renderer = .{ .sprite = .{
                .draw_over = false,
                .draw_normal = true,
                .rotate_to_dir = true,
                .flip_x_to_dir = true,
                .rel_pos = v2f(0, -12),
            } },
            .hitbox = .{
                .active = false,
                .effect = .{
                    .damage = 0,
                },
                .radius = 4,
            },
            .shadow_radius_x = 4,
        };
        return ball;
    }
};

pub const ProjectileTypes = [_]type{
    FireBlaze,
    Gobarrow,
    Gobbomb,
    SlimePuddle,
    DjinnCrescent,
    Snowball,
    FairyBall,
};

pub const Kind = utl.EnumFromTypes(&ProjectileTypes, "enum_name");
pub const KindData = utl.TaggedUnionFromTypes(&ProjectileTypes, "enum_name", Kind);

pub fn GetKindType(kind: Kind) type {
    const fields: []const std.builtin.Type.UnionField = std.meta.fields(KindData);
    if (std.meta.fieldIndex(KindData, @tagName(kind))) |i| {
        return fields[i].type;
    }
    @compileError("No Projectile kind: " ++ @tagName(kind));
}

pub fn proto(room: *Room, kind: Kind) Thing {
    switch (kind) {
        inline else => |k| {
            return GetKindType(k).proto(room);
        },
    }
}

pub const Controller = struct {
    kind: KindData,

    pub fn update(self: *Thing, room: *Room) Error!void {
        assert(self.spawn_state == .spawned);
        switch (self.controller.projectile.kind) {
            inline else => |c| try @TypeOf(c).update(self, room),
        }
    }
};
