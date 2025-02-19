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
const Data = @import("../Data.zig");

const Collision = @import("../Collision.zig");
const Spell = @import("../Spell.zig");
const TargetKind = Spell.TargetKind;
const TargetingData = Spell.TargetingData;
const Params = Spell.Params;

pub const title = "Flare Dart";

pub const enum_name = "flare_dart";
pub const Controllers = [_]type{Projectile};

const base_ball_radius = 3.25;
const base_range = 125;

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .cast_time = .fast,
        .color = draw.Coloru.rgb(236, 98, 43).toColorf(),
        .targeting_data = .{
            .kind = .pos,
            .fixed_range = true,
            .max_range = base_range,
            .ray_to_mouse = .{
                .ends_at_coll_mask = Collision.Mask.initMany(&.{.wall}),
                .thickness = base_ball_radius * 2, // TODO use radius below?
                .cast_orig_dist = 10,
            },
        },
    },
);

hit_effect: Thing.HitEffect = .{
    .damage = 5,
    .damage_kind = .fire,
    .status_stacks = StatusEffect.StacksArray.initDefault(0, .{ .lit = 1 }),
},
ball_radius: f32 = base_ball_radius,
range: f32 = base_range,
max_speed: f32 = 3,

const AnimRef = struct {
    var projectile_loop = Data.Ref(Data.SpriteAnim).init("spell-projectile-flare-dart");
};
const SoundRef = struct {
    var woosh = Data.Ref(Data.Sound).init("long-woosh");
    var crackle = Data.Ref(Data.Sound).init("crackle");
};

pub const Projectile = struct {
    pub const controller_enum_name = enum_name ++ "_projectile";

    pub fn update(self: *Thing, room: *Room) Error!void {
        const spell_controller = &self.controller.spell;
        const spell = spell_controller.spell;
        const flare_dart = spell.kind.flare_dart;
        _ = flare_dart;
        const params = spell_controller.params;
        const target_pos = params.pos;
        _ = target_pos;
        const projectile: *@This() = &spell_controller.controller.flare_dart_projectile;
        _ = projectile;
        _ = AnimRef.projectile_loop.get();
        _ = self.renderer.sprite.playNormal(AnimRef.projectile_loop, .{ .loop = true });

        if (self.last_coll != null or !self.hitbox.?.active) {
            self.deferFree(room);
        }
    }
};

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    params.validate(.pos, caster);
    const flare_dart: @This() = self.kind.flare_dart;
    const target_pos = params.pos;
    const target_dir = if (target_pos.sub(caster.pos).normalizedChecked()) |d| d else V2f.right;

    var ball = Thing{
        .kind = .projectile,
        .dir = target_dir,
        .vel = target_dir.scale(flare_dart.max_speed),
        .coll_radius = flare_dart.ball_radius,
        .coll_mask = Thing.Collision.Mask.initMany(&.{.wall}),
        .controller = .{ .spell = .{
            .spell = self.*,
            .params = params,
            .controller = .{
                .flare_dart_projectile = .{},
            },
        } },
        .renderer = .{
            .sprite = .{
                .draw_over = false,
                .draw_normal = true,
                .rotate_to_dir = true,
                .flip_x_to_dir = true,
                .rel_pos = v2f(0, -14),
            },
        },
        .hitbox = .{
            .mask = Thing.Faction.opposing_masks.get(caster.faction),
            .deactivate_on_hit = true,
            .deactivate_on_update = false,
            .effect = flare_dart.hit_effect,
            .radius = flare_dart.ball_radius,
        },
        .shadow_radius_x = flare_dart.ball_radius,
    };
    ball.hitbox.?.activate(room);
    ball.renderer.sprite.setNormalAnim(AnimRef.projectile_loop);
    _ = try room.queueSpawnThing(&ball, caster.pos);
    _ = App.get().sfx_player.playSound(&SoundRef.crackle, .{});
}

pub fn getTooltip(self: *const Spell, tt: *Spell.Tooltip) Error!void {
    const flare_dart: @This() = self.kind.flare_dart;
    const hit_dmg = Thing.Damage{
        .kind = .fire,
        .amount = flare_dart.hit_effect.damage,
    };
    const fmt =
        \\Projectile which deals {any}
        \\damage on impact.
    ;
    tt.desc = try Spell.Tooltip.Desc.fromSlice(
        try std.fmt.bufPrint(&tt.desc.buffer, fmt, .{
            hit_dmg,
        }),
    );
    tt.infos.appendAssumeCapacity(.{ .damage = .fire });
    tt.infos.appendAssumeCapacity(.{ .status = .lit });
}

pub fn getNewTags(self: *const Spell) Error!Spell.NewTag.Array {
    const flare_dart: @This() = self.kind.flare_dart;
    return Spell.NewTag.Array.fromSlice(&.{
        try Spell.NewTag.makeDamage(.fire, flare_dart.hit_effect.damage, false),
    }) catch unreachable;
}
