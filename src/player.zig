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
const gameUI = @import("gameUI.zig");
const Player = @This();

pub const enum_name = "player";

pub fn protoype() Error!Thing {
    return Thing{
        .kind = .creature,
        .creature_kind = .player,
        .spawn_state = .instance,
        .coll_radius = 20,
        .vision_range = 300,
        .coll_mask = Thing.Collision.Mask.initMany(&.{ .creature, .tile }),
        .coll_layer = Thing.Collision.Mask.initMany(&.{.creature}),
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
        .hp = Thing.HP.init(50),
        .faction = .player,
    };
}

pub const InputController = struct {
    const State = enum {
        none,
        cast,
        walk,
    };
    const BufferedSpell = struct {
        spell: Spell,
        params: Spell.Params,
        slot_idx: i32,
    };

    state: State = .none,
    spell_buffered: ?BufferedSpell = null,
    spell_casting: ?BufferedSpell = null,
    cast_counter: utl.TickCounter = .{},
    ticks_in_state: i64 = 0,
    show_move_timer: utl.TickCounter = utl.TickCounter.initStopped(60),

    pub fn update(self: *Thing, room: *Room) Error!void {
        assert(self.spawn_state == .spawned);
        const plat = getPlat();
        const controller = &self.controller.player;

        _ = controller.show_move_timer.tick(false);
        if (plat.input_buffer.mouseBtnIsDown(.right)) {
            const mouse_pos = plat.screenPosToCamPos(room.camera, plat.input_buffer.getCurrMousePos());
            try self.findPath(room, mouse_pos);
            controller.show_move_timer.restart();
        }

        if (room.spell_slots.getSelectedSlot()) |slot| {
            const cast_method = room.spell_slots.selected_method;
            const do_cast = switch (cast_method) {
                .left_click => !room.ui_clicked and plat.input_buffer.mouseBtnIsJustPressed(.left),
                .quick_press => true,
                .quick_release => !plat.input_buffer.keyIsDown(gameUI.SpellSlots.idx_to_key[slot.idx]),
            };
            if (do_cast) {
                assert(slot.spell != null);
                const spell = slot.spell.?;
                const mouse_pos = plat.screenPosToCamPos(room.camera, plat.input_buffer.getCurrMousePos());
                if (spell.getTargetParams(room, self, mouse_pos)) |params| {
                    self.path.len = 0; // cancel the current path on cast, but you can buffer a new one
                    const bspell = BufferedSpell{
                        .spell = spell,
                        .params = params,
                        .slot_idx = utl.as(i32, slot.idx),
                    };
                    controller.spell_buffered = bspell;
                } else if (cast_method == .quick_press or cast_method == .quick_release) {
                    room.spell_slots.selected_idx = null;
                }
            }
        }
        if (controller.spell_buffered) |buffered| {
            if (controller.spell_casting == null) {
                room.spell_slots.clearSlot(utl.as(usize, buffered.slot_idx));
                room.discardSpell(buffered.spell);
                controller.spell_casting = buffered;
                controller.cast_counter = utl.TickCounter.init(buffered.spell.cast_time_ticks);
                controller.spell_buffered = null;
            }
        }

        {
            const p = self.followPathGetNextPoint(20);
            const input_dir = p.sub(self.pos).normalizedOrZero();

            const accel_dir: V2f = input_dir;
            const accel_params: Thing.AccelParams = .{
                .accel = 0.15,
                .friction = 0.09,
                .max_speed = 1.2,
            };

            controller.state = state: switch (controller.state) {
                .none => {
                    if (controller.spell_casting != null) {
                        controller.ticks_in_state = 0;
                        continue :state .cast;
                    }
                    if (!input_dir.isZero()) {
                        controller.ticks_in_state = 0;
                        continue :state .walk;
                    }
                    self.updateVel(.{}, accel_params);
                    _ = self.animator.creature.play(.idle, .{ .loop = true });
                    break :state .none;
                },
                .walk => {
                    if (controller.spell_casting != null) {
                        controller.ticks_in_state = 0;
                        continue :state .cast;
                    }
                    if (input_dir.isZero()) {
                        controller.ticks_in_state = 0;
                        continue :state .none;
                    }
                    self.updateVel(accel_dir, accel_params);
                    if (!self.vel.isZero()) {
                        self.dir = self.vel.normalized();
                    }
                    _ = self.animator.creature.play(.move, .{ .loop = true });
                    break :state .walk;
                },
                .cast => {
                    assert(controller.spell_casting != null);
                    const s = controller.spell_casting.?;
                    if (controller.ticks_in_state == 0) {
                        if (s.params.face_dir) |dir| {
                            self.dir = dir;
                        }
                    }
                    if (controller.cast_counter.tick(false)) {
                        try s.spell.cast(self, room, s.params);
                        controller.spell_casting = null;
                        controller.ticks_in_state = 0;
                        continue :state .none;
                    }
                    self.updateVel(.{}, accel_params);
                    _ = self.animator.creature.play(.cast, .{ .loop = true });
                    break :state .cast;
                },
            };
            controller.ticks_in_state += 1;
        }

        self.moveAndCollide(room);
    }
};
