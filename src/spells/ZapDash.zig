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
const icon_text = @import("../icon_text.zig");

const Collision = @import("../Collision.zig");
const Spell = @import("../Spell.zig");
const TargetKind = Spell.TargetKind;
const TargetingData = Spell.TargetingData;
const Params = Spell.Params;

pub const title = "Zap Dash";

pub const enum_name = "zap_dash";
pub const Controllers = [_]type{Projectile};

const base_line_thickness = 7;
const base_end_radius = 25;
const base_range = 90;

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .cast_time = .fast,
        .mana_cost = Spell.ManaCost.num(2),
        .rarity = .exceptional,
        .color = draw.Coloru.rgb(255, 253, 231).toColorf(),
        .targeting_data = .{
            .kind = .pos,
            .fixed_range = true,
            .max_range = base_range,
            .ray_to_mouse = .{
                .ends_at_coll_mask = Collision.Mask.initOne(.wall),
                .thickness = base_line_thickness,
            },
            .radius_at_target = base_end_radius,
        },
    },
);

hit_effect: Thing.HitEffect = .{
    .damage = 6,
    .status_stacks = StatusEffect.StacksArray.initDefault(0, .{ .stunned = 1 }),
},
line_thickness: f32 = base_line_thickness,
end_radius: f32 = base_end_radius,
range: f32 = base_range,

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
        switch (self.renderer) {
            .shape => |*shape| {
                shape.poly_opt.fill_color = Colorf.white.fade(1 - projectile.fade_timer.remapTo0_1());
            },
            .lightning => |*lightning| {
                lightning.color = Colorf.white.fade(1 - projectile.fade_timer.remapTo0_1());
            },
            else => {},
        }
    }
};

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    params.validate(.pos, caster);
    const zap_dash = self.kind.zap_dash;
    const param_target_pos = params.pos;
    const to_target = param_target_pos.sub(caster.pos);
    const target_dir = if (to_target.normalizedChecked()) |d| d else V2f.right;
    const orig_target_pos = caster.pos.add(target_dir.scale(zap_dash.range));
    const target_pos = self.targeting_data.getRayEnd(room, caster, self.targeting_data.ray_to_mouse.?, orig_target_pos);

    var line = Thing{
        .kind = .projectile,
        .dir = target_dir,
        .controller = .{ .spell = .{
            .spell = self.*,
            .params = params,
            .controller = .{
                .zap_dash_projectile = .{},
            },
        } },
        .renderer = .{ .lightning = .{} },
        .hitbox = .{
            .sweep_to_rel_pos = target_pos.sub(caster.pos),
            .mask = Thing.Faction.opposing_masks.get(caster.faction),
            .deactivate_on_hit = false,
            .deactivate_on_update = true,
            .effect = zap_dash.hit_effect,
            .radius = zap_dash.line_thickness * 0.5,
        },
    };
    line.hitbox.?.activate(room);
    {
        const renderer = &line.renderer.lightning;
        const dist = @max(to_target.length(), 1);
        const approx_section_length: f32 = 6;
        const num_sections = @round(dist / approx_section_length);
        const section_length = dist / num_sections;
        var i: f32 = 0;
        while (i < num_sections) {
            const curr_pos = caster.pos.add(target_dir.scale(section_length * i));
            const rang = utl.tau * room.rng.random().float(f32);
            const rdst = 2 + 4 * room.rng.random().float(f32);
            const dir = V2f.fromAngleRadians(rang);
            const point = curr_pos.add(dir.scale(rdst));
            renderer.points.append(point) catch break;
            i += 1;
        }
    }
    var circle = line;
    circle.hitbox = .{
        .active = true, // copy hit id from line
        .mask = Thing.Faction.opposing_masks.get(caster.faction),
        .deactivate_on_hit = false,
        .deactivate_on_update = true,
        .effect = zap_dash.hit_effect,
        .radius = zap_dash.end_radius,
    };
    circle.hitbox.?.effect.hit_id = line.hitbox.?.effect.hit_id;
    circle.renderer = .{ .shape = .{
        .draw_normal = false,
        .draw_under = true,
        .kind = .{ .circle = .{ .radius = zap_dash.end_radius } },
        .poly_opt = .{ .fill_color = .white },
    } };
    _ = try room.queueSpawnThing(&line, caster.pos);
    _ = try room.queueSpawnThing(&circle, target_pos);
    caster.pos = target_pos;
}

pub fn getTooltip(self: *const Spell, tt: *Spell.Tooltip) Error!void {
    const zap_dash: @This() = self.kind.zap_dash;
    const hit_damage = Thing.Damage{
        .kind = .lightning,
        .amount = zap_dash.hit_effect.damage,
    };
    const fmt =
        \\Teleport a short distance.
        \\Deal {any} damage to enemies
        \\on the way, and near the target
        \\location.
    ;
    tt.desc = try Spell.Tooltip.Desc.fromSlice(
        try std.fmt.bufPrint(&tt.desc.buffer, fmt, .{
            hit_damage,
        }),
    );
    tt.infos.appendAssumeCapacity(.{ .damage = .lightning });
    tt.infos.appendAssumeCapacity(.{ .status = .stunned });
}

pub fn getNewTags(self: *const Spell) Error!Spell.NewTag.Array {
    var buf: [64]u8 = undefined;
    const zap_dash: @This() = self.kind.zap_dash;
    return Spell.NewTag.Array.fromSlice(&.{
        .{
            .card_label = try Spell.NewTag.CardLabel.fromSlice(
                try std.fmt.bufPrint(&buf, "{any}{any}{any}{any}{any}", .{
                    icon_text.Fmt{ .tint = .orange },
                    icon_text.Icon.wizard,
                    icon_text.Fmt{ .tint = .white },
                    icon_text.Icon.arrow_right,
                    icon_text.Icon.wizard,
                }),
            ),
        },
        try Spell.NewTag.makeDamage(.lightning, zap_dash.hit_effect.damage, false),
        try Spell.NewTag.makeStatus(.stunned, zap_dash.hit_effect.status_stacks.get(.stunned)),
    }) catch unreachable;
}
