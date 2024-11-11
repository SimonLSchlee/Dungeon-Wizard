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
    var ret = Thing.creatureProto(.player, .wizard, .player, 40, .medium, 15);
    ret.accel_params = .{
        .accel = 0.15,
        .friction = 0.09,
        .max_speed = 1.2,
    };
    ret.vision_range = 300;
    ret.player_input = Input{};
    ret.controller = .{ .player = .{} };

    return ret;
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
    move_press_ui_timer: utl.TickCounter = utl.TickCounter.initStopped(60),
    move_release_ui_timer: utl.TickCounter = utl.TickCounter.initStopped(60),

    pub fn update(self: *Thing, room: *Room) Error!void {
        assert(self.spawn_state == .spawned);
        const plat = App.getPlat();
        const input = &self.player_input.?;
        const controller = &self.controller.player;
        const ui_slots = &room.ui_slots;
        const mouse_pos = plat.getMousePosWorld(room.camera);

        ui_slots.updateSelected(room, self);
        if (!room.paused) {
            ui_slots.updateTimerAndDrawSpell(room);
        }
        if (self.mana) |*mana| {
            if (mana.curr == 0 or ui_slots.pressedDiscard()) {
                const max_extra_mana_cooldown_secs: f32 = 2;
                const per_mana_secs = max_extra_mana_cooldown_secs / utl.as(f32, mana.max);
                const num_secs: f32 = 1 + per_mana_secs * utl.as(f32, mana.curr);
                const num_ticks = core.secsToTicks(num_secs);
                for (ui_slots.getSlotsByKindConst(.spell)) |*slot| {
                    if (slot.kind) |k| {
                        const spell = k.spell;
                        room.discardSpell(spell);
                    }
                    ui_slots.clearSlotByKind(slot.idx, .spell);
                    ui_slots.setSlotCooldown(slot.idx, .spell, num_ticks);
                }
                ui_slots.discard_button.?.cooldown_timer = utl.TickCounter.init(num_ticks);
                mana.curr = mana.max;
            }
        }

        // clicking rmb cancels buffered action
        if (plat.input_buffer.mouseBtnIsJustPressed(.right)) {
            input.move_press_ui_timer.restart();
            ui_slots.select_state = null;
            controller.action_buffered = null;
        }
        // holding rmb sets path, only if an action isn't buffered
        // so movement can be 'canceled' with an action, even if still holding RMB
        if (controller.action_buffered == null and plat.input_buffer.mouseBtnIsDown(.right)) {
            try self.findPath(room, mouse_pos);
            _ = input.move_press_ui_timer.tick(true);
            input.move_release_ui_timer.restart();
        } else {
            _ = input.move_press_ui_timer.tick(false);
            _ = input.move_release_ui_timer.tick(false);
        }

        if (ui_slots.getSelectedSlot()) |slot| {
            assert(slot.kind != null);
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

    pub fn render(self: *const Thing, room: *const Room) Error!void {
        const plat = getPlat();
        const input = &self.player_input.?;
        const ui_slots = &room.ui_slots;
        const controller = &self.controller.player;

        if (ui_slots.getSelectedSlot()) |slot| {
            switch (slot.kind.?) {
                inline else => |k| try k.renderTargeting(room, self, null),
            }
        } else {
            const maybe_buffered: ?Action.Buffered = if (controller.action_buffered) |b| b else if (controller.action_casting) |a| a else null;
            if (maybe_buffered) |buffered| {
                switch (buffered.action) {
                    inline else => |k| try k.renderTargeting(room, self, buffered.params),
                }
            }
        }

        if (input.move_release_ui_timer.running and self.path.len > 0) {
            const move_pos = self.path.get(self.path.len - 1);
            const release_f = input.move_release_ui_timer.remapTo0_1();
            const bounce_f = input.move_press_ui_timer.remapTo0_1();
            const bounce_t = @sin(bounce_f * 3);
            const bounce_range = 10;
            const y_off = -bounce_range * bounce_t;
            var points: [3]V2f = .{
                v2f(0, 0),
                v2f(8, -10),
                v2f(-8, -10),
            };
            for (&points) |*p| {
                p.* = p.add(move_pos);
                p.y += y_off;
            }
            plat.circlef(move_pos, 10, .{ .outline_color = Colorf.green.fade(0.6 * (1 - release_f)), .fill_color = null });
            plat.trianglef(points, .{ .fill_color = Colorf.green.fade(1 - release_f) });
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
                const slot_idx = utl.as(usize, buffered.slot_idx);
                room.ui_slots.clearSlotByKind(slot_idx, std.meta.activeTag(buffered.action));
                switch (buffered.action) {
                    .spell => |spell| {
                        if (spell.mislay) {
                            room.mislaySpell(spell);
                        } else {
                            room.discardSpell(spell);
                        }
                        if (self.mana) |*mana| {
                            assert(mana.curr >= spell.mana_cost);
                            mana.curr -= spell.mana_cost;
                            if (spell.draw_immediate) {
                                room.ui_slots.setSlotCooldown(slot_idx, .spell, 0);
                            } else {
                                room.ui_slots.setSlotCooldown(slot_idx, .spell, null);
                            }
                        } else {
                            room.ui_slots.setSlotCooldown(slot_idx, .spell, spell.getSlotCooldownTicks());
                        }
                        controller.cast_counter = utl.TickCounter.init(spell.cast_ticks);
                    },
                    else => {},
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
