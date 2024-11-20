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

const creatures = @This();
const App = @import("App.zig");
const getPlat = App.getPlat;
const Thing = @import("Thing.zig");
const Room = @import("Room.zig");
const TileMap = @import("TileMap.zig");
const AI = @import("AI.zig");
const player = @import("player.zig");
const sprites = @import("sprites.zig");

pub const Kind = enum {
    player,
    dummy,
    troll,
    gobbow,
    sharpboi,
    impling,
    bat,
    acolyte,
    slime,
};

pub const proto_fns = blk: {
    var ret: std.EnumArray(Kind, fn () Thing) = undefined;
    for (@typeInfo(Kind).@"enum".fields) |f| {
        const kind: Kind = @enumFromInt(f.value);
        const fn_name = f.name ++ "Proto";
        ret.getPtr(kind).* = @field(creatures, fn_name);
    }
    break :blk ret;
};

pub fn playerProto() Thing {
    var ret = creatureProto(.player, .wizard, .player, null, 40, .medium, 15);
    ret.accel_params = .{
        .accel = 0.15,
        .friction = 0.09,
        .max_speed = 1.2,
    };
    ret.vision_range = 300;
    ret.player_input = player.Input{};
    ret.controller = .{ .player = .{} };

    return ret;
}

pub fn implingProto() Thing {
    var ret = creatureProto(.impling, .impling, .ally, .{ .aggro = .{} }, 25, .medium, 13);

    ret.accel_params = .{
        .max_speed = 1.0,
    };
    ret.controller.ai_actor.actions.appendAssumeCapacity(.{
        .kind = .{
            .melee_attack = .{
                .hitbox = .{
                    .mask = Thing.Faction.opposing_masks.get(.ally),
                    .radius = 20,
                    .rel_pos = V2f.right.scale(20),
                    .effect = .{ .damage = 6 },
                },
                .range = 30,
                .LOS_thiccness = 40,
            },
        },
        .cooldown = utl.TickCounter.initStopped(60),
    });
    return ret;
}

pub fn slimeProto() Thing {
    var c = creatureProto(.slime, .slime, .enemy, .{ .aggro = .{} }, 14, .big, 13);
    c.accel_params = .{
        .max_speed = 0.7,
    };
    c.controller.ai_actor.actions.appendAssumeCapacity(.{
        .kind = .{
            .melee_attack = .{
                .hitbox = .{
                    .radius = 20,
                    .rel_pos = V2f.right.scale(10),
                    .sweep_to_rel_pos = V2f.right.scale(40),
                    .effect = .{ .damage = 6 },
                },
                .range = 40,
            },
        },
        .cooldown = utl.TickCounter.initStopped(90),
    });
    c.enemy_difficulty = 0.75;
    return c;
}

pub fn batProto() Thing {
    var c = creatureProto(.bat, .bat, .enemy, .{ .aggro = .{} }, 5, .smol, 17);
    c.accel_params = .{
        .max_speed = 1.1,
    };
    c.controller.ai_actor.actions.appendAssumeCapacity(.{
        .kind = .{
            .melee_attack = .{
                .hitbox = .{
                    .radius = 20,
                    .rel_pos = V2f.right.scale(20),
                    .effect = .{ .damage = 3 },
                },
                .range = 25,
            },
        },
        .cooldown = utl.TickCounter.initStopped(70),
    });
    c.enemy_difficulty = 0.25;
    return c;
}

pub fn trollProto() Thing {
    var ret = creatureProto(.troll, .troll, .enemy, .{ .aggro = .{} }, 40, .big, 20);
    ret.accel_params = .{
        .max_speed = 0.7,
    };
    ret.controller.ai_actor.actions.appendAssumeCapacity(.{
        .kind = .{
            .melee_attack = .{
                .hitbox = .{
                    .radius = 20,
                    .rel_pos = V2f.right.scale(20),
                    .sweep_to_rel_pos = V2f.right.scale(50),
                    .effect = .{ .damage = 12 },
                },
                .range = 50,
                .LOS_thiccness = 30,
            },
        },
        .cooldown = utl.TickCounter.initStopped(90),
    });
    ret.enemy_difficulty = 2.5;

    return ret;
}

pub fn gobbowProto() Thing {
    var ret = creatureProto(.gobbow, .gobbow, .enemy, .{ .aggro = .{} }, 18, .medium, 12);
    ret.controller.ai_actor.actions.appendAssumeCapacity(.{
        .kind = .{ .projectile_attack = .{
            .projectile = .arrow,
            .range = 270,
        } },
        .cooldown = utl.TickCounter.initStopped(60),
    });
    ret.enemy_difficulty = 1.5;
    return ret;
}

pub fn sharpboiProto() Thing {
    var ret = creatureProto(.sharpboi, .sharpboi, .enemy, .{ .aggro = .{} }, 25, .medium, 18);

    ret.accel_params = .{
        .max_speed = 0.9,
    };
    ret.controller.ai_actor.actions.appendAssumeCapacity(.{
        .kind = .{
            .melee_attack = .{
                .lunge_accel = .{
                    .accel = 5,
                    .max_speed = 5,
                    .friction = 0,
                },
                .hitbox = .{
                    .mask = Thing.Faction.opposing_masks.get(.enemy),
                    .radius = 15,
                    .rel_pos = V2f.right.scale(40),
                    .effect = .{ .damage = 8 },
                    .deactivate_on_update = false,
                    .deactivate_on_hit = true,
                },
                .hit_to_side_force = 2.5,
                .range = 110,
                .LOS_thiccness = 30,
            },
        },
        .cooldown = utl.TickCounter.initStopped(140),
    });
    ret.enemy_difficulty = 2.5;
    return ret;
}

pub fn acolyteProto() Thing {
    var ret = creatureProto(.acolyte, .acolyte, .enemy, null, 25, .medium, 12);
    ret.accel_params = .{
        .accel = 0.3,
        .friction = 0.09,
        .max_speed = 1.25,
    };
    ret.controller = .{ .acolyte_enemy = .{} };
    ret.enemy_difficulty = 3;
    return ret;
}

pub fn dummyProto() Thing {
    var ret = creatureProto(.dummy, .dummy, .enemy, null, 25, .medium, 20);
    ret.enemy_difficulty = 0;
    return ret;
}

pub fn creatureProto(creature_kind: Kind, sprite_kind: sprites.CreatureAnim.Kind, faction: Thing.Faction, ai: ?AI.ActorController.KindData, hp: f32, size_cat: Thing.SizeCategory, select_height_px: f32) Thing {
    return Thing{
        .kind = .creature,
        .creature_kind = creature_kind,
        .spawn_state = .instance,
        .vision_range = 160,
        .coll_radius = Thing.SizeCategory.coll_radii.get(size_cat),
        .coll_mask = Thing.Collision.Mask.initMany(&.{ .creature, .tile }),
        .coll_layer = Thing.Collision.Mask.initMany(&.{.creature}),
        .controller = if (ai) |a| .{ .ai_actor = .{ .ai = a } } else .default,
        .renderer = .{ .creature = .{
            .draw_color = .yellow,
            .draw_radius = Thing.SizeCategory.draw_radii.get(size_cat),
        } },
        .animator = .{ .kind = .{ .creature = .{ .kind = sprite_kind } } },
        .hurtbox = .{
            .radius = Thing.SizeCategory.hurtbox_radii.get(size_cat),
        },
        .selectable = .{
            .height = select_height_px * core.pixel_art_scaling,
            .radius = Thing.SizeCategory.select_radii.get(size_cat),
        },
        .hp = Thing.HP.init(hp),
        .faction = faction,
    };
}
