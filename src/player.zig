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
const Thing = @import("Thing.zig");
const Room = @import("Room.zig");
const Spell = @import("Spell.zig");
const Item = @import("Item.zig");
const gameUI = @import("gameUI.zig");
const Player = @This();

pub const enum_name = "player";

pub fn protoype() Error!Thing {
    return Thing{
        .kind = .creature,
        .creature_kind = .player,
        .spawn_state = .instance,
        .accel_params = .{
            .accel = 0.15,
            .friction = 0.09,
            .max_speed = 1.2,
        },
        .coll_radius = 20,
        .vision_range = 300,
        .coll_mask = Thing.Collision.Mask.initMany(&.{ .creature, .tile }),
        .coll_layer = Thing.Collision.Mask.initMany(&.{.creature}),
        .player_input = Input{},
        .controller = .{ .player = .{} },
        .renderer = .{ .creature = .{
            .draw_color = .cyan,
            .draw_radius = 20,
        } },
        .animator = .{ .creature = .{
            .creature_kind = .wizard,
        } },
        .hurtbox = .{
            .radius = 15,
        },
        .selectable = .{
            .height = 15 * 4, // TODO pixellszslz
            .radius = 6 * 4,
        },
        .hp = Thing.HP.init(40),
        .faction = .player,
    };
}

pub const Action = struct {
    pub const Kind = enum {
        spell,
        item,
    };
    pub const KindData = union(Kind) {
        spell: Spell,
        item: Item,
    };
    pub const Buffered = struct {
        action: KindData,
        params: Spell.Params,
        slot_idx: i32,
    };
};

pub const Input = struct {
    pub fn update(self: *Thing, room: *Room) Error!void {
        assert(self.spawn_state == .spawned);
        const plat = App.getPlat();
        const controller = &self.controller.player;
        const ui_slots = &room.ui_slots;
        const mouse_pos = plat.screenPosToCamPos(room.camera, plat.input_buffer.getCurrMousePos());

        // tick this here even though its on the player controller
        if (plat.input_buffer.mouseBtnIsJustPressed(.right)) {
            room.move_press_ui_timer.restart();
        }
        if (plat.input_buffer.mouseBtnIsDown(.right)) {
            controller.action_buffered = null;
            try self.findPath(room, mouse_pos);
            _ = room.move_press_ui_timer.tick(true);
            room.move_release_ui_timer.restart();
        } else {
            _ = room.move_press_ui_timer.tick(false);
            _ = room.move_release_ui_timer.tick(false);
        }

        if (ui_slots.getSelectedSlot()) |slot| {
            const cast_method = ui_slots.selected_method;
            const do_cast = switch (cast_method) {
                .left_click => !room.ui_clicked and plat.input_buffer.mouseBtnIsJustPressed(.left),
                .quick_press => true,
                .quick_release => !plat.input_buffer.keyIsDown(slot.key),
            };
            if (do_cast) {
                const _params: ?Spell.Params = blk: switch (slot.kind) {
                    inline else => |_action| {
                        assert(_action != null);
                        const action = _action.?;
                        break :blk action.getTargetParams(room, self, mouse_pos);
                    },
                };
                if (_params) |params| {
                    self.path.len = 0; // cancel the current path on cast, but you can buffer a new one
                    var baction = Action.Buffered{
                        .action = undefined,
                        .params = params,
                        .slot_idx = utl.as(i32, slot.idx),
                    };
                    switch (slot.kind) {
                        .item => |item| {
                            baction.action = .{ .item = item.? };
                            ui_slots.state = .{ .item = .{
                                .idx = slot.idx,
                                .select_kind = .buffered,
                            } };
                        },
                        .spell => |spell| {
                            baction.action = .{ .spell = spell.? };
                            ui_slots.state = .{ .spell = .{
                                .idx = slot.idx,
                                .select_kind = .buffered,
                            } };
                        },
                    }
                    controller.action_buffered = baction;
                } else if (cast_method == .quick_press or cast_method == .quick_release) {
                    ui_slots.state = .none;
                    controller.action_buffered = null;
                }
            }
        }
    }
};

pub const Controller = struct {
    const State = enum {
        none,
        cast,
        walk,
    };

    state: State = .none,
    action_casting: ?Action.Buffered = null,
    action_buffered: ?Action.Buffered = null,
    cast_counter: utl.TickCounter = .{},
    ticks_in_state: i64 = 0,

    pub fn update(self: *Thing, room: *Room) Error!void {
        assert(self.spawn_state == .spawned);
        const controller = &self.controller.player;

        if (controller.action_buffered) |buffered| {
            if (controller.action_casting == null) {
                switch (buffered.action) {
                    .item => |_| {
                        room.ui_slots.clearItemSlot(utl.as(usize, buffered.slot_idx));
                    },
                    .spell => |spell| {
                        room.ui_slots.clearSpellSlot(utl.as(usize, buffered.slot_idx));
                        room.discardSpell(spell);
                        controller.cast_counter = utl.TickCounter.init(spell.cast_time_ticks);
                    },
                }
                controller.action_casting = buffered;
                controller.action_buffered = null;
            }
        }

        {
            const p = self.followPathGetNextPoint(20);
            const input_dir = p.sub(self.pos).normalizedOrZero();

            const accel_dir: V2f = input_dir;

            controller.state = state: switch (controller.state) {
                .none => {
                    if (controller.action_casting != null) {
                        controller.ticks_in_state = 0;
                        continue :state .cast;
                    }
                    if (!input_dir.isZero()) {
                        controller.ticks_in_state = 0;
                        continue :state .walk;
                    }
                    self.updateVel(.{}, self.accel_params);
                    _ = self.animator.creature.play(.idle, .{ .loop = true });
                    break :state .none;
                },
                .walk => {
                    if (controller.action_casting != null) {
                        controller.ticks_in_state = 0;
                        continue :state .cast;
                    }
                    if (input_dir.isZero()) {
                        controller.ticks_in_state = 0;
                        continue :state .none;
                    }
                    self.updateVel(accel_dir, self.accel_params);
                    if (!self.vel.isZero()) {
                        self.dir = self.vel.normalized();
                    }
                    _ = self.animator.creature.play(.move, .{ .loop = true });
                    break :state .walk;
                },
                .cast => {
                    assert(controller.action_casting != null);
                    const s = controller.action_casting.?;
                    if (controller.ticks_in_state == 0) {
                        if (s.params.face_dir) |dir| {
                            self.dir = dir;
                        }
                    }
                    if (controller.cast_counter.tick(false)) {
                        switch (controller.action_casting.?.action) {
                            .item => |item| try item.use(self, room, s.params),
                            .spell => |spell| try spell.cast(self, room, s.params),
                        }
                        controller.action_casting = null;
                        controller.ticks_in_state = 0;
                        continue :state .none;
                    }
                    self.updateVel(.{}, self.accel_params);
                    _ = self.animator.creature.play(.cast, .{ .loop = true });
                    break :state .cast;
                },
            };
            controller.ticks_in_state += 1;
        }

        self.moveAndCollide(room);
    }
};
