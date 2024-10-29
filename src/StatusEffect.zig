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

const StatusEffect = @This();
const App = @import("App.zig");
const getPlat = App.getPlat;
const Room = @import("Room.zig");
const TileMap = @import("TileMap.zig");
const data = @import("data.zig");
const Thing = @import("Thing.zig");
const sprites = @import("sprites.zig");

const player = @import("player.zig");
const enemies = @import("enemies.zig");
const Spell = @import("Spell.zig");

const ComptimeProto = struct {
    enum_name: [:0]const u8,
    cd: i64,
    cd_type: CdType,
    color: Colorf,
    max_stacks: i32 = 9999,
};

const protos = [_]ComptimeProto{
    .{
        .enum_name = "protected",
        .cd = 5 * core.fups_per_sec,
        .cd_type = .remove_one_stack,
        .color = Colorf.rgb(0.7, 0.7, 0.4),
    },
    .{
        .enum_name = "frozen",
        .cd = 1 * core.fups_per_sec,
        .cd_type = .remove_one_stack,
        .color = Colorf.rgb(0.3, 0.4, 0.9),
    },
    .{
        .enum_name = "blackmailed",
        .cd = 1 * core.fups_per_sec,
        .cd_type = .remove_one_stack,
        .color = Colorf.rgb(0.6, 0, 0),
    },
    .{
        .enum_name = "mint",
        .cd = 1 * core.fups_per_sec,
        .cd_type = .remove_one_stack,
        .color = Colorf.rgb(1.0, 0.9, 0),
    },
    .{
        .enum_name = "promptitude",
        .cd = 1 * core.fups_per_sec,
        .cd_type = .remove_one_stack,
        .color = Colorf.rgb(0.95, 0.9, 1.0),
    },
    .{
        .enum_name = "exposed",
        .cd = 1 * core.fups_per_sec,
        .cd_type = .remove_one_stack,
        .color = Colorf.rgb(0.15, 0.1, 0.2),
    },
    .{
        .enum_name = "stunned",
        .cd = 1 * core.fups_per_sec,
        .cd_type = .remove_one_stack,
        .color = Colorf.rgb(0.9, 0.8, 0.7),
    },
    .{
        .enum_name = "unseeable",
        .cd = 1 * core.fups_per_sec,
        .cd_type = .remove_one_stack,
        .color = Colorf.rgb(0.26, 0.55, 0.7),
    },
    .{
        .enum_name = "prickly",
        .cd = 0,
        .cd_type = .no_cd,
        .color = Colorf.rgb(0.25, 0.55, 0.2),
    },
    .{
        .enum_name = "lit",
        .cd = 4 * core.fups_per_sec,
        .cd_type = .remove_one_stack,
        .color = Colorf.rgb(1, 0.5, 0),
        .max_stacks = 4,
    },
    .{
        .enum_name = "moist",
        .cd = 1 * core.fups_per_sec,
        .cd_type = .remove_one_stack,
        .color = Colorf.rgb(0.5, 0.8, 1),
    },
    .{
        .enum_name = "trailblaze",
        .cd = 1 * core.fups_per_sec,
        .cd_type = .remove_one_stack,
        .color = Colorf.rgb(1, 0.2, 0),
    },
};

const Kind = blk: {
    var fields: [protos.len]std.builtin.Type.EnumField = undefined;
    for (protos, 0..) |p, i| {
        fields[i] = .{
            .name = p.enum_name,
            .value = i,
        };
    }
    break :blk @Type(.{
        .@"enum" = .{
            .tag_type = std.math.IntFittingRange(0, fields.len),
            .fields = &fields,
            .decls = &.{},
            .is_exhaustive = true,
        },
    });
};

pub const StacksArray = std.EnumArray(Kind, i32);
pub const StatusArray = std.EnumArray(Kind, StatusEffect);
pub const proto_array = blk: {
    var ret: StatusArray = undefined;
    for (protos, 0..) |p, i| {
        const kind: Kind = @enumFromInt(i);
        ret.set(kind, .{
            .kind = kind,
            .stacks = 0,
            .cooldown = utl.TickCounter.init(p.cd),
            .cd_type = p.cd_type,
            .color = p.color,
            .max_stacks = p.max_stacks,
        });
    }
    break :blk ret;
};

pub const CdType = enum {
    no_cd,
    remove_one_stack,
    remove_all_stacks,
};

kind: Kind,
stacks: i32 = 0,
cooldown: utl.TickCounter = utl.TickCounter.init(core.fups_per_sec * 1),
cd_type: CdType = .no_cd,
color: Colorf = .white,
// should put in a union maybe
timer: utl.TickCounter = .{},
prev_pos: V2f = .{},
max_stacks: i32 = 9999,

pub fn setStacks(self: *StatusEffect, thing: *Thing, num: i32) void {
    switch (self.kind) {
        .lit => {
            if (thing.statuses.get(.moist).stacks > 0) {
                return;
            }
        },
        .moist => {
            thing.statuses.getPtr(.lit).stacks = 0;
        },
        else => {},
    }
    if (self.stacks == 0) {
        self.cooldown.restart();
    }
    self.stacks = utl.clamp(i32, num, 0, self.max_stacks);
}

pub fn addStacks(self: *StatusEffect, thing: *Thing, num: i32) void {
    self.setStacks(thing, self.stacks + num);
}

pub fn update(status: *StatusEffect, thing: *Thing, room: *Room) Error!void {
    if (status.cd_type == .no_cd or status.stacks == 0) {
        return;
    }
    if (status.cooldown.tick(true)) {
        switch (status.cd_type) {
            .remove_one_stack => {
                status.stacks -= 1;
            },
            .remove_all_stacks => {
                status.stacks = 0;
            },
            else => unreachable,
        }
        if (status.stacks == 0) {
            switch (status.kind) {
                .blackmailed => {
                    assert(thing.isCreature());
                    const proto = App.get().data.creatures.get(thing.creature_kind.?);
                    thing.faction = proto.faction;
                },
                .trailblaze => {
                    assert(thing.isCreature());
                    const proto = App.get().data.creatures.get(thing.creature_kind.?);
                    thing.accel_params = proto.accel_params;
                },
                else => {},
            }
        }
    }
    switch (status.kind) {
        // activate at start of each second
        .lit => if (@mod(status.cooldown.curr_tick, core.fups_per_sec) == core.fups_per_sec - 1) {
            assert(thing.statuses.get(.moist).stacks == 0);
            if (thing.hurtbox) |*hurtbox| {
                const lit_effect = Thing.HitEffect{
                    .damage = utl.as(f32, status.stacks),
                    .can_be_blocked = false,
                };
                hurtbox.hit(thing, room, lit_effect, null);
            }
        },
        .trailblaze => if (status.timer.tick(true)) {
            const vec = thing.pos.sub(status.prev_pos);
            const len = vec.length();
            const spawn_dist: f32 = 25;
            if (len > spawn_dist) {
                const proto: Thing = Spell.GetKindType(.trailblaze).fireProto();
                const vec_n = vec.scale(1 / len);
                const num_to_spawn: usize = utl.as(usize, len / spawn_dist);
                for (0..num_to_spawn) |i| {
                    var pos = status.prev_pos.add(vec_n.scale(utl.as(f32, i) * spawn_dist));
                    const v_90 = vec_n.rot90CCW();
                    const rand_offset = v_90.scale(2).add(v_90.neg()).scale(room.rng.random().floatNorm(f32) * 6);
                    _ = try room.queueSpawnThing(&proto, pos.add(rand_offset));
                }
            }
            status.prev_pos = thing.pos;
        },
        else => {},
    }
}
