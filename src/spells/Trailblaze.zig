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
const StatusEffect = @import("../StatusEffect.zig");

const Spell = @import("../Spell.zig");
const TargetKind = Spell.TargetKind;
const TargetingData = Spell.TargetingData;
const Params = Spell.Params;

pub const title = "Trailblaze";

pub const enum_name = "trailblaze";
pub const Controllers = [_]type{Projectile};

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .cast_time = .medium,
        .rarity = .interesting,
        .color = StatusEffect.proto_array.get(.promptitude).color,
        .targeting_data = .{
            .kind = .self,
        },
    },
);

pub fn fireProto() Thing {
    return Thing{
        .kind = .projectile,
        .spawn_state = .instance,
        .controller = .{ .spell = .{
            .params = .{ .target = .self },
            .spell = proto,
            .controller = .{ .trailblaze_projectile = .{} },
        } },
        .renderer = .{ .vfx = .{} },
        .animator = .{ .kind = .{ .vfx = .{
            .sheet_name = .trailblaze,
        } } },
        .hitbox = .{
            .mask = Thing.Faction.Mask.initFull(),
            .radius = 25,
            .sweep_to_rel_pos = v2f(0, -25),
            .deactivate_on_hit = false,
            .deactivate_on_update = true,
            .effect = .{
                .damage = 0,
                .can_be_blocked = false,
                .status_stacks = StatusEffect.StacksArray.initDefault(0, .{ .lit = 1 }),
            },
        },
    };
}

num_stacks: i32 = 5,

pub const Projectile = struct {
    pub const controller_enum_name = enum_name ++ "_projectile";

    loops_til_end: i32 = 2,
    state: enum {
        loop,
        end,
    } = .loop,

    pub fn update(self: *Thing, room: *Room) Error!void {
        const spell_controller = &self.controller.spell;
        const spell = spell_controller.spell;
        const trailblaze = spell.kind.trailblaze;
        _ = trailblaze;
        const projectile: *@This() = &spell_controller.controller.trailblaze_projectile;
        const animator = &self.animator.?;
        switch (projectile.state) {
            .loop => {
                const events = animator.play(.loop, .{ .loop = true });
                if (events.contains(.end)) {
                    projectile.loops_til_end -= 1;
                    if (projectile.loops_til_end <= 0) {
                        projectile.state = .end;
                    }
                } else if (events.contains(.hit)) {
                    self.hitbox.?.active = true;
                }
            },
            .end => {
                if (animator.play(.end, .{}).contains(.end)) {
                    self.deferFree(room);
                }
            },
        }
    }
};

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    assert(params.target == .self);
    _ = room;
    const trailblaze: @This() = self.kind.trailblaze;
    const status = caster.statuses.getPtr(.trailblaze);
    status.addStacks(trailblaze.num_stacks);
    status.timer.num_ticks = 20;
    status.prev_pos = caster.pos;
    caster.accel_params = .{
        .accel = 0.6,
        .friction = 0.3,
        .max_speed = 2.5,
    };
}

pub const description =
    \\Move faster. Leave fire behind when
    \\you move. The fire can hurt you too,
    \\so careful!
;

pub fn getDescription(self: *const Spell, buf: []u8) Error![]u8 {
    const trailblaze: @This() = self.kind.trailblaze;
    const fmt =
        \\Duration: {} secs
        \\
        \\{s}
        \\
    ;
    const dur_secs: i32 = trailblaze.num_stacks * utl.as(i32, @divFloor(StatusEffect.proto_array.get(.trailblaze).cooldown.num_ticks, core.fups_per_sec));
    return std.fmt.bufPrint(buf, fmt, .{ dur_secs, description });
}
