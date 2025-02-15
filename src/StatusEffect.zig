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
const projectiles = @import("projectiles.zig");

pub const CdType = enum {
    no_cd,
    remove_one_stack,
    remove_all_stacks,
};

const Proto = struct {
    enum_name: [:0]const u8,
    name: []const u8,
    cd: i64 = 1 * core.fups_per_sec,
    cd_type: CdType,
    color: Colorf,
    max_stacks: i32 = 9999,
    icon: icon_text.Icon,
    timer_ticks: i64 = 0,
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
        .cd_type = .remove_one_stack,
        .color = Colorf.rgb(0.3, 0.4, 0.9),
        .icon = .ice_ball,
    },
    .{
        .enum_name = "blackmailed",
        .name = "Blackmailed",
        .cd_type = .remove_one_stack,
        .color = Colorf.rgb(0.6, 0, 0),
        .icon = .ouchy_heart,
    },
    .{
        .enum_name = "mint",
        .name = "Mint",
        .cd_type = .remove_one_stack,
        .color = Colorf.rgb(1.0, 0.9, 0),
        .icon = .coin,
    },
    .{
        .enum_name = "promptitude",
        .name = "Promptitude",
        .cd_type = .remove_one_stack,
        .color = Colorf.rgb(0.95, 0.9, 1.0),
        .icon = .fast_forward,
    },
    .{
        .enum_name = "exposed",
        .name = "Exposed",
        .cd_type = .remove_one_stack,
        .color = Colorf.rgb(0.15, 0.1, 0.2),
        .icon = .magic_eye,
    },
    .{
        .enum_name = "stunned",
        .name = "Stunned",
        .cd_type = .remove_one_stack,
        .color = Colorf.rgb(0.9, 0.8, 0.7),
        .icon = .spiral_yellow,
    },
    .{
        .enum_name = "unseeable",
        .name = "Unseeable",
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
        .enum_name = "cold",
        .name = "Cold",
        .cd = 3 * core.fups_per_sec,
        .cd_type = .remove_one_stack,
        .color = Colorf.rgb(0.5, 0.8, 1),
        .icon = .ice_ball,
    },
    .{
        .enum_name = "trailblaze",
        .name = "Trailblaze",
        .cd_type = .remove_one_stack,
        .color = Colorf.rgb(1, 0.2, 0),
        .icon = .trailblaze,
        .timer_ticks = 20,
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
    .{
        .enum_name = "slimetrail",
        .name = "Slime Trail",
        .cd = 0,
        .cd_type = .no_cd,
        .color = Colorf.rgb(0.2, 0.7, 0.1),
        .icon = .slime,
        .timer_ticks = 45,
    },
    .{
        .enum_name = "slimed",
        .name = "Slimed",
        .cd_type = .remove_all_stacks,
        .color = Colorf.rgb(0.3, 0.9, 0.2),
        .icon = .slime,
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

pub const ProtoArray = std.EnumArray(Kind, Proto);
pub const proto_array = blk: {
    var ret: ProtoArray = undefined;
    for (protos) |p| {
        const kind: Kind = utl.stringToEnum(Kind, p.enum_name).?;
        ret.set(kind, p);
    }
    break :blk ret;
};

pub const StacksArray = std.EnumArray(Kind, i32);
pub const StatusArray = std.EnumArray(Kind, StatusEffect);

pub const status_array = blk: {
    var ret: StatusArray = undefined;
    for (protos) |p| {
        const kind: Kind = utl.stringToEnum(Kind, p.enum_name).?;
        ret.set(kind, .{
            .kind = kind,
            .cooldown = utl.TickCounter.init(p.cd),
            .timer = utl.TickCounter.init(p.timer_ticks),
        });
    }
    break :blk ret;
};

kind: Kind,
stacks: i32 = 0,
cooldown: utl.TickCounter = utl.TickCounter.init(core.fups_per_sec * 1),
// should put in a union maybe
timer: utl.TickCounter = utl.TickCounter.init(core.secsToTicks(1)),
prev_pos: ?V2f = .{},

pub fn setStacks(self: *StatusEffect, thing: *Thing, num: i32) void {
    const proto = proto_array.get(self.kind);
    const old_stacks = self.stacks;

    if (num > 0) {
        switch (self.kind) {
            .lit => {
                // thaw cold
                if (thing.statuses.get(.cold).stacks > 0) {
                    thing.statuses.getPtr(.cold).addStacks(thing, -num);
                    return;
                }
                // thaw frozen
                if (thing.statuses.get(.frozen).stacks > 0) {
                    thing.statuses.getPtr(.frozen).addStacks(thing, -num);
                    return;
                }
            },
            .cold => {
                // can't get any colder if frozen
                if (thing.statuses.get(.frozen).stacks > 0) {
                    return;
                }
                // completely put out lit
                thing.statuses.getPtr(.lit).setStacks(thing, 0);
                if (num >= 3) {
                    thing.statuses.getPtr(.frozen).addStacks(thing, 4);
                    self.stacks = 0;
                    return;
                }
            },
            .frozen => {
                // completely put out lit
                thing.statuses.getPtr(.lit).setStacks(thing, 0);
            },
            .slimed => {
                // can only have 1 slime stack at a time, and wait for it to expire
                // slimetrail is immune from slime
                if (thing.statuses.get(.slimed).stacks > 0 or thing.statuses.get(.slimetrail).stacks > 0) {
                    return;
                }
            },
            else => {},
        }
    }

    self.stacks = utl.clamp(i32, num, 0, proto.max_stacks);

    if (old_stacks == 0 and self.stacks > 0) { // stacks went from 0 to >0
        self.cooldown.restart();
        self.prev_pos = null;
    } else if (self.stacks == 0) { // finished the stacks
        switch (self.kind) {
            .blackmailed => {
                assert(thing.isCreature());
                const thing_proto = App.get().data.creature_protos.get(thing.creature_kind.?);
                thing.faction = thing_proto.faction;
            },
            else => {},
        }
    }
}

pub fn addStacks(self: *StatusEffect, thing: *Thing, num: i32) void {
    self.setStacks(thing, self.stacks + num);
}

pub fn getDurationSeconds(kind: Kind, stacks: i32) ?f32 {
    const proto = proto_array.get(kind);
    return switch (proto.cd_type) {
        .remove_one_stack => utl.as(f32, stacks) * utl.as(f32, @divFloor(proto.cd, core.fups_per_sec)),
        .remove_all_stacks => core.fups_to_secsf(proto.cd),
        .no_cd => null,
    };
}

pub fn update(status: *StatusEffect, thing: *Thing, room: *Room) Error!void {
    const proto = proto_array.get(status.kind);
    switch (status.kind) {
        .shield => if (thing.hp) |hp| {
            status.stacks = 0;
            for (hp.shields.constSlice()) |shield| {
                status.stacks += utl.as(i32, @ceil(shield.curr));
            }
        },
        else => {},
    }
    if (status.stacks == 0) {
        return;
    }
    if (status.cooldown.tick(true)) {
        switch (proto.cd_type) {
            .remove_one_stack => {
                status.addStacks(thing, -1);
            },
            .remove_all_stacks => {
                status.setStacks(thing, 0);
            },
            else => {},
        }
    }
    if (status.stacks == 0) {
        return;
    }

    // prev pos will only be null if status was just applied (from 0 stacks)
    // so can be used as a flag to indicate that
    if (status.prev_pos == null) {
        status.prev_pos = thing.pos;

        switch (status.kind) {
            .slimed => {
                const hit_effect = Thing.HitEffect{
                    .damage = 2,
                    .can_be_blocked = false,
                    .damage_kind = .acid,
                };
                if (thing.hurtbox) |*hurt| {
                    hurt.hit(thing, room, hit_effect, null);
                }
            },
            else => {},
        }
    }

    switch (status.kind) {
        // activate at start of each second
        .lit => if (@mod(status.cooldown.curr_tick, core.fups_per_sec) == core.fups_per_sec - 1) {
            assert(thing.statuses.get(.cold).stacks == 0);
            if (thing.hurtbox) |*hurtbox| {
                const lit_effect = Thing.HitEffect{
                    .damage = utl.as(f32, status.stacks),
                    .damage_kind = .fire,
                    .can_be_blocked = false,
                };
                hurtbox.hit(thing, room, lit_effect, null);
            }
        },
        .trailblaze => if (status.timer.tick(true)) {
            const vec = thing.pos.sub(status.prev_pos.?);
            const len = vec.length();
            const spawn_dist: f32 = 12.5;
            if (len > spawn_dist) {
                const thing_proto: Thing = projectiles.proto(.fire_blaze);
                const vec_n = vec.scale(1 / len);
                const num_to_spawn: usize = utl.as(usize, len / spawn_dist);
                for (0..num_to_spawn) |i| {
                    var pos = status.prev_pos.?.add(vec_n.scale(utl.as(f32, i) * spawn_dist));
                    const v_90 = vec_n.rot90CCW();
                    const rand_offset = v_90.scale(2).add(v_90.neg()).scale(room.rng.random().floatNorm(f32) * 3);
                    _ = try room.queueSpawnThing(&thing_proto, pos.add(rand_offset));
                }
            }
            status.prev_pos = thing.pos;
        },
        .slimetrail => if (status.timer.tick(true)) {
            const thing_proto: Thing = projectiles.proto(.slimepuddle);
            const vec = thing.pos.sub(status.prev_pos.?);
            var pos = status.prev_pos.?.add(vec.scale(0.66));
            const rand_dir = V2f.fromAngleRadians(room.rng.random().float(f32) * utl.tau);
            const rand_offset = rand_dir.scale(room.rng.random().float(f32) * 4);
            //const rand_offset = V2f{};
            _ = try room.queueSpawnThing(&thing_proto, pos.add(rand_offset));
            status.prev_pos = thing.pos;
        },
        else => {},
    }
}

pub fn getIcon(kind: StatusEffect.Kind) icon_text.Icon {
    return proto_array.get(kind).icon;
}

pub inline fn getColor(status: StatusEffect) Colorf {
    return proto_array.get(status.kind).color;
}

pub fn fmtDesc(buf: []u8, kind: StatusEffect.Kind) Error![]u8 {
    const proto = proto_array.get(kind);
    return switch (kind) {
        .protected => try std.fmt.bufPrint(buf, "The next enemy attack is blocked", .{}),
        .frozen => try std.fmt.bufPrint(buf, "Cannot move or act. Thawed by {}Fire", .{Thing.Damage.Kind.fire}),
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
                utl.as(i32, @floor(core.fups_to_secsf(proto.cd))),
                proto.max_stacks,
            },
        ),
        .cold => try std.fmt.bufPrint(
            buf,
            "Move speed reduced by half per stack.\nExtinguish {any}lit\nRemove 1 stack every {} seconds\nAt 3 stacks, {any}freeze for 4 seconds",
            .{
                icon_text.Icon.burn,
                utl.as(i32, @floor(core.fups_to_secsf(proto.cd))),
                icon_text.Icon.ice_ball,
            },
        ),
        .trailblaze => try std.fmt.bufPrint(buf, "Moves faster.\nLeaves behind a trail of fire", .{}),
        .quickdraw => try std.fmt.bufPrint(buf, "The next spell is drawn instantly", .{}),
        .shield => try std.fmt.bufPrint(buf, "Prevents damage for a duration", .{}),
        .slimetrail => try std.fmt.bufPrint(buf, "Leave a trail of slime. Immune to said slime", .{}),
        .slimed => try std.fmt.bufPrint(buf, "Slowed movement, take damage when this is applied. Expires in 1 sec", .{}),
        //else => try std.fmt.bufPrint(buf, "<Placeholder for status: {s}>", .{status.name}),
    };
}

pub fn fmtLong(buf: []u8, kind: StatusEffect.Kind, stacks: i32) Error![]u8 {
    const proto = proto_array.get(kind);
    return try icon_text.partsToUtf8(buf, &.{
        .{ .icon = proto.icon },
        .{ .text = proto.name },
        .{ .text = ": " },
        .{ .text = try _fmtStacksLong(kind, stacks) },
    });
}

pub fn fmtShort(buf: []u8, kind: StatusEffect.Kind, stacks: i32) Error![]u8 {
    const proto = proto_array.get(kind);
    return try icon_text.partsToUtf8(buf, &.{
        .{ .icon = proto.icon },
        .{ .text = try _fmtStacksShort(kind, stacks) },
    });
}

pub fn fmtName(buf: []u8, kind: StatusEffect.Kind) Error![]u8 {
    const proto = proto_array.get(kind);
    return try icon_text.partsToUtf8(buf, &.{
        .{ .icon = proto.icon },
        .{ .text = proto.name },
    });
}

pub fn getInfos(buf: []Tooltip.Info, kind: StatusEffect.Kind) Error![]Tooltip.Info {
    assert(buf.len >= 1);
    var arr = std.ArrayListUnmanaged(Tooltip.Info).initBuffer(buf);
    arr.appendAssumeCapacity(.{ .status = kind });

    switch (kind) {
        .cold => {
            assert(buf.len >= 3);
            arr.appendAssumeCapacity(.{ .status = .lit });
            arr.appendAssumeCapacity(.{ .status = .frozen });
        },
        else => {},
    }
    return arr.items;
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
