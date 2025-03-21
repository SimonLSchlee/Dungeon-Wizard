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
const Data = @import("Data.zig");
const Thing = @import("Thing.zig");
const Room = @import("Room.zig");
const TileMap = @import("TileMap.zig");
const AI = @import("AI.zig");
const player = @import("player.zig");
const sprites = @import("sprites.zig");
const icon_text = @import("icon_text.zig");
const Spell = @import("Spell.zig");
const Action = @import("Action.zig");

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
    gobbomber,
    shopspider,
    djinn,
    djinn_smoke,
    snowfren,
    @"fairy-blue",
    @"fairy-green",
    @"fairy-red",
    @"fairy-gold",

    pub fn getIcon(self: Kind) icon_text.Icon {
        if (self == .player) {
            return .wizard;
        }
        const enum_name = utl.enumToString(Thing.CreatureKind, self);
        if (std.mem.startsWith(u8, enum_name, "fairy")) {
            return .fairy;
        }
        if (std.meta.stringToEnum(icon_text.Icon, enum_name)) |icon| {
            return icon;
        }
        return .skull;
    }
    pub fn getName(self: Kind) []const u8 {
        return switch (self) {
            .@"fairy-green" => "slime fairy",
            .@"fairy-blue" => "sky fairy",
            .@"fairy-red" => "heart fairy",
            .@"fairy-gold" => "golden fairy",
            else => utl.enumToString(Thing.CreatureKind, self),
        };
    }
    pub fn fmtName(self: Kind, buf: []u8) Error![]const u8 {
        return std.fmt.bufPrint(buf, "{s}", .{self.getName()});
    }
    pub fn fmtDesc(self: Kind, buf: []u8) Error![]const u8 {
        const proto = App.get().data.creature_protos.get(self);
        const hp_fmt_opts: usize = @bitCast(Thing.HP.FmtOpts{ .max_only = true });
        const hp_buf = if (proto.hp) |hp| try std.fmt.bufPrint(buf, "{any:." ++ std.fmt.comptimePrint("{}", .{hp_fmt_opts}) ++ "}", .{hp}) else "";
        if (proto.controller != .ai_actor) return hp_buf;
        const ai_actor = proto.controller.ai_actor;
        var curr_idx: usize = hp_buf.len;
        if (false) {
            var action_bufs = std.EnumArray(Action.Slot, []u8).initFill("");
            var action_it = ai_actor.actions.iterator();
            while (action_it.next()) |slot| {
                if (slot.value == null) continue;
                if (curr_idx >= buf.len) break;
                buf[curr_idx] = '\n';
                curr_idx += 1;
                const action_buf = try std.fmt.bufPrint(buf[curr_idx..], "{any}", .{slot.value.?});
                curr_idx += action_buf.len;
                action_bufs.getPtr(slot.key).* = action_buf;
            }
        }
        return buf[0..curr_idx];
    }
    pub fn format(self: Kind, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) Error!void {
        _ = fmt;
        _ = options;
        const enum_name = self.getName();
        const first_letter = [1]u8{std.ascii.toUpper(enum_name[0])};
        writer.print("{any}{s}{s}", .{
            self.getIcon(),
            &first_letter,
            enum_name[1..],
        }) catch return Error.EncodingFail;
    }
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
    var ret = creatureProto(.player, .wizard, .player, null, 40, .medium, 18);
    ret.hurtbox.?.radius *= 0.85;
    ret.accel_params = .{
        .accel = 0.0023 * TileMap.tile_sz_f,
        .friction = 0.0014 * TileMap.tile_sz_f,
        .max_speed = 0.020 * TileMap.tile_sz_f,
    };
    ret.vision_range = TileMap.tile_sz_f * 4;
    ret.player_input = player.Input{};
    ret.controller = .{ .player = .{} };
    ret.dir = V2f.left;

    return ret;
}

pub fn djinnProto() Thing {
    var ret = creatureProto(.djinn, .creature, .enemy, .{ .djinn = .{} }, 80, .big, 26);
    ret.accel_params = .{
        .accel = 0.0047 * TileMap.tile_sz_f,
        .max_speed = 0.0198 * TileMap.tile_sz_f,
    };
    ret.controller.ai_actor.flee_range = 90;
    ret.controller.ai_actor.actions.getPtr(.spell_cast_thing_attack_1).* = (.{
        .kind = .{ .spell_cast = .{
            .spell = Spell.getProto(.crescent_throw),
        } },
        .cooldown = utl.TickCounter.initStopped(5 * core.fups_per_sec),
    });
    ret.controller.ai_actor.actions.getPtr(.spell_cast_self_buff_1).* = (.{
        .kind = .{ .spell_cast = .{
            .spell = Spell.getProto(.protect_self),
        } },
        .cooldown = utl.TickCounter.initStopped(12 * core.fups_per_sec),
    });
    ret.controller.ai_actor.actions.getPtr(.spell_cast_teleport_self).* = (.{
        .kind = .{ .spell_cast = .{
            .spell = Spell.getProto(.teleport_self),
        } },
        .cooldown = utl.TickCounter.initStopped(7 * core.fups_per_sec),
    });

    ret.enemy_difficulty = 8;
    ret.is_boss = true;
    ret.on_die = .djinn_boss;
    return ret;
}

pub fn djinn_smokeProto() Thing {
    var ret = creatureProto(.djinn_smoke, .creature, .enemy, .{ .djinn_smoke = .{} }, 80, .big, 26);
    ret.accel_params = .{
        .accel = 0.0047 * TileMap.tile_sz_f,
        .max_speed = 0.0198 * TileMap.tile_sz_f,
    };
    ret.pathing_layer = .flying;
    ret.controller.ai_actor.flee_range = 70;
    ret.controller.ai_actor.actions.getPtr(.spell_cast_summon_1).* = (.{
        .kind = .{ .spell_cast = .{
            .spell = Spell.getProto(.summon_bat),
        } },
        .cooldown = utl.TickCounter.initStopped(5 * core.fups_per_sec),
    });
    ret.controller.ai_actor.actions.getPtr(.melee_attack_1).* = (.{
        .kind = .{
            .melee_attack = .{
                .lunge_accel = .{
                    .accel = 3,
                    .max_speed = 3.0,
                    .friction = 0.01,
                },
                .hitbox = .{
                    .mask = Thing.Faction.opposing_masks.get(.enemy),
                    .radius = 9,
                    .rel_pos = V2f.right.scale(20),
                    .effect = .{ .damage = 9 },
                    .deactivate_on_update = false,
                    .deactivate_on_hit = true,
                },
                .hit_to_side_force = 2,
                .range = 90,
                .LOS_thiccness = ret.coll_radius * 0.5,
            },
        },
        .cooldown = utl.TickCounter.initStopped(140),
    });
    ret.enemy_difficulty = 8;
    ret.is_boss = true;
    return ret;
}

pub fn shopspiderProto() Thing {
    var ret = creatureProto(.shopspider, .creature, .ally, .idle, 60, .big, 24);
    ret.selectable.?.radius = 24;
    ret.coll_mass = std.math.inf(f32);
    ret.hp = null;
    ret.coll_mask = Thing.Collision.Mask.initEmpty();
    ret.dir = V2f.left;
    ret.rmb_interactable = .{
        .kind = .shop,
        .interact_radius = 50,
    };

    return ret;
}

pub fn implingProto() Thing {
    var ret = creatureProto(.impling, .impling, .ally, .{ .aggro = .{} }, 15, .medium, 13);
    ret.accel_params = .{
        .max_speed = 0.0166 * TileMap.tile_sz_f,
    };
    ret.controller.ai_actor.actions.getPtr(.melee_attack_1).* = (.{
        .kind = .{
            .melee_attack = .{
                .hitbox = .{
                    .mask = Thing.Faction.opposing_masks.get(.ally),
                    .radius = 10,
                    .rel_pos = V2f.right.scale(10),
                    .effect = .{ .damage = 5 },
                },
                .range = 15,
            },
        },
        .cooldown = utl.TickCounter.initStopped(60),
    });
    return ret;
}

pub fn snowfrenProto() Thing {
    var ret = creatureProto(.snowfren, .snowfren, .ally, .{ .aggro = .{} }, 12, .smol, 11);
    ret.statuses.getPtr(.snowy).setStacks(&ret, 1);
    ret.accel_params = .{
        .max_speed = 0.15,
    };
    ret.controller.ai_actor.actions.getPtr(.projectile_attack_1).* = (.{
        .kind = .{
            .projectile_attack = .{
                .projectile = .snowball,
                .range = 85,
                .LOS_thiccness = 3.5,
            },
        },
        .cooldown = utl.TickCounter.initStopped(core.secsToTicks(1)),
    });
    return ret;
}

pub fn fairyBaseProto() Thing {
    var ret = creatureProto(.@"fairy-blue", .@"fairy-blue", .ally, .{ .fairy = .{} }, 2, .smol, 17);
    ret.pathing_layer = .flying;
    ret.accel_params = .{
        .max_speed = 0.03 * TileMap.tile_sz_f,
    };
    ret.renderer.sprite.rel_pos.y = -10;
    ret.statuses.getPtr(.protected).addStacks(&ret, -1);
    return ret;
}

pub fn @"fairy-blueProto"() Thing {
    var ret = fairyBaseProto();
    ret.creature_kind = .@"fairy-blue";
    ret.controller.ai_actor.actions.getPtr(.spell_cast_thing_buff_1).* = (.{
        .kind = .{
            .spell_cast = .{
                .spell = Spell.getProto(.fairy_air),
            },
        },
        .cooldown = utl.TickCounter.initStopped(core.secsToTicks(5)),
    });
    return ret;
}

pub fn @"fairy-greenProto"() Thing {
    var ret = fairyBaseProto();
    ret.creature_kind = .@"fairy-green";
    ret.controller.ai_actor.actions.getPtr(.spell_cast_thing_debuff_1).* = (.{
        .kind = .{
            .spell_cast = .{
                .spell = Spell.getProto(.fairy_slime),
            },
        },
        .cooldown = utl.TickCounter.initStopped(core.secsToTicks(5)),
    });
    return ret;
}

pub fn @"fairy-redProto"() Thing {
    var ret = fairyBaseProto();
    ret.creature_kind = .@"fairy-red";
    ret.controller.ai_actor.actions.getPtr(.spell_cast_thing_buff_1).* = (.{
        .kind = .{
            .spell_cast = .{
                .spell = Spell.getProto(.fairy_heart),
            },
        },
        .cooldown = utl.TickCounter.initStopped(core.secsToTicks(7)),
    });
    return ret;
}

pub fn @"fairy-goldProto"() Thing {
    var ret = fairyBaseProto();
    ret.hp = Thing.HP.init(6);
    ret.creature_kind = .@"fairy-gold";
    ret.statuses.getPtr(.protected).addStacks(&ret, -1);
    ret.statuses.getPtr(.protected).addStacks(&ret, -1);
    ret.controller.ai_actor.actions.getPtr(.spell_cast_thing_debuff_1).* = (.{
        .kind = .{
            .spell_cast = .{
                .spell = Spell.getProto(.fairy_gold_debuff),
            },
        },
        .cooldown = utl.TickCounter.initStopped(core.secsToTicks(5)),
    });
    ret.controller.ai_actor.actions.getPtr(.spell_cast_thing_buff_1).* = (.{
        .kind = .{
            .spell_cast = .{
                .spell = Spell.getProto(.fairy_gold_buff),
            },
        },
        .cooldown = utl.TickCounter.initStopped(core.secsToTicks(5)),
    });
    return ret;
}

pub fn slimeProto() Thing {
    var c = creatureProto(.slime, .slime, .enemy, .{ .aggro = .{} }, 12, .big, 13);
    c.accel_params = .{
        .max_speed = 0.0119 * TileMap.tile_sz_f,
    };
    const status = c.statuses.getPtr(.slimetrail);
    status.addStacks(&c, 1);
    c.controller.ai_actor.actions.getPtr(.melee_attack_1).* = (.{
        .kind = .{
            .melee_attack = .{
                .hitbox = .{
                    .radius = 10,
                    .rel_pos = V2f.right.scale(5),
                    .sweep_to_rel_pos = V2f.right.scale(20),
                    .effect = .{ .damage = 6 },
                },
                .range = 20,
            },
        },
        .cooldown = utl.TickCounter.initStopped(90),
    });
    c.enemy_difficulty = 1;
    return c;
}

pub fn batProto() Thing {
    var ret = creatureProto(.bat, .bat, .enemy, .{ .aggro = .{} }, 4, .smol, 17);
    ret.pathing_layer = .flying;
    ret.accel_params = .{
        .max_speed = 0.0192 * TileMap.tile_sz_f,
    };
    ret.controller.ai_actor.actions.getPtr(.melee_attack_1).* = (.{
        .kind = .{
            .melee_attack = .{
                .hitbox = .{
                    .radius = 10,
                    .rel_pos = V2f.right.scale(10),
                    .effect = .{ .damage = 3 },
                },
                .range = 12.5,
            },
        },
        .cooldown = utl.TickCounter.initStopped(70),
    });
    ret.enemy_difficulty = 0.5;
    return ret;
}

pub fn trollProto() Thing {
    var ret = creatureProto(.troll, .troll, .enemy, .{ .troll = .{} }, 40, .big, 20);
    ret.accel_params = .{
        .max_speed = 0.0119 * TileMap.tile_sz_f,
    };
    ret.controller.ai_actor.actions.getPtr(.melee_attack_1).* = (.{
        .kind = .{
            .melee_attack = .{
                .hitbox = .{
                    .radius = 10,
                    .rel_pos = V2f.right.scale(10),
                    .sweep_to_rel_pos = V2f.right.scale(25),
                    .effect = .{ .damage = 12 },
                },
                .range = 25,
            },
        },
        .cooldown = utl.TickCounter.initStopped(90),
    });
    ret.controller.ai_actor.actions.getPtr(.ability_1).* = (.{
        .kind = .{
            .regen_hp = .{
                .amount_per_sec = 5,
                .max_regen = 25,
            },
        },
        .cooldown = utl.TickCounter.initStopped(core.secsToTicks(5)),
    });
    ret.enemy_difficulty = 3;

    return ret;
}

pub fn gobbowProto() Thing {
    var ret = creatureProto(
        .gobbow,
        .gobbow,
        .enemy,
        .{ .ranged_flee = .{} },
        18,
        .medium,
        12,
    );
    ret.accel_params = .{
        .max_speed = 0.0161 * TileMap.tile_sz_f,
    };
    ret.controller.ai_actor.flee_range = 115;
    ret.controller.ai_actor.actions.getPtr(.projectile_attack_1).* = (.{
        .kind = .{ .projectile_attack = .{
            .projectile = .gobarrow,
            .range = 105,
            .LOS_thiccness = 3,
        } },
        .cooldown = utl.TickCounter.initStopped(60),
    });
    ret.enemy_difficulty = 1.5;
    return ret;
}

pub fn sharpboiProto() Thing {
    var ret = creatureProto(.sharpboi, .sharpboi, .enemy, .{ .aggro = .{} }, 25, .medium, 18);

    ret.accel_params = .{
        .max_speed = 0.0191 * TileMap.tile_sz_f,
    };
    ret.controller.ai_actor.actions.getPtr(.melee_attack_1).* = (.{
        .kind = .{
            .melee_attack = .{
                .lunge_accel = .{
                    .accel = 2.5,
                    .max_speed = 2.4,
                    .friction = 0,
                },
                .hitbox = .{
                    .mask = Thing.Faction.opposing_masks.get(.enemy),
                    .radius = 7.5,
                    .rel_pos = V2f.right.scale(20),
                    .effect = .{ .damage = 8 },
                    .deactivate_on_update = false,
                    .deactivate_on_hit = true,
                },
                .hit_to_side_force = 1.25,
                .range = 50,
                .LOS_thiccness = ret.coll_radius * 0.5,
            },
        },
        .cooldown = utl.TickCounter.initStopped(140),
    });
    ret.enemy_difficulty = 2.5;
    return ret;
}

pub fn acolyteProto() Thing {
    var ret = creatureProto(.acolyte, .acolyte, .enemy, .{ .acolyte = .{} }, 25, .medium, 12);
    ret.accel_params = .{
        .accel = 0.0047 * TileMap.tile_sz_f,
        .max_speed = 0.0198 * TileMap.tile_sz_f,
    };
    ret.controller.ai_actor.flee_range = 120;
    ret.controller.ai_actor.actions.getPtr(.spell_cast_summon_1).* = (.{
        .kind = .{ .spell_cast = .{
            .spell = Spell.getProto(.summon_bat),
        } },
        .cooldown = utl.TickCounter.initStopped(5 * core.fups_per_sec),
    });
    ret.enemy_difficulty = 2.5;
    return ret;
}

pub fn gobbomberProto() Thing {
    var ret = creatureProto(
        .gobbomber,
        .gobbomber,
        .enemy,
        .{ .gobbomber = .{} },
        15,
        .medium,
        12,
    );
    ret.hp.?.addShield(8, null);
    ret.accel_params = .{
        .max_speed = 0.0135 * TileMap.tile_sz_f,
    };
    ret.controller.ai_actor.flee_range = 90;
    ret.controller.ai_actor.actions.getPtr(.ability_1).* = .{
        .kind = .{ .shield_up = .{
            .amount = 8,
        } },
        .cooldown = utl.TickCounter.initStopped(core.secsToTicks(10)),
    };
    ret.controller.ai_actor.actions.getPtr(.projectile_attack_1).* = .{
        .kind = .{ .projectile_attack = .{
            .projectile = .gobbomb,
            .range = 95,
            .LOS_thiccness = 5,
        } },
        .cooldown = utl.TickCounter.initStopped(90),
    };
    ret.enemy_difficulty = 2.5;
    return ret;
}

pub fn dummyProto() Thing {
    var ret = creatureProto(.dummy, .dummy, .enemy, .idle, 25, .medium, 20);
    ret.dir = V2f.left;
    ret.enemy_difficulty = 1.5;
    return ret;
}

pub fn creatureProto(creature_kind: Kind, sprite_kind: Data.CreatureSpriteName, faction: Thing.Faction, ai: ?AI.ActorController.KindData, hp: f32, size_cat: Thing.SizeCategory, select_height_px: f32) Thing {
    var ret = Thing{
        .kind = .creature,
        .creature_kind = creature_kind,
        .spawn_state = .instance,
        .vision_range = 80,
        .draw_radius = Thing.SizeCategory.draw_radii.get(size_cat),
        .coll_radius = Thing.SizeCategory.coll_radii.get(size_cat),
        .coll_mask = Thing.Collision.Mask.initMany(&.{ .creature, .wall }),
        .coll_layer = Thing.Collision.Mask.initMany(&.{.creature}),
        .controller = if (ai) |a| .{ .ai_actor = .{ .ai = a } } else .default,
        .renderer = .{ .sprite = .{} },
        .hurtbox = .{
            .radius = Thing.SizeCategory.hurtbox_radii.get(size_cat),
        },
        .selectable = .{
            .height = select_height_px * core.game_sprite_scaling,
            .radius = Thing.SizeCategory.select_radii.get(size_cat),
        },
        .hp = Thing.HP.init(hp),
        .faction = faction,
        .shadow_radius_x = Thing.SizeCategory.draw_radii.get(size_cat),
    };
    const anim_name = utl.bufPrintLocal("{s}-idle", .{utl.enumToString(Data.CreatureSpriteName, sprite_kind)}) catch @panic("Unable to fmt anim name string");
    const idle_ref = Data.Ref(sprites.DirectionalSpriteAnim).init(anim_name);
    ret.renderer.sprite.setDirAnim(idle_ref);

    return ret;
}
