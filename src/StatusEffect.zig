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
const icon_text = @import("icon_text.zig");
const Spell = @import("Spell.zig");
const ImmUI = @import("ImmUI.zig");
const Tooltip = @import("Tooltip.zig");

const Proto = struct {
    enum_name: [:0]const u8,
    name: []const u8,
    cd: i64,
    cd_type: CdType,
    color: Colorf,
    max_stacks: i32 = 9999,
    icon: icon_text.Icon,
};

const protos = [_]Proto{
    .{
        .enum_name = "protected",
        .name = "Protected",
        .cd = 10 * core.fups_per_sec,
        .cd_type = .remove_one_stack,
        .color = Colorf.rgb(0.7, 0.7, 0.4),
        .icon = .ouchy_skull, // TODO
    },
    .{
        .enum_name = "frozen",
        .name = "Frozen",
        .cd = 1 * core.fups_per_sec,
        .cd_type = .remove_one_stack,
        .color = Colorf.rgb(0.3, 0.4, 0.9),
        .icon = .ice_ball,
    },
    .{
        .enum_name = "blackmailed",
        .name = "Blackmailed",
        .cd = 1 * core.fups_per_sec,
        .cd_type = .remove_one_stack,
        .color = Colorf.rgb(0.6, 0, 0),
        .icon = .ouchy_heart,
    },
    .{
        .enum_name = "mint",
        .name = "Mint",
        .cd = 1 * core.fups_per_sec,
        .cd_type = .remove_one_stack,
        .color = Colorf.rgb(1.0, 0.9, 0),
        .icon = .coin,
    },
    .{
        .enum_name = "promptitude",
        .name = "Promptitude",
        .cd = 1 * core.fups_per_sec,
        .cd_type = .remove_one_stack,
        .color = Colorf.rgb(0.95, 0.9, 1.0),
        .icon = .fast_forward,
    },
    .{
        .enum_name = "exposed",
        .name = "Exposed",
        .cd = 1 * core.fups_per_sec,
        .cd_type = .remove_one_stack,
        .color = Colorf.rgb(0.15, 0.1, 0.2),
        .icon = .magic_eye,
    },
    .{
        .enum_name = "stunned",
        .name = "Stunned",
        .cd = 1 * core.fups_per_sec,
        .cd_type = .remove_one_stack,
        .color = Colorf.rgb(0.9, 0.8, 0.7),
        .icon = .spiral_yellow,
    },
    .{
        .enum_name = "unseeable",
        .name = "Unseeable",
        .cd = 1 * core.fups_per_sec,
        .cd_type = .remove_one_stack,
        .color = Colorf.rgb(0.26, 0.55, 0.7),
        .icon = .wizard_inverse,
    },
    .{
        .enum_name = "prickly",
        .name = "Prickly",
        .cd = 0,
        .cd_type = .no_cd,
        .color = Colorf.rgb(0.25, 0.55, 0.2),
        .icon = .spiky,
    },
    .{
        .enum_name = "lit",
        .name = "Lit",
        .cd = 4 * core.fups_per_sec,
        .cd_type = .remove_one_stack,
        .color = Colorf.rgb(1, 0.5, 0),
        .max_stacks = 3,
        .icon = .burn,
    },
    .{
        .enum_name = "moist",
        .name = "Moist",
        .cd = 1 * core.fups_per_sec,
        .cd_type = .remove_one_stack,
        .color = Colorf.rgb(0.5, 0.8, 1),
        .icon = .water,
    },
    .{
        .enum_name = "trailblaze",
        .name = "Trailblaze",
        .cd = 1 * core.fups_per_sec,
        .cd_type = .remove_one_stack,
        .color = Colorf.rgb(1, 0.2, 0),
        .icon = .trailblaze,
    },
    .{
        .enum_name = "quickdraw",
        .name = "Quickdraw",
        .cd = 0,
        .cd_type = .no_cd,
        .color = Colorf.rgb(0.7, 0.7, 0.5),
        .icon = .draw_card,
    },
    .{
        .enum_name = "shield",
        .name = "Shield",
        .cd = 0,
        .cd_type = .no_cd,
        .color = Colorf.rgb(0.8, 0.8, 0.7),
        .icon = .shield,
    },
};

pub const Kind = blk: {
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
            .name = p.name,
            .kind = kind,
            .icon = p.icon,
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

name: []const u8, // TODO remove
icon: icon_text.Icon,
kind: Kind,
stacks: i32 = 0,
cooldown: utl.TickCounter = utl.TickCounter.init(core.fups_per_sec * 1),
cd_type: CdType = .no_cd,
color: Colorf = .white,
// should put in a union maybe
timer: utl.TickCounter = utl.TickCounter.init(core.secsToTicks(1)),
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

pub fn getDurationSeconds(kind: Kind, stacks: i32) ?f32 {
    const status = proto_array.get(kind);
    return switch (status.cd_type) {
        .remove_one_stack => utl.as(f32, stacks) * utl.as(f32, @divFloor(status.cooldown.num_ticks, core.fups_per_sec)),
        .remove_all_stacks => core.fups_to_secsf(status.cooldown.num_ticks),
        .no_cd => null,
    };
}

pub fn update(status: *StatusEffect, thing: *Thing, room: *Room) Error!void {
    switch (status.kind) {
        .shield => if (thing.hp) |hp| {
            status.stacks = 0;
            for (hp.shields.constSlice()) |shield| {
                status.stacks += utl.as(i32, @ceil(shield.curr));
            }
        },
        else => {},
    }
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
                    const proto = App.get().data.creature_protos.get(thing.creature_kind.?);
                    thing.faction = proto.faction;
                },
                .trailblaze => {
                    assert(thing.isCreature());
                    const proto = App.get().data.creature_protos.get(thing.creature_kind.?);
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
            const spawn_dist: f32 = 12.5;
            if (len > spawn_dist) {
                const proto: Thing = Spell.GetKindType(.trailblaze).fireProto();
                const vec_n = vec.scale(1 / len);
                const num_to_spawn: usize = utl.as(usize, len / spawn_dist);
                for (0..num_to_spawn) |i| {
                    var pos = status.prev_pos.add(vec_n.scale(utl.as(f32, i) * spawn_dist));
                    const v_90 = vec_n.rot90CCW();
                    const rand_offset = v_90.scale(2).add(v_90.neg()).scale(room.rng.random().floatNorm(f32) * 3);
                    _ = try room.queueSpawnThing(&proto, pos.add(rand_offset));
                }
            }
            status.prev_pos = thing.pos;
        },
        else => {},
    }
}

pub fn getIcon(kind: StatusEffect.Kind) icon_text.Icon {
    return proto_array.get(kind).icon;
}

pub fn fmtDesc(buf: []u8, kind: StatusEffect.Kind) Error![]u8 {
    const status = proto_array.get(kind);
    return switch (kind) {
        .protected => try std.fmt.bufPrint(buf, "The next enemy attack is blocked", .{}),
        .frozen => try std.fmt.bufPrint(buf, "Cannot move or act", .{}),
        .blackmailed => try std.fmt.bufPrint(buf, "Fights for the blackmailer", .{}),
        .mint => try std.fmt.bufPrint(buf, "On death, drops 1 gold per stack", .{}),
        .promptitude => try std.fmt.bufPrint(buf, "Moves and acts at double speed", .{}),
        .exposed => try std.fmt.bufPrint(buf, "Takes 130% damage from all sources", .{}),
        .stunned => try std.fmt.bufPrint(buf, "Cannot move or act", .{}),
        .unseeable => try std.fmt.bufPrint(buf, "Ignored by enemies", .{}),
        .prickly => try std.fmt.bufPrint(buf, "Melee attackers take 1 damage per stack", .{}),
        .lit => try std.fmt.bufPrint(
            buf,
            "Take 1 damage per second per stack.\nRemove 1 stack every {} seconds\nMax {} stacks",
            .{
                utl.as(i32, @floor(core.fups_to_secsf(status.cooldown.num_ticks))),
                status.max_stacks,
            },
        ),
        .moist => try std.fmt.bufPrint(
            buf,
            "Remove all stacks of {any}lit.\nImmune to {any}lit until duration\nexpires",
            .{
                icon_text.Icon.burn,
                icon_text.Icon.burn,
            },
        ),
        .trailblaze => try std.fmt.bufPrint(buf, "Moves faster.\nLeaves behind a trail of fire", .{}),
        .quickdraw => try std.fmt.bufPrint(buf, "The next spell is drawn instantly", .{}),
        .shield => try std.fmt.bufPrint(buf, "Prevents damage for a duration", .{}),
        //else => try std.fmt.bufPrint(buf, "<Placeholder for status: {s}>", .{status.name}),
    };
}

pub fn fmtLong(buf: []u8, kind: StatusEffect.Kind, stacks: i32) Error![]u8 {
    const status = proto_array.get(kind);
    return try icon_text.partsToUtf8(buf, &.{
        .{ .icon = status.icon },
        .{ .text = status.name },
        .{ .text = ": " },
        .{ .text = try _fmtStacksLong(kind, stacks) },
    });
}

pub fn fmtShort(buf: []u8, kind: StatusEffect.Kind, stacks: i32) Error![]u8 {
    const status = proto_array.get(kind);
    return try icon_text.partsToUtf8(buf, &.{
        .{ .icon = status.icon },
        .{ .text = try _fmtStacksShort(kind, stacks) },
    });
}

pub fn fmtName(buf: []u8, kind: StatusEffect.Kind) Error![]u8 {
    const status = proto_array.get(kind);
    return try icon_text.partsToUtf8(buf, &.{
        .{ .icon = status.icon },
        .{ .text = status.name },
    });
}

pub fn getInfos(buf: []Tooltip.Info, kind: StatusEffect.Kind) Error![]Tooltip.Info {
    assert(buf.len >= 1);
    var idx: usize = 0;
    buf[idx] = .{ .status = kind };
    idx += 1;
    switch (kind) {
        .moist => {
            assert(buf.len >= 2);
            buf[idx] = .{ .status = .lit };
            idx += 1;
        },
        else => {},
    }
    return buf[0..idx];
}

inline fn sEnding(num: i32) []const u8 {
    if (num > 0) {
        return "s";
    }
    return "";
}

fn _fmtStacksLong(kind: StatusEffect.Kind, stacks: i32) Error![]u8 {
    const dur_secs = if (StatusEffect.getDurationSeconds(kind, stacks)) |secs_f| utl.as(i32, @floor(secs_f)) else null;
    return switch (kind) {
        .lit => try utl.bufPrintLocal("{} stack{s}", .{ stacks, sEnding(stacks) }),
        else => if (dur_secs) |secs|
            try utl.bufPrintLocal("{} sec{s}", .{ secs, sEnding(secs) })
        else
            try utl.bufPrintLocal("{} stack{s}", .{ stacks, sEnding(stacks) }),
    };
}

fn _fmtStacksShort(kind: StatusEffect.Kind, stacks: i32) Error![]u8 {
    const dur_secs = if (StatusEffect.getDurationSeconds(kind, stacks)) |secs_f| utl.as(i32, @floor(secs_f)) else null;
    return switch (kind) {
        .lit => try utl.bufPrintLocal("{}", .{stacks}),
        else => if (dur_secs) |secs|
            try utl.bufPrintLocal("{}sec{s}", .{ secs, sEnding(secs) })
        else
            try utl.bufPrintLocal("{}", .{stacks}),
    };
}
