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
const Run = @import("Run.zig");
const Thing = @import("Thing.zig");
const Room = @import("Room.zig");
const Spell = @import("Spell.zig");
const Item = @import("Item.zig");
const gameUI = @import("gameUI.zig");
const sprites = @import("sprites.zig");
const Player = @This();

pub const enum_name = "player";

pub fn basePrototype() Thing {
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
        .animator = .{ .kind = .{ .creature = .{ .kind = .wizard } } },
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

pub fn modePrototype(mode: Run.Mode) Thing {
    var base = basePrototype();
    switch (mode) {
        ._4_slot_frank => {},
        ._mana_mandy => {
            base.mana = .{ .max = 3, .curr = 3 };
        },
    }
    return base;
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
        const mouse_pos = plat.getMousePosWorld(room.camera);

        ui_slots.updateSelected(room, self);
        if (!room.paused) {
            ui_slots.updateTimerAndDrawSpell(room);
        }

        // tick this here even though its on the player controller
        if (plat.input_buffer.mouseBtnIsJustPressed(.right)) {
            room.move_press_ui_timer.restart();
        }
        if (plat.input_buffer.mouseBtnIsDown(.right)) {
            ui_slots.select_state = null;
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
                const _params: ?Spell.Params = blk: switch (slot.kind.?) {
                    inline else => |action| {
                        break :blk action.getTargetParams(room, self, mouse_pos);
                    },
                };
                if (_params) |params| {
                    self.path.len = 0; // cancel the current path on cast, but you can buffer a new one
                    controller.action_buffered = Action.Buffered{
                        .action = slot.kind.?,
                        .params = params,
                        .slot_idx = utl.as(i32, slot.idx),
                    };
                    ui_slots.select_state = .{
                        .slot_idx = slot.idx,
                        .select_kind = .buffered,
                        .slot_kind = slot.kind.?,
                    };
                } else if (cast_method == .quick_press or cast_method == .quick_release) {
                    ui_slots.select_state = null;
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
    cast_vfx: ?Thing.Id = null,
    ticks_in_state: i64 = 0,

    pub fn update(self: *Thing, room: *Room) Error!void {
        assert(self.spawn_state == .spawned);
        const controller = &self.controller.player;

        if (controller.action_buffered) |buffered| {
            if (controller.action_casting == null) {
                switch (buffered.action) {
                    .spell => |spell| {
                        if (spell.mislay) {
                            room.mislaySpell(spell);
                        } else {
                            room.discardSpell(spell);
                        }
                        controller.cast_counter = utl.TickCounter.init(spell.cast_ticks);
                    },
                    else => {},
                }
                room.ui_slots.clearSlotByKind(utl.as(usize, buffered.slot_idx), std.meta.activeTag(buffered.action));
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
                    _ = self.animator.?.play(.idle, .{ .loop = true });
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
                    _ = self.animator.?.play(.move, .{ .loop = true });
                    break :state .walk;
                },
                .cast => {
                    assert(controller.action_casting != null);

                    const cast_loop_sound = App.get().data.sounds.get(.spell_casting).?;
                    const cast_end_sound = App.get().data.sounds.get(.spell_cast).?;
                    const cast_loop_volume = 0.2;
                    const cast_end_volume = 0.4;
                    const s = controller.action_casting.?;
                    if (controller.ticks_in_state == 0) {
                        if (s.params.face_dir) |dir| {
                            self.dir = dir;
                        }
                        switch (controller.action_casting.?.action) {
                            .spell => {
                                const cast_proto = Thing.VFXController.castingProto(self);
                                if (try room.queueSpawnThing(&cast_proto, cast_proto.pos)) |id| {
                                    controller.cast_vfx = id;
                                }
                            },
                            else => {},
                        }
                    }
                    if (controller.cast_counter.tick(false)) {
                        switch (controller.action_casting.?.action) {
                            .item => |item| try item.use(self, room, s.params),
                            .spell => |spell| {
                                try spell.cast(self, room, s.params);
                            },
                        }
                        getPlat().stopSound(cast_loop_sound);
                        controller.action_casting = null;
                        controller.ticks_in_state = 0;
                        continue :state .none;
                    }
                    getPlat().loopSound(cast_loop_sound);
                    // TODO bit of a hacky wacky
                    const ticks_left = controller.cast_counter.num_ticks - controller.cast_counter.curr_tick;
                    if (ticks_left <= 30) {
                        const vol: f32 = utl.as(f32, ticks_left) / 30.0;
                        getPlat().setSoundVolume(cast_loop_sound, vol * cast_loop_volume);
                        if (controller.cast_vfx) |id| {
                            if (room.getThingById(id)) |cast| {
                                cast.controller.vfx.anim_to_play = .basic_cast;
                            }
                        }
                        if (controller.cast_vfx != null) {
                            getPlat().setSoundVolume(cast_end_sound, cast_end_volume);
                            getPlat().playSound(cast_end_sound);
                        }
                        controller.cast_vfx = null;
                    } else {
                        getPlat().setSoundVolume(cast_loop_sound, cast_loop_volume);
                    }
                    self.updateVel(.{}, self.accel_params);
                    _ = self.animator.?.play(.cast, .{ .loop = true });
                    break :state .cast;
                },
            };
            controller.ticks_in_state += 1;
        }

        self.moveAndCollide(room);
    }
};
