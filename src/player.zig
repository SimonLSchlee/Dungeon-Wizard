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
const Run = @import("Run.zig");
const Thing = @import("Thing.zig");
const Room = @import("Room.zig");
const Spell = @import("Spell.zig");
const Item = @import("Item.zig");
const gameUI = @import("gameUI.zig");
const sprites = @import("sprites.zig");
const Player = @This();

pub const enum_name = "player";

pub fn modePrototype(mode: Run.Mode) Thing {
    var base = App.get().data.creature_protos.get(.player);

    switch (mode) {
        .frank_4_slot => {},
        .mandy_3_mana => {
            base.mana = .{ .max = 3, .curr = 3 };
        },
        .crispin_picker => {
            base.mana = .{
                .max = 5,
                .curr = 3,
                .regen = .{
                    .timer = utl.TickCounter.init(core.secsToTicks(3)),
                    .max_threshold = 3,
                },
            };
        },
        .harriet_hoarder => {
            base.mana = .{
                .max = 10,
                .curr = 10,
            };
        },
    }
    base.player_input.?.mode = mode;

    return base;
}

pub const Action = struct {
    pub const Kind = enum {
        spell,
        item,
        discard,
    };
    pub const KindData = union(Kind) {
        spell: Spell,
        item: Item,
        discard: struct {}, // @hasField etc doesn't work with void, so empty struct
    };
    // identifies an Action (in context - e.g. a player action, a particular NPC's action, not a universal lookup (yet))
    pub const Id = struct {
        kind: Action.Kind,
        slot_idx: ?usize = null,
        pub fn eql(self: Id, other: Id) bool {
            if (self.kind != other.kind) return false;
            if (self.slot_idx != other.slot_idx) return false;
            return true;
        }
    };
    // an Action that isn't being done yet. Just point to it, and the params used to run it
    pub const Buffered = struct {
        action: KindData,
        params: ?Spell.Params = null,
    };
};

pub const Input = struct {
    move_press_ui_timer: utl.TickCounter = utl.TickCounter.initStopped(60),
    move_release_ui_timer: utl.TickCounter = utl.TickCounter.initStopped(60),
    mode: Run.Mode = undefined,

    pub fn updatePaused(input: *Input, run: *Run, self: *Thing) Error!void {
        const plat = App.getPlat();
        const room = &run.room;
        const ui_slots = &run.ui_slots;
        const mouse_pos = plat.getMousePosWorld(room.camera);

        if (self.mana) |*mana| {
            if (run.mode == .mandy_3_mana) {
                // automatically discard when out of mana
                if (mana.curr == 0 and ui_slots.getSelectedAction(.buffered) == null) {
                    ui_slots.selectAction(.{ .action = .{ .kind = .discard } }, .quick_release);
                }
            }
        }

        // clicking rmb cancels buffered action
        // !room.ui_clicked and
        if (plat.input_buffer.mouseBtnIsJustPressed(.right)) {
            input.move_press_ui_timer.restart();
            ui_slots.unselectAction();
        }
        // holding rmb sets path, only if an action isn't buffered
        // so movement can be 'canceled' with an action, even if still holding RMB
        // !room.ui_hovered and
        if (ui_slots.getSelectedAction(.buffered) == null and plat.input_buffer.mouseBtnIsDown(.right)) {
            try self.findPath(room, mouse_pos);
            _ = input.move_press_ui_timer.tick(true);
            input.move_release_ui_timer.restart();
        } else {
            _ = input.move_press_ui_timer.tick(true);
            _ = input.move_release_ui_timer.tick(false);
        }

        if (ui_slots.bufferSelectedAction(run, self)) {
            self.path.len = 0; // cancel the current path on cast, but you can buffer a new one
        }
        if (App.get().options.controls.getBindingByCommand(.stop_moving)) |stop_binding| {
            if (stop_binding.isJustPressed()) {
                self.path.len = 0;
            }
        }
    }

    pub fn updateUnpaused(_: *Input, run: *Run, self: *Thing) Error!void {
        assert(!run.room.paused);
        const room = &run.room;
        const controller = &self.controller.player;
        const ui_slots = &run.ui_slots;

        if (controller.action_casting == null) {
            controller.action_casting = ui_slots.tryUnbufferAction(run, self);
            if (controller.action_casting) |b| {
                switch (b.action) {
                    .spell => |spell| {
                        controller.cast_counter = utl.TickCounter.init(spell.cast_ticks);
                    },
                    else => {},
                }
            }
        }
        // TODO ?? I don't think this applies anymore
        // make sure selected action is still valid! It may be selected but not buffered, bypassing the canUse check in gameUI.Slots
        // ui_slots.cancelSelectedActionSlotIfInvalid(run, self);

        if (controller.action_casting) |action| {
            if (action.action == .discard) {
                // how long to wait if discarding...
                const discard_secs = if (self.mana) |*mana| blk: {
                    const max_extra_mana_cooldown_secs: f32 = 1.33;
                    const per_mana_secs = max_extra_mana_cooldown_secs / utl.as(f32, mana.max);
                    const num_secs: f32 = 0.66 + per_mana_secs * utl.as(f32, mana.curr);
                    break :blk num_secs;
                } else 3;
                const num_ticks = core.secsToTicks(discard_secs);
                for (ui_slots.spells.slice()) |*slot| {
                    if (slot.spell) |spell| {
                        room.discardSpell(spell);
                    }
                    slot.spell = null;
                    slot.ui_slot.cooldown_timer = utl.TickCounter.init(num_ticks);
                }
                ui_slots.discard_slot.?.cooldown_timer = utl.TickCounter.init(num_ticks);
                ui_slots.unselectAction();
            }
        }
    }

    pub fn update(input: *Input, run: *Run, self: *Thing) Error!void {
        const room = &run.room;
        try input.updatePaused(run, self);
        if (!room.paused) {
            try input.updateUnpaused(run, self);
            run.ui_slots.updateTimerAndDrawSpell(room);
        }
    }

    fn actionHasTargeting(action: Action.KindData) bool {
        switch (action) {
            inline else => |a| return std.meta.hasMethod(@TypeOf(a), "renderTargeting"),
        }
    }

    pub fn render(input: *const Input, run: *const Run, self: *const Thing) Error!void {
        const plat = getPlat();
        const controller = &self.controller.player;
        const room = &run.room;

        var params: ?Spell.Params = null;
        const action_with_targeting: ?Action.KindData = blk: {
            if (run.ui_slots.getSelectedAction(.selected)) |action| {
                if (actionHasTargeting(action)) {
                    break :blk action;
                }
            }
            if (run.ui_slots.getSelectedAction(.buffered)) |action| {
                if (actionHasTargeting(action)) {
                    params = run.ui_slots.action_selected.?.select_state.buffered;
                    break :blk action;
                }
            }
            if (controller.action_casting) |b| {
                if (actionHasTargeting(b.action)) {
                    params = b.params;
                    break :blk b.action;
                }
            }
            break :blk null;
        };
        if (action_with_targeting) |action| {
            switch (action) {
                inline else => |a| {
                    if (std.meta.hasMethod(@TypeOf(a), "renderTargeting")) {
                        try a.renderTargeting(room, self, params);
                    }
                },
            }
        }

        if (self.path.len > 0) { // and input.move_release_ui_timer.running
            const move_pos = self.path.get(self.path.len - 1);
            const release_f = 0; //input.move_release_ui_timer.remapTo0_1();
            const bounce_f = input.move_press_ui_timer.remapTo0_1();
            const bounce_t = @sin(bounce_f * 3);
            const bounce_range = 5;
            const y_off = -bounce_range * bounce_t;
            var points: [3]V2f = .{
                v2f(0, 0),
                v2f(4, -5),
                v2f(-4, -5),
            };
            for (&points) |*p| {
                p.* = p.add(move_pos);
                p.y += y_off;
            }
            plat.circlef(
                move_pos,
                if (self.hurtbox) |h| h.radius else 5,
                .{
                    .outline = .{ .color = Colorf.green.fade(0.6 * (1 - release_f)) },
                    .fill_color = null,
                },
            );
            plat.trianglef(points, .{ .fill_color = Colorf.green.fade(1 - release_f) });
        }
    }
};

pub const Controller = struct {
    const AnimRefs = struct {
        var idle = Data.Ref(Data.DirectionalSpriteAnim).init("wizard-idle");
        var move = Data.Ref(Data.DirectionalSpriteAnim).init("wizard-move");
        var cast = Data.Ref(Data.DirectionalSpriteAnim).init("wizard-cast");
        var swirlies = Data.Ref(Data.SpriteAnim).init("swirlies-loop");
    };
    const State = enum {
        none,
        action,
        walk,
    };

    state: State = .none,
    action_casting: ?Action.Buffered = null,
    cast_counter: utl.TickCounter = .{},
    cast_vfx: ?Thing.Id = null,
    ticks_in_state: i64 = 0,

    pub fn update(self: *Thing, room: *Room) Error!void {
        assert(self.spawn_state == .spawned);
        const controller = &self.controller.player;

        if (self.mana) |*mana| {
            if (mana.regen) |*mrgn| {
                if (mana.curr < mrgn.max_threshold) {
                    if (self.vel.isAlmostZero()) {
                        if (mrgn.timer.tick(true)) {
                            mana.curr += 1;
                        }
                        if (@mod(mrgn.timer.curr_tick, @divFloor(mrgn.timer.num_ticks, 4)) == 0) {
                            _ = AnimRefs.swirlies.get();
                            const proto = Thing.LoopVFXController.proto(
                                AnimRefs.swirlies,
                                0.66,
                                0.66,
                                false,
                                draw.Coloru.rgb(119, 87, 255).toColorf(),
                                false,
                            );
                            _ = room.queueSpawnThing(&proto, self.pos.add(v2f(0, 1))) catch {};
                        }
                    }
                }
            }
        }

        {
            const renderer = &self.renderer.sprite;
            const p = self.followPathGetNextPoint(5);
            const input_dir = p.sub(self.pos).normalizedOrZero();

            const accel_dir: V2f = input_dir;

            controller.state = state: switch (controller.state) {
                .none => {
                    if (controller.action_casting != null) {
                        controller.ticks_in_state = 0;
                        continue :state .action;
                    }
                    if (!input_dir.isZero()) {
                        controller.ticks_in_state = 0;
                        continue :state .walk;
                    }
                    self.move(.{});
                    _ = AnimRefs.idle.get();
                    _ = renderer.playDir(AnimRefs.idle, .{ .loop = true, .dir = self.dir });
                    break :state .none;
                },
                .walk => {
                    if (controller.action_casting != null) {
                        controller.ticks_in_state = 0;
                        continue :state .action;
                    }
                    if (input_dir.isZero()) {
                        controller.ticks_in_state = 0;
                        continue :state .none;
                    }
                    self.move(accel_dir);
                    if (!self.vel.isZero()) {
                        self.dir = self.vel.normalized();
                    }
                    _ = AnimRefs.move.get();
                    _ = renderer.playDir(AnimRefs.move, .{ .loop = true, .dir = self.dir });
                    break :state .walk;
                },
                .action => {
                    assert(controller.action_casting != null);
                    const plat = getPlat();
                    const Refs = struct {
                        var casting = Data.Ref(Data.Sound).init("casting");
                        var cast_end = Data.Ref(Data.Sound).init("cast-end");
                    };
                    const cast_loop_sound = Refs.casting.get().sound;
                    const cast_end_sound = Refs.cast_end.get().sound;
                    const cast_loop_volume = 0.2;
                    const cast_end_volume = 0.4;
                    const s = controller.action_casting.?;
                    if (controller.ticks_in_state == 0) {
                        if (s.params) |params| {
                            if (params.face_dir) |dir| {
                                self.dir = dir;
                            }
                        }
                        switch (controller.action_casting.?.action) {
                            .spell => {
                                const cast_proto = Thing.CastVFXController.castingProto(self);
                                if (try room.queueSpawnThing(&cast_proto, cast_proto.pos)) |id| {
                                    controller.cast_vfx = id;
                                }
                            },
                            else => {},
                        }
                    }
                    if (controller.cast_counter.tick(false)) {
                        switch (controller.action_casting.?.action) {
                            .item => |item| try item.use(self, room, s.params.?),
                            .spell => |spell| {
                                try spell.cast(self, room, s.params.?);
                            },
                            .discard => { // discard all cards (happens in Input though)
                                // mana mandy gets all her mana back
                                if (self.mana) |*mana| {
                                    if (room.init_params.mode == .mandy_3_mana) {
                                        mana.curr = mana.max;
                                    }
                                }
                            },
                        }
                        plat.stopSound(cast_loop_sound);
                        controller.action_casting = null;
                        controller.ticks_in_state = 0;
                        continue :state .none;
                    }
                    plat.loopSound(cast_loop_sound);
                    // TODO bit of a hacky wacky
                    const ticks_left = controller.cast_counter.num_ticks - controller.cast_counter.curr_tick;
                    if (ticks_left <= 30) {
                        const vol: f32 = utl.as(f32, ticks_left) / 30.0;
                        plat.setSoundVolume(cast_loop_sound, vol * cast_loop_volume);
                        if (controller.cast_vfx) |id| {
                            if (room.getThingById(id)) |cast| {
                                cast.controller.cast_vfx.state = .cast;
                            }
                        }
                        if (controller.cast_vfx != null) {
                            plat.setSoundVolume(cast_end_sound, cast_end_volume);
                            plat.playSound(cast_end_sound);
                        }
                        controller.cast_vfx = null;
                    } else {
                        plat.setSoundVolume(cast_loop_sound, cast_loop_volume);
                    }
                    self.move(.{});
                    _ = AnimRefs.cast.get();
                    _ = renderer.playDir(AnimRefs.cast, .{ .loop = true, .dir = self.dir });
                    break :state .action;
                },
            };

            controller.ticks_in_state += 1;
        }
    }
};
