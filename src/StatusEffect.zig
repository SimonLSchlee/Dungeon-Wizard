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
stacks: i32,
cooldown: utl.TickCounter,
cd_type: CdType,
color: Colorf,
