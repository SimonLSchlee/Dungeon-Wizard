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

const Collision = @import("../Collision.zig");
const Spell = @import("../Spell.zig");
const TargetKind = Spell.TargetKind;
const TargetingData = Spell.TargetingData;
const Params = Spell.Params;

pub const title = "Zap Dash";

pub const enum_name = "zap_dash";
pub const Controllers = [_]type{Projectile};

const base_line_thickness = 12;
const base_end_radius = 50;
const base_range = 200;

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .cast_time = .fast,
        .mana_cost = Spell.ManaCost.num(2),
        .rarity = .exceptional,
        .color = StatusEffect.proto_array.get(.mint).color,
        .targeting_data = .{
            .kind = .pos,
            .fixed_range = true,
            .max_range = base_range,
            .ray_to_mouse = .{
                .ends_at_coll_mask = Collision.Mask.initOne(.tile),
                .thickness = base_line_thickness,
            },
            .radius_at_target = base_end_radius,
        },
    },
);

line_hit_effect: Thing.HitEffect = .{
    .damage = 10,
},
end_hit_effect: Thing.HitEffect = .{
    .damage = 5,
    .status_stacks = StatusEffect.StacksArray.initDefault(0, .{ .stunned = 1 }),
},
line_thickness: f32 = base_line_thickness,
end_radius: f32 = base_end_radius,
range: f32 = base_range,
max_speed: f32 = 6,

pub const Projectile = struct {
    pub const controller_enum_name = enum_name ++ "_projectile";

    fade_timer: utl.TickCounter = utl.TickCounter.init(30),

    pub fn update(self: *Thing, room: *Room) Error!void {
        const spell_controller = &self.controller.spell;
        const spell = spell_controller.spell;
        const zap_dash = spell.kind.zap_dash;
        _ = zap_dash;
        const params = spell_controller.params;
        const target_pos = params.pos;
        _ = target_pos;
        const projectile: *@This() = &spell_controller.controller.zap_dash_projectile;
        if (projectile.fade_timer.tick(false)) {
            self.deferFree(room);
        }
        self.renderer.shape.poly_opt.fill_color = Colorf.white.fade(1 - projectile.fade_timer.remapTo0_1());
    }
};

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    params.validate(.pos, caster);
    const zap_dash = self.kind.zap_dash;
    const param_target_pos = params.pos;
    const target_dir = if (param_target_pos.sub(caster.pos).normalizedChecked()) |d| d else V2f.right;
    const orig_target_pos = caster.pos.add(target_dir.scale(zap_dash.range));
    const target_pos = self.targeting_data.getRayEnd(room, caster, self.targeting_data.ray_to_mouse.?, orig_target_pos);

    const line = Thing{
        .kind = .projectile,
        .dir = target_dir,
        .controller = .{ .spell = .{
            .spell = self.*,
            .params = params,
            .controller = .{
                .zap_dash_projectile = .{},
            },
        } },
        .renderer = .{ .shape = .{ .kind = .{
            .arrow = .{
                .length = target_pos.sub(caster.pos).length(),
                .thickness = 5,
            },
        }, .poly_opt = .{ .fill_color = Colorf.white } } },
        .hitbox = .{
            .active = true,
            .sweep_to_rel_pos = target_pos.sub(caster.pos),
            .mask = Thing.Faction.opposing_masks.get(caster.faction),
            .deactivate_on_hit = false,
            .deactivate_on_update = true,
            .effect = zap_dash.line_hit_effect,
            .radius = zap_dash.line_thickness * 0.5,
        },
    };
    var circle = line;
    circle.hitbox = .{
        .active = true,
        .mask = Thing.Faction.opposing_masks.get(caster.faction),
        .deactivate_on_hit = false,
        .deactivate_on_update = true,
        .effect = zap_dash.end_hit_effect,
        .radius = zap_dash.end_radius,
    };
    circle.renderer.shape = .{
        .draw_normal = false,
        .draw_under = true,
        .kind = .{ .circle = .{ .radius = zap_dash.end_radius } },
        .poly_opt = .{ .fill_color = .white },
    };
    _ = try room.queueSpawnThing(&line, caster.pos);
    _ = try room.queueSpawnThing(&circle, target_pos);
    caster.pos = target_pos;
}

pub const description =
    \\Zip around like a bolt of lightning!
    \\Enemies you pass through are damaged.
    \\Enemies near the target location take
    \\additional damage and are stunned.
;

pub fn getDescription(self: *const Spell, buf: []u8) Error![]u8 {
    const zap_dash: @This() = self.kind.zap_dash;
    const fmt =
        \\Line damage: {}
        \\Target area damage: {}
        \\Stun duration: {} secs
        \\
        \\{s}
        \\
    ;
    const line_damage: i32 = utl.as(i32, zap_dash.line_hit_effect.damage);
    const end_damage: i32 = utl.as(i32, zap_dash.end_hit_effect.damage);
    const dur_secs: i32 = zap_dash.end_hit_effect.status_stacks.get(.stunned) * utl.as(i32, @divFloor(StatusEffect.proto_array.get(.stunned).cooldown.num_ticks, core.fups_per_sec));
    return std.fmt.bufPrint(buf, fmt ++ "\n", .{ line_damage, end_damage, dur_secs, description });
}

pub fn getTags(self: *const Spell) Spell.Tag.Array {
    const zap_dash: @This() = self.kind.zap_dash;
    return Spell.Tag.makeArray(&.{
        &.{
            .{ .icon = .{ .sprite_enum = .target } },
            .{ .icon = .{ .sprite_enum = .mouse } },
        },
        &.{
            .{ .icon = .{ .sprite_enum = .wizard } },
            .{ .icon = .{ .sprite_enum = .arrow_right } },
            .{ .icon = .{ .sprite_enum = .wizard, .tint = .orange } },
        },
        &.{
            .{ .icon = .{ .sprite_enum = .lightning } },
            .{ .label = Spell.Tag.fmtLabel("{d:.0}", .{zap_dash.line_hit_effect.damage}) },
        },
        &.{
            .{ .icon = .{ .sprite_enum = .aoe_lightning } },
            .{ .label = Spell.Tag.fmtLabel("{d:.0}", .{zap_dash.end_hit_effect.damage}) },
        },
        &.{
            .{ .icon = .{ .sprite_enum = .spiral, .tint = draw.Coloru.rgb(255, 235, 147).toColorf() } },
            .{ .icon = .{ .sprite_enum = .ouchy_skull } },
        },
    });
}
