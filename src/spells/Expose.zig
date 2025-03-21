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
const Data = @import("../Data.zig");
const Room = @import("../Room.zig");
const Thing = @import("../Thing.zig");
const TileMap = @import("../TileMap.zig");
const StatusEffect = @import("../StatusEffect.zig");

const Spell = @import("../Spell.zig");
const TargetKind = Spell.TargetKind;
const TargetingData = Spell.TargetingData;
const Params = Spell.Params;

pub const title = "Expose";

pub const enum_name = "expose";
pub const Controllers = [_]type{Projectile};

const base_radius = 20;
const base_color = Colorf.rgb(0.4, 0.2, 0.6);

pub const proto = Spell.makeProto(
    std.meta.stringToEnum(Spell.Kind, enum_name).?,
    .{
        .cast_time = .medium,
        .mana_cost = Spell.ManaCost.num(2),
        .obtainableness = std.EnumSet(Spell.Obtainableness).initOne(.starter),
        .color = Spell.colors.magic,
        .targeting_data = .{
            .kind = .pos,
            .target_faction_mask = Thing.Faction.Mask.initOne(.enemy),
            .max_range = 100,
            .show_max_range_ring = true,
            .radius_at_target = base_radius,
        },
    },
);

hit_effect: Thing.HitEffect = .{
    .damage = 6,
    .damage_kind = .magic,
    .status_stacks = StatusEffect.StacksArray.initDefault(0, .{ .exposed = 5 }),
},
radius: f32 = base_radius,

const AnimRef = struct {
    var loop = Data.Ref(Data.SpriteAnim).init("expose_circle-loop");
    var end = Data.Ref(Data.SpriteAnim).init("expose_circle-end");
};
const SoundRef = struct {
    var chime = Data.Ref(Data.Sound).init("creep-chime");
};

pub const Projectile = struct {
    pub const controller_enum_name = enum_name ++ "_projectile";

    state: enum {
        expanding,
        fading,
    } = .expanding,
    timer: utl.TickCounter = utl.TickCounter.init(15),

    pub fn update(self: *Thing, room: *Room) Error!void {
        const spell_controller = &self.controller.spell;
        const spell = spell_controller.spell;
        const expose = spell.kind.expose;
        _ = expose;
        const params = spell_controller.params;
        _ = params;
        const projectile: *Projectile = &spell_controller.controller.expose_projectile;

        _ = projectile.timer.tick(false);
        switch (projectile.state) {
            .expanding => {
                if (!projectile.timer.running) {
                    projectile.timer = utl.TickCounter.init(60);
                    projectile.state = .fading;
                    self.hitbox.?.activate(room);
                    self.renderer.sprite.scale = core.game_sprite_scaling * 0.5;
                    self.renderer.sprite.sprite_tint = Colorf.white;
                    self.renderer.sprite.setNormalAnim(AnimRef.end);
                    _ = App.get().sfx_player.playSound(&SoundRef.chime, .{});
                } else {
                    const f = projectile.timer.remapTo0_1();
                    self.renderer.sprite.scale = f * core.game_sprite_scaling * 0.5;
                }
            },
            .fading => {
                if (!projectile.timer.running) {
                    self.deferFree(room);
                } else {
                    const f = projectile.timer.remapTo0_1();
                    self.renderer.sprite.sprite_tint = Colorf.white.lerp(base_color, f).fade(1 - f);
                }
            },
        }
    }
};

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    params.validate(.pos, caster);
    const expose = self.kind.expose;
    const target_pos = params.pos;
    var hit_circle = Thing{
        .kind = .projectile,
        .accel_params = .{
            .accel = 0.5,
            .max_speed = 5,
        },
        .controller = .{ .spell = .{
            .spell = self.*,
            .params = params,
            .controller = .{ .expose_projectile = .{} },
        } },
        .hitbox = .{
            .deactivate_on_hit = false,
            .deactivate_on_update = true,
            .effect = expose.hit_effect,
            .mask = Thing.Faction.opposing_masks.get(caster.faction),
            .radius = expose.radius,
        },
        .renderer = .{ .sprite = .{
            .draw_normal = false,
            .draw_under = true,
            .rotate_to_dir = true,
            .sprite_tint = base_color,
            .scale = 0,
        } },
    };
    _ = AnimRef.loop.get();
    _ = AnimRef.end.get();
    hit_circle.renderer.sprite.setNormalAnim(AnimRef.loop);
    _ = try room.queueSpawnThing(&hit_circle, target_pos);
}

pub fn getTooltip(self: *const Spell, tt: *Spell.Tooltip) Error!void {
    const expose: @This() = self.kind.expose;
    const hit_damage = Thing.Damage{
        .kind = .magic,
        .amount = expose.hit_effect.damage,
    };
    const fmt =
        \\Deal {any} damage and {any}expose
        \\enemies for {d:.0} seconds.
    ;
    tt.desc = try Spell.Tooltip.Desc.fromSlice(
        try std.fmt.bufPrint(&tt.desc.buffer, fmt, .{
            hit_damage,
            StatusEffect.getIcon(.exposed),
            StatusEffect.getDurationSeconds(.exposed, expose.hit_effect.status_stacks.get(.exposed)).?,
        }),
    );
    tt.infos.appendAssumeCapacity(.{ .status = .exposed });
}

pub fn getNewTags(self: *const Spell) Error!Spell.NewTag.Array {
    const expose: @This() = self.kind.expose;
    return Spell.NewTag.Array.fromSlice(&.{
        try Spell.NewTag.makeDamage(.magic, expose.hit_effect.damage, false),
        try Spell.NewTag.makeStatus(.exposed, expose.hit_effect.status_stacks.get(.exposed)),
    }) catch unreachable;
}
