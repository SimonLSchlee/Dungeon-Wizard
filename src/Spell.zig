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

const App = @import("App.zig");
const getPlat = App.getPlat;
const Room = @import("Room.zig");
const Thing = @import("Thing.zig");
const TileMap = @import("TileMap.zig");
const Data = @import("Data.zig");
const pool = @import("pool.zig");
const Collision = @import("Collision.zig");
const menuUI = @import("menuUI.zig");
const sprites = @import("sprites.zig");
const ImmUI = @import("ImmUI.zig");
const Action = @import("Action.zig");
const Run = @import("Run.zig");
const StatusEffect = @import("StatusEffect.zig");
const icon_text = @import("icon_text.zig");
const tooltip = @import("tooltip.zig");

const Spell = @This();

pub const Pool = pool.BoundedPool(Spell, 32);
pub const Id = pool.Id;

// no scaling applied
pub const card_dims = v2f(71, 99);
pub const card_art_topleft_offset = v2f(3, 3);
pub const card_art_dims = v2f(65, 46);
pub const card_mana_topleft_offset = v2f(58, 1);
pub const card_tags_topleft_offset = v2f(5, 66);
pub const card_tags_dims = v2f(61, 29);
pub const card_tag_icon_dims = v2f(7, 7);
pub const card_title_center_offset = v2f(36, 56);

var desc_buf: [2048]u8 = undefined;

pub const SpellTypes = blk: {
    const player_spells = [_]type{
        @import("spells/Unherring.zig"),
        @import("spells/Protec.zig"),
        @import("spells/FrostVom.zig"),
        @import("spells/Blackmail.zig"),
        @import("spells/Mint.zig"),
        @import("spells/Impling.zig"),
        @import("spells/Promptitude.zig"),
        @import("spells/FlameyExplodey.zig"),
        @import("spells/Expose.zig"),
        @import("spells/ZapDash.zig"),
        @import("spells/FlareDart.zig"),
        @import("spells/Trailblaze.zig"),
        @import("spells/FlamePurge.zig"),
        @import("spells/BlankMind.zig"),
        @import("spells/ShieldFu.zig"),
        @import("spells/Ignite.zig"),
        @import("spells/MassIgnite.zig"),
        @import("spells/Hmmm.zig"),
        @import("spells/Switcharoo.zig"),
    };
    const nonplayer_spells = @import("spells/nonplayer.zig").spells;
    break :blk player_spells ++ nonplayer_spells;
};

pub const Kind = utl.EnumFromTypes(&SpellTypes, "enum_name");
pub const KindData = utl.TaggedUnionFromTypes(&SpellTypes, "enum_name", Kind);
const all_spells = blk: {
    const kind_info = @typeInfo(Kind).@"enum";
    var ret: [kind_info.fields.len]Spell = undefined;
    for (kind_info.fields, 0..) |f, i| {
        const kind: Kind = @enumFromInt(f.value);
        const proto = getProto(kind);
        ret[i] = proto;
    }
    break :blk ret;
};
const spell_names = blk: {
    var ret: std.EnumArray(Kind, []const u8) = undefined;
    for (std.meta.fields(Kind)) |f| {
        const kind: Kind = @enumFromInt(f.value);
        const T = GetKindType(kind);
        ret.set(kind, T.title);
    }
    break :blk ret;
};

pub fn GetKindType(kind: Kind) type {
    const fields: []const std.builtin.Type.UnionField = std.meta.fields(KindData);
    if (std.meta.fieldIndex(KindData, @tagName(kind))) |i| {
        return fields[i].type;
    }
    @compileError("No Spell kind: " ++ @tagName(kind));
}

pub fn getProto(kind: Kind) Spell {
    switch (kind) {
        inline else => |k| {
            return GetKindType(k).proto;
        },
    }
}

pub const CardSpriteEnum = enum {
    card_blank,
    card_base,
    rarity_pedestrian,
    rarity_interesting,
    rarity_exceptional,
    rarity_brilliant,

    pub fn fromRarity(r: Rarity) CardSpriteEnum {
        return switch (r) {
            .pedestrian => .rarity_pedestrian,
            .interesting => .rarity_interesting,
            .exceptional => .rarity_exceptional,
            .brilliant => .rarity_brilliant,
        };
    }
};

pub const Rarity = enum {
    pedestrian,
    interesting,
    exceptional,
    brilliant,
};

pub const TargetKind = Action.TargetKind;
pub const Params = Action.Params;

pub const TargetingData = struct {
    pub const Ray = struct {
        ends_at_coll_mask: Collision.Mask = Collision.Mask.initEmpty(),
        thickness: f32 = 1,
        cast_orig_dist: f32 = 0,
    };
    kind: Action.TargetKind = .self,
    color: Colorf = .cyan,
    fixed_range: bool = false,
    max_range: f32 = std.math.inf(f32),
    show_max_range_ring: bool = false,
    ray_to_mouse: ?Ray = null,
    target_faction_mask: Thing.Faction.Mask = .{},
    target_mouse_pos: bool = false,
    radius_at_target: ?f32 = null,
    cone_from_self_to_mouse: ?struct {
        radius: f32,
        radians: f32,
    } = null,
    requires_los_to_thing: bool = false,

    fn fmtRange(self: *const TargetingData, buf: []u8) Error![]u8 {
        if (self.max_range == std.math.inf(f32)) return buf[0..0];
        return try std.fmt.bufPrint(buf, "Range: {}\n", .{utl.as(u32, @floor(self.max_range))});
    }

    pub fn fmtDesc(self: *const TargetingData, buf: []u8) Error![]u8 {
        var len: usize = 0;
        len += (try std.fmt.bufPrint(buf[len..], "Target: {s}\n", .{
            switch (self.kind) {
                .self => "self",
                .thing => "thing",
                .pos => "ground",
            },
        })).len;
        len += (try self.fmtRange(buf[len..])).len;
        return buf[0..len];
    }

    pub fn getRayEnd(self: *const TargetingData, room: *const Room, caster: *const Thing, ray: Ray, target_pos: V2f) V2f {
        const caster_to_target = target_pos.sub(caster.pos);
        const target_dir = if (caster_to_target.normalizedChecked()) |d| d else return target_pos;
        const cast_orig = caster.pos.add(target_dir.scale(ray.cast_orig_dist));
        const cast_orig_to_target = target_pos.sub(cast_orig);
        if (cast_orig_to_target.dot(target_dir) < 0) return cast_orig;

        const max_radius = self.max_range + caster.coll_radius;
        const capped_dist = if (self.fixed_range) max_radius else @min(max_radius, cast_orig.length());
        const capped_vec = target_dir.scale(capped_dist);
        const ray_radius = ray.thickness * 0.5;

        var target_hit_pos = cast_orig.add(capped_vec);
        var end_ray_pos = target_hit_pos;

        if (Collision.getNextSweptCircleCollision(
            cast_orig,
            capped_vec,
            ray_radius,
            ray.ends_at_coll_mask,
            &.{caster.id},
            room,
        )) |coll| {
            target_hit_pos = coll.pos;
            end_ray_pos = coll.pos.add(coll.normal.scale(ray_radius));
        }

        return end_ray_pos;
    }

    pub fn getParams(targeting_data: *const TargetingData, room: *Room, caster: *const Thing, mouse_pos: V2f) ?Params {
        switch (targeting_data.kind) {
            .pos => {
                const caster_to_mouse = mouse_pos.sub(caster.pos);
                const target_dir = if (caster_to_mouse.normalizedChecked()) |d| d else V2f.right;
                const max_radius = targeting_data.max_range + caster.coll_radius;
                const capped_dist = if (targeting_data.fixed_range) max_radius else @min(max_radius, caster_to_mouse.length());
                const capped_vec = target_dir.scale(capped_dist);
                var target_pos = caster.pos.add(capped_vec);
                var ret = Params{
                    .target_kind = .pos,
                    .pos = target_pos,
                    .face_dir = target_pos.sub(caster.pos).normalizedChecked() orelse caster.dir,
                };
                if (targeting_data.ray_to_mouse) |ray| {
                    const cast_orig = caster.pos.add(target_dir.scale(ray.cast_orig_dist));
                    if (target_pos.sub(cast_orig).dot(target_dir) < 0) {
                        ret.pos = cast_orig;
                    }
                    ret.cast_orig = cast_orig;
                }
                return ret;
            },
            .self => {
                return .{
                    .target_kind = .self,
                    .thing = caster.id,
                    .pos = caster.pos,
                };
            },
            .thing => {
                if (room.getMousedOverThing(targeting_data.target_faction_mask)) |thing| {
                    // TODO different range calculation? sort that out and make consistent
                    const range = @max(caster.pos.dist(thing.pos) - caster.coll_radius - thing.coll_radius, 0);
                    if (range > targeting_data.max_range) {
                        return null;
                    }
                    if (targeting_data.requires_los_to_thing and !room.tilemap.isLOSBetween(caster.pos, thing.pos)) return null;
                    if (targeting_data.target_faction_mask.contains(thing.faction)) {
                        return .{
                            .target_kind = .thing,
                            .face_dir = thing.pos.sub(caster.pos).normalizedChecked() orelse caster.dir,
                            .thing = thing.id,
                            .pos = thing.pos,
                        };
                    }
                }
            },
        }
        return null;
    }

    pub fn render(targeting_data: *const TargetingData, room: *const Room, caster: *const Thing, params: ?Params) Error!void {
        const plat = App.getPlat();

        if (params == null) {
            if (targeting_data.show_max_range_ring and targeting_data.max_range < 99999) {
                plat.circlef(
                    caster.pos,
                    targeting_data.max_range + caster.coll_radius,
                    .{
                        .outline = .{ .color = targeting_data.color.fade(0.5) },
                        .fill_color = null,
                    },
                );
            }
        }

        switch (targeting_data.kind) {
            .pos => {
                const mouse_pos = if (params) |p| p.pos else plat.getMousePosWorld(room.camera);
                const caster_to_mouse = mouse_pos.sub(caster.pos);
                const target_dir = if (caster_to_mouse.normalizedChecked()) |d| d else V2f.right;
                const max_radius = targeting_data.max_range + caster.coll_radius;
                const capped_dist = if (targeting_data.fixed_range) max_radius else @min(max_radius, caster_to_mouse.length());
                const capped_vec = target_dir.scale(capped_dist);
                var target_circle_pos = caster.pos.add(capped_vec);

                if (targeting_data.ray_to_mouse) |ray| {
                    const cast_orig = caster.pos.add(target_dir.scale(ray.cast_orig_dist));
                    if (mouse_pos.sub(cast_orig).dot(target_dir) > 0) {
                        const ray_end = targeting_data.getRayEnd(room, caster, ray, target_circle_pos);
                        if (ray_end.sub(caster.pos).length() < capped_dist) {
                            target_circle_pos = ray_end;
                        }
                    } else {
                        target_circle_pos = cast_orig;
                    }
                    const ray_radius = ray.thickness * 0.5;
                    plat.circlef(cast_orig, ray_radius, .{ .fill_color = targeting_data.color });
                    plat.linef(cast_orig, target_circle_pos, .{ .thickness = ray.thickness, .color = targeting_data.color });
                    plat.circlef(target_circle_pos, ray_radius, .{ .fill_color = targeting_data.color });
                    //if (coll) |c| {
                    //    plat.circlef(c.pos, 3, .{ .fill_color = .red });
                    //}
                }
                if (targeting_data.cone_from_self_to_mouse) |cone| {
                    const start_rads = target_dir.toAngleRadians() - cone.radians * 0.5;
                    const end_rads = start_rads + cone.radians;
                    //try plat.textf(caster.pos.add(V2f.right.scale(cone.radius * 0.5).rotRadians(start_rads)), "{d:.3}", .{start_rads}, .{ .color = .white });
                    plat.sectorf(
                        caster.pos,
                        cone.radius,
                        start_rads,
                        end_rads,
                        .{ .fill_color = targeting_data.color.fade(0.5) },
                    );
                }
                if (targeting_data.radius_at_target) |r| {
                    plat.circlef(target_circle_pos, r, .{ .fill_color = targeting_data.color.fade(0.4) });
                }
                if (targeting_data.target_mouse_pos) {
                    plat.circlef(target_circle_pos, 10, .{ .fill_color = targeting_data.color.fade(0.4) });
                }
            },
            .self => {
                if (caster.selectable) |s| {
                    plat.circlef(caster.pos, s.radius, .{ .fill_color = targeting_data.color.fade(0.4) });
                }
                if (targeting_data.radius_at_target) |r| {
                    plat.circlef(caster.pos, r, .{ .fill_color = targeting_data.color.fade(0.4) });
                }
            },
            .thing => {
                const maybe_targeted_thing = if (params) |p|
                    room.getConstThingById(p.thing.?)
                else
                    @constCast(room).getMousedOverThing(targeting_data.target_faction_mask);

                // show all possible target...
                // but only if params are not passed in
                if (params == null) {
                    for (&room.things.items) |*thing| {
                        if (!thing.isActive()) continue;
                        if (thing.selectable == null) continue;
                        if (!targeting_data.target_faction_mask.contains(thing.faction)) continue;
                        const range = @max(caster.pos.dist(thing.pos) - caster.coll_radius - thing.coll_radius, 0);
                        if (range > targeting_data.max_range) continue;
                        // we're already drawing it after this loop
                        if (maybe_targeted_thing) |targeted_thing| {
                            if (thing.id.eql(targeted_thing.id)) {
                                continue;
                            }
                        }
                        const selectable = thing.selectable.?;
                        plat.circlef(
                            thing.pos,
                            selectable.radius - 10,
                            .{ .fill_color = targeting_data.color.fade(0.4) },
                        );
                    }
                }
                // selected target, if any
                if (maybe_targeted_thing) |thing| {
                    const range = @max(caster.pos.dist(thing.pos) - caster.coll_radius - thing.coll_radius, 0);
                    if (range <= targeting_data.max_range) {
                        var targeting_color = targeting_data.color;
                        if (targeting_data.requires_los_to_thing) {
                            if (room.tilemap.raycastLOS(caster.pos, thing.pos)) |tile_coord| {
                                targeting_color = .red;
                                const rect = TileMap.tileCoordToRect(tile_coord);
                                plat.rectf(rect.pos, rect.dims, .{
                                    .fill_color = null,
                                    .outline = .{
                                        .color = Colorf.red.fade(0.6),
                                        .thickness = 3,
                                    },
                                });
                            }
                        }
                        if (targeting_data.radius_at_target) |r| {
                            plat.circlef(caster.pos, r, .{ .fill_color = targeting_color.fade(0.4) });
                        }
                        if (targeting_data.ray_to_mouse) |ray| {
                            const ray_radius = ray.thickness * 0.5;
                            plat.linef(caster.pos, thing.pos, .{ .thickness = ray.thickness, .color = targeting_color });
                            plat.circlef(thing.pos, ray_radius, .{ .fill_color = targeting_color });
                        }
                        if (targeting_data.radius_at_target) |r| {
                            plat.circlef(caster.pos, r, .{ .fill_color = targeting_color.fade(0.4) });
                        }
                        // we always gotta check this... things can become unselectable e.g. when dying
                        if (thing.selectable) |s| {
                            plat.circlef(
                                thing.pos,
                                s.radius,
                                .{ .fill_color = targeting_color.fade(0.5) },
                            );
                        }
                    }
                }
            },
        }
    }
};

pub const Controller = struct {
    const ControllerTypes = blk: {
        var num = 0;
        for (SpellTypes) |M| {
            if (@hasDecl(M, "Controllers")) {
                for (M.Controllers) |_| {
                    num += 1;
                }
            }
        }
        var Types: [num]type = undefined;
        var i = 0;
        for (SpellTypes) |M| {
            if (@hasDecl(M, "Controllers")) {
                for (M.Controllers) |C| {
                    Types[i] = C;
                    i += 1;
                }
            }
        }
        break :blk Types;
    };
    pub const ControllerKind = utl.EnumFromTypes(&ControllerTypes, "controller_enum_name");
    pub const ControllerKindData = utl.TaggedUnionFromTypes(&ControllerTypes, "controller_enum_name", ControllerKind);

    controller: ControllerKindData,
    spell: Spell,
    params: Params,

    pub fn update(self: *Thing, room: *Room) Error!void {
        const scontroller = self.controller.spell;
        switch (scontroller.controller) {
            inline else => |s| {
                try @TypeOf(s).update(self, room);
            },
        }
    }
};

pub const max_spells_in_array = 256;
pub const SpellArray = std.BoundedArray(Spell, max_spells_in_array);
const WeightsArray = std.BoundedArray(f32, max_spells_in_array);

const rarity_weight_base = std.EnumArray(Rarity, f32).init(.{
    .pedestrian = 0.5,
    .interesting = 0.30,
    .exceptional = 0.15,
    .brilliant = 0.05,
});

pub fn getSpellWeights(spells: []const Spell) WeightsArray {
    var ret = WeightsArray{};
    for (spells) |spell| {
        ret.append(rarity_weight_base.get(spell.rarity)) catch unreachable;
    }
    return ret;
}

pub fn generateRandom(rng: std.Random, mask: Obtainableness.Mask, mode: Run.Mode, allow_duplicates: bool, buf: []Spell) usize {
    var num: usize = 0;
    var spell_pool = SpellArray{};
    for (all_spells) |spell| {
        if (spell.obtainable_modes.contains(mode) and spell.obtainableness.intersectWith(mask).count() > 0) {
            spell_pool.append(spell) catch unreachable;
        }
    }
    for (0..buf.len) |i| {
        if (spell_pool.len == 0) break;
        const weights = getSpellWeights(spell_pool.constSlice());
        const idx = rng.weightedIndex(f32, weights.constSlice());
        const spell = if (allow_duplicates) spell_pool.get(idx) else spell_pool.swapRemove(idx);
        buf[i] = spell;
        num += 1;
    }
    return num;
}

pub fn makeRoomReward(rng: std.Random, mode: Run.Mode, buf: []Spell) usize {
    return generateRandom(rng, Obtainableness.Mask.initOne(.room_reward), mode, false, buf);
}

pub fn makeShopSpells(rng: std.Random, mode: Run.Mode, buf: []Spell) usize {
    return generateRandom(rng, Obtainableness.Mask.initOne(.shop), mode, false, buf);
}

pub const Obtainableness = enum {
    pub const Mask = std.EnumSet(Obtainableness);

    starter,
    room_reward,
    shop,
};

pub const ManaCost = union(enum) {
    pub const SpriteEnum = enum {
        zero,
        one,
        two,
        three,
        four,
        five,
        six,
        seven,
        eight,
        nine,
        X,
        unknown,
        crystal,
    };
    number: u8,
    X,
    unknown,

    pub fn num(n: u8) ManaCost {
        assert(n < 10);
        return ManaCost{ .number = n };
    }

    pub fn getActualCost(self: ManaCost, caster: *const Thing) ?u8 {
        return switch (self) {
            .number => |n| n,
            .X => if (caster.mana) |mana| utl.as(u8, mana.curr) else 0,
            .unknown => null,
        };
    }

    pub fn toSpriteEnum(self: ManaCost) SpriteEnum {
        return switch (self) {
            .number => |n| @enumFromInt(n),
            .X => .X,
            .unknown => .unknown,
        };
    }
};

pub const NewTag = struct {
    pub const Array = std.BoundedArray(NewTag, 8);
    pub const CardLabel = utl.BoundedString(16);
    pub const TooltipLabel = utl.BoundedString(64);
    pub const InfoArr = std.BoundedArray(tooltip.Info, 8);

    card_label: CardLabel = .{},
    tooltip_label: TooltipLabel = .{},
    info_tooltips: InfoArr = .{},
    start_on_new_line: bool = false,

    pub fn makeDamage(kind: Thing.HitEffect.DamageKind, amount: f32, aoe_hits_allies: bool) Error!NewTag {
        var ret = NewTag{};
        var icon: icon_text.Icon = .blood_splat;
        var dmg_type_string: []const u8 = "";
        switch (kind) {
            .magic => {
                icon = if (aoe_hits_allies) .aoe_magic else .magic;
                dmg_type_string = "Magic ";
            },
            .fire => {
                icon = if (aoe_hits_allies) .aoe_fire else .fire;
                dmg_type_string = "Fire ";
                ret.info_tooltips.appendAssumeCapacity(.{ .damage = .fire });
                ret.info_tooltips.appendAssumeCapacity(.{ .status = .lit });
            },
            .ice => {
                icon = if (aoe_hits_allies) .aoe_ice else .icicle;
                dmg_type_string = "Ice ";
            },
            .lightning => {
                icon = if (aoe_hits_allies) .aoe_lightning else .lightning;
                dmg_type_string = "Lightning ";
            },
            else => {},
        }
        var buf: [64]u8 = undefined;
        ret.card_label = try CardLabel.fromSlice(
            try icon_text.partsToUtf8(&buf, &.{
                .{ .icon = icon },
                .{ .text = try utl.bufPrintLocal("{d:.0}", .{@floor(amount)}) },
            }),
        );
        ret.tooltip_label = try TooltipLabel.fromSlice(
            try icon_text.partsToUtf8(&buf, &.{
                .{ .icon = icon },
                .{ .text = try utl.bufPrintLocal(
                    "{d:.0} {s}Damage{s}",
                    .{
                        @floor(amount),
                        dmg_type_string,
                        if (aoe_hits_allies) "\nDamages ALL creatures in the area of effect" else "",
                    },
                ) },
            }),
        );
        // TODO info tooltips (fire..)
        ret.info_tooltips = .{};
        return ret;
    }
    pub fn makeStatus(kind: StatusEffect.Kind, stacks: i32) Error!NewTag {
        var buf: [64]u8 = undefined;
        var ret = NewTag{};
        ret.card_label = try CardLabel.fromSlice(try StatusEffect.fmtShort(&buf, kind, stacks));
        ret.tooltip_label = try TooltipLabel.fromSlice(try StatusEffect.fmtLong(&buf, kind, stacks));
        const info_buf = try StatusEffect.getInfos(&ret.info_tooltips.buffer, kind);
        try ret.info_tooltips.resize(info_buf.len);
        return ret;
    }
};

pub const Tag = struct {
    pub const Array = std.BoundedArray(Tag, 16);
    pub const Label = utl.BoundedString(8);
    pub const Desc = utl.BoundedString(64);
    pub const SpriteEnum = enum {
        target,
        skull,
        mouse,
        wizard,
        lightning,
        fire,
        icicle,
        magic,
        aoe_lightning,
        aoe_fire,
        aoe_ice,
        aoe_magic,
        water,
        arrow_right,
        heart,
        card,
        fast_forward,
        shield_empty,
        sword_hilt,
        droplets,
        arrow_shaft,
        shoes,
        ouchy_skull,
        spiral_yellow,
        doorway,
        monster_with_sword,
        ice_ball,
        arrow_180_CC,
        arrows_opp,
        mana_crystal,
        blood_splat,
        magic_eye,
        ouchy_heart,
        coin,
        wizard_inverse,
        spiky,
        burn,
        trailblaze,
        draw_card,
    };
    pub const Part = union(enum) {
        icon: struct {
            sprite_enum: SpriteEnum,
            tint: Colorf = .white,
        },
        label: Label,
    };
    pub const PartArray = std.BoundedArray(Part, 8);
    pub const height: f32 = 9;

    start_on_new_line: bool = false,
    parts: PartArray = .{},
    desc: Desc = .{},

    pub fn makeArray(grouped_parts: []const []const Spell.Tag.Part) Spell.Tag.Array {
        var ret = Spell.Tag.Array{};
        for (grouped_parts) |parts| {
            ret.appendAssumeCapacity(.{
                .parts = Spell.Tag.PartArray.fromSlice(parts) catch @panic("too many parts"),
            });
        }
        return ret;
    }
    pub fn fmtLabel(comptime fmt: []const u8, args: anytype) Label {
        const str = utl.bufPrintLocal(fmt, args) catch "E:FMT";
        return Label.fromSlice(str) catch Label.fromSlice("E:OVRFLW") catch unreachable;
    }
    pub fn fmtDesc(comptime fmt: []const u8, args: anytype) Desc {
        const str = utl.bufPrintLocal(fmt, args) catch "ERR:FMT";
        return Desc.fromSlice(str) catch Desc.fromSlice("ERR:OVRFLW") catch unreachable;
    }
    pub fn makeTarget(kind: TargetKind) Tag {
        var ret = Tag{
            .start_on_new_line = true,
            .parts = PartArray.fromSlice(&.{
                .{ .icon = .{ .sprite_enum = .target } },
            }) catch unreachable,
        };
        switch (kind) {
            .self => {
                ret.parts.appendAssumeCapacity(.{ .icon = .{ .sprite_enum = .wizard, .tint = .orange } });
                ret.desc = fmtDesc("Target: self", .{});
            },
            .pos => {
                ret.parts.appendAssumeCapacity(.{ .icon = .{ .sprite_enum = .mouse } });
                ret.desc = fmtDesc("Target: point", .{});
            },
            .thing => {
                ret.parts.appendAssumeCapacity(.{ .icon = .{ .sprite_enum = .skull } });
                ret.desc = fmtDesc("Target: creature", .{});
            },
        }
        return ret;
    }
    pub fn makeDamage(kind: Thing.HitEffect.DamageKind, amount: f32, aoe_hits_allies: bool) Tag {
        const sprite: SpriteEnum = switch (kind) {
            .magic => if (aoe_hits_allies) .aoe_magic else .magic,
            .fire => if (aoe_hits_allies) .aoe_fire else .fire,
            .ice => if (aoe_hits_allies) .aoe_ice else .icicle,
            .lightning => if (aoe_hits_allies) .aoe_lightning else .lightning,
            else => .blood_splat,
        };
        return Tag{
            .parts = PartArray.fromSlice(&.{
                .{ .icon = .{ .sprite_enum = sprite } },
                .{ .label = fmtLabel("{d:.0}", .{@floor(amount)}) },
            }) catch unreachable,
            .desc = fmtDesc("Deals {d:.0} {s} damage{s}", .{
                @floor(amount),
                utl.enumToString(Thing.HitEffect.DamageKind, kind),
                if (aoe_hits_allies) ". Careful! Damages ALL creatures in the area of effect" else "",
            }),
        };
    }
    pub fn sEnding(num: i32) []const u8 {
        if (num > 0) {
            return "s";
        }
        return "";
    }
    pub fn makeStatus(kind: StatusEffect.Kind, stacks: i32) Tag {
        const dur_secs = if (StatusEffect.getDurationSeconds(kind, stacks)) |secs_f| utl.as(i32, @floor(secs_f)) else null;
        return switch (kind) {
            .protected => Tag{
                .parts = PartArray.fromSlice(&.{
                    .{ .icon = .{ .sprite_enum = .ouchy_skull, .tint = draw.Coloru.rgb(161, 133, 238).toColorf() } },
                    .{ .label = Spell.Tag.fmtLabel("{} sec{s}", .{ dur_secs.?, sEnding(dur_secs.?) }) },
                }) catch unreachable,
                .desc = fmtDesc("Protected: The next enemy attack is blocked", .{}),
            },
            .frozen => Tag{
                .parts = PartArray.fromSlice(&.{
                    .{ .icon = .{ .sprite_enum = .ice_ball } },
                    .{ .label = Spell.Tag.fmtLabel("{} sec{s}", .{ dur_secs.?, sEnding(dur_secs.?) }) },
                }) catch unreachable,
                .desc = fmtDesc("Frozen: Cannot move or act", .{}),
            },
            .blackmailed => Tag{
                .parts = PartArray.fromSlice(&.{
                    .{ .icon = .{ .sprite_enum = .ouchy_heart, .tint = Colorf.rgb(1, 0.4, 0.6) } },
                    .{ .label = Spell.Tag.fmtLabel("{} sec{s}", .{ dur_secs.?, sEnding(dur_secs.?) }) },
                }) catch unreachable,
                .desc = fmtDesc("Blackmailed: Fights for the blackmailer", .{}),
            },
            .mint => Tag{
                .parts = PartArray.fromSlice(&.{
                    .{ .icon = .{ .sprite_enum = .coin } },
                    .{ .label = Spell.Tag.fmtLabel("{} sec{s}", .{ dur_secs.?, sEnding(dur_secs.?) }) },
                }) catch unreachable,
                .desc = fmtDesc("Mint: On death, drops 1 gold per stack", .{}),
            },
            .promptitude => Tag{
                .parts = PartArray.fromSlice(&.{
                    .{ .icon = .{ .sprite_enum = .fast_forward } },
                    .{ .label = Spell.Tag.fmtLabel("{} sec{s}", .{ dur_secs.?, sEnding(dur_secs.?) }) },
                }) catch unreachable,
                .desc = fmtDesc("Promptitude: Moves and acts at double speed", .{}),
            },
            .exposed => Tag{
                .parts = PartArray.fromSlice(&.{
                    .{ .icon = .{ .sprite_enum = .magic_eye } },
                    .{ .label = Spell.Tag.fmtLabel("{} sec{s}", .{ dur_secs.?, sEnding(dur_secs.?) }) },
                }) catch unreachable,
                .desc = fmtDesc("Exposed: Takes 30% more damage from all sources", .{}),
            },
            .stunned => Tag{
                .parts = PartArray.fromSlice(&.{
                    .{ .icon = .{ .sprite_enum = .spiral_yellow, .tint = draw.Coloru.rgb(255, 235, 147).toColorf() } },
                    .{ .label = Spell.Tag.fmtLabel("{} sec{s}", .{ dur_secs.?, sEnding(dur_secs.?) }) },
                }) catch unreachable,
                .desc = fmtDesc("Stunned: Cannot move or act", .{}),
            },
            .unseeable => Tag{
                .parts = PartArray.fromSlice(&.{
                    .{ .icon = .{ .sprite_enum = .wizard_inverse } },
                    .{ .label = Spell.Tag.fmtLabel("{} sec{s}", .{ dur_secs.?, sEnding(dur_secs.?) }) },
                }) catch unreachable,
                .desc = fmtDesc("Unseeable: Ignored by enemies", .{}),
            },
            .prickly => Tag{
                .parts = PartArray.fromSlice(&.{
                    .{ .icon = .{ .sprite_enum = .spiky } },
                    .{ .label = Spell.Tag.fmtLabel("{} stack{s}", .{ stacks, sEnding(stacks) }) },
                }) catch unreachable,
                .desc = fmtDesc("Prickly: Melee attackers take 1 damage per stack", .{}),
            },
            .lit => Tag{
                .parts = PartArray.fromSlice(&.{
                    .{ .icon = .{ .sprite_enum = .burn } },
                    .{ .label = Spell.Tag.fmtLabel("{} stack{s}", .{ stacks, sEnding(stacks) }) },
                }) catch unreachable,
                .desc = fmtDesc("Aflame: Take {} damage per second.\nRemove 1 stack every {} seconds.\nMax {} stacks", .{
                    stacks,
                    utl.as(i32, @floor(core.fups_to_secsf(StatusEffect.proto_array.get(kind).cooldown.num_ticks))),
                    StatusEffect.proto_array.get(kind).max_stacks,
                }),
            },
            .moist => Tag{
                .parts = PartArray.fromSlice(&.{
                    .{ .icon = .{ .sprite_enum = .wizard_inverse } },
                    .{ .label = Spell.Tag.fmtLabel("{} sec{s}", .{ dur_secs.?, sEnding(dur_secs.?) }) },
                }) catch unreachable,
                .desc = fmtDesc("Moist: Extinguishes \"Aflame\".\nImmune to \"Aflame\"", .{}),
            },
            .trailblaze => Tag{
                .parts = PartArray.fromSlice(&.{
                    .{ .icon = .{ .sprite_enum = .trailblaze } },
                    .{ .label = Spell.Tag.fmtLabel("{} sec{s}", .{ dur_secs.?, sEnding(dur_secs.?) }) },
                }) catch unreachable,
                .desc = fmtDesc("Trailblazin': Moves faster.\nLeaves behind a trail of fire", .{}),
            },
            .quickdraw => Tag{
                .parts = PartArray.fromSlice(&.{
                    .{ .icon = .{ .sprite_enum = .draw_card } },
                    .{ .label = Spell.Tag.fmtLabel("{} stack{s}", .{ stacks, sEnding(stacks) }) },
                }) catch unreachable,
                .desc = fmtDesc("Quickdraw: The next {} spells are drawn instantly", .{stacks}),
            },
        };
    }
};

pub const CastTime = enum {
    slow,
    medium,
    fast,
};

pub const cast_time_to_secs = std.EnumArray(CastTime, f32).init(.{
    .slow = 1.334,
    .medium = 1.0,
    .fast = 0.667,
});

kind: KindData = undefined,
rarity: Rarity = .pedestrian,
obtainableness: Obtainableness.Mask = Obtainableness.Mask.initMany(&.{ .room_reward, .shop }),
obtainable_modes: Run.Mode.Mask = Run.Mode.Mask.initFull(),
color: Colorf = .black,
targeting_data: TargetingData = .{},
cast_time: CastTime,
cast_secs: f32 = 1, // time from spell starting to when it's cast() is called - caster can't move or do anything except buffer inputs
cast_ticks: i32 = 60,
after_cast_slot_cooldown_secs: f32 = 4,
after_cast_slot_cooldown_ticks: i32 = 4 * 60,
mislay: bool = false,
draw_immediate: bool = false,
mana_cost: ManaCost = .{ .number = 1 },

pub fn getSlotCooldownTicks(self: *const Spell) i32 {
    return self.cast_ticks + self.after_cast_slot_cooldown_ticks;
}

pub fn makeProto(kind: Kind, the_rest: Spell) Spell {
    var ret = the_rest;
    ret.kind = @unionInit(KindData, @tagName(kind), .{});
    ret.cast_secs = cast_time_to_secs.get(ret.cast_time);
    ret.cast_ticks = utl.as(i32, core.fups_per_sec_f * ret.cast_secs);
    ret.after_cast_slot_cooldown_ticks = utl.as(i32, core.fups_per_sec_f * ret.after_cast_slot_cooldown_secs);
    return ret;
}

pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
    switch (self.kind) {
        inline else => |k| {
            const K = @TypeOf(k);
            if (std.meta.hasMethod(K, "cast")) {
                try K.cast(self, caster, room, params);
            }
        },
    }
}

pub fn canUse(self: *const Spell, room: *const Room, caster: *const Thing) bool {
    if (caster.mana) |mana| {
        if (self.mana_cost.getActualCost(caster)) |cost| {
            if (mana.curr < cost) return false;
        }
    }
    switch (self.kind) {
        inline else => |k| {
            const K = @TypeOf(k);
            if (std.meta.hasMethod(K, "canUse")) {
                return K.canUse(self, room, caster);
            }
        },
    }
    return true;
}

pub fn getFlavor(self: *const Spell) []const u8 {
    switch (self.kind) {
        inline else => |k| {
            const K = @TypeOf(k);
            if (std.meta.hasMethod(K, "getFlavor")) {
                return K.getFlavor(self);
            }
        },
    }
    return "";
}

pub fn getTags(self: *const Spell) Tag.Array {
    switch (self.kind) {
        inline else => |k| {
            const K = @TypeOf(k);
            if (std.meta.hasMethod(K, "getTags")) {
                return K.getTags(self);
            } else {
                return .{};
            }
        },
    }
}

pub fn getNewTags(self: *const Spell) Error!NewTag.Array {
    switch (self.kind) {
        inline else => |k| {
            const K = @TypeOf(k);
            if (std.meta.hasMethod(K, "getNewTags")) {
                return try K.getNewTags(self);
            } else {
                return .{};
            }
        },
    }
}

const rarity_price_base = std.EnumArray(Rarity, i32).init(.{
    .pedestrian = 7,
    .interesting = 10,
    .exceptional = 15,
    .brilliant = 27,
});

const rarity_price_variance = std.EnumArray(Rarity, i32).init(.{
    .pedestrian = 3,
    .interesting = 5,
    .exceptional = 5,
    .brilliant = 5,
});

pub fn getShopPrice(self: *const Spell, rng: std.Random) i32 {
    const base = rarity_price_base.get(self.rarity);
    const variance = rarity_price_variance.get(self.rarity);
    return base - variance + rng.intRangeAtMost(i32, 0, variance * 2);
}

pub inline fn getTargetParams(self: *const Spell, room: *Room, caster: *const Thing, mouse_pos: V2f) ?Params {
    return self.targeting_data.getParams(room, caster, mouse_pos);
}

pub inline fn renderTargeting(self: *const Spell, room: *const Room, caster: *const Thing, params: ?Params) Error!void {
    return self.targeting_data.render(room, caster, params);
}

pub fn getName(self: *const Spell) []const u8 {
    const kind = std.meta.activeTag(self.kind);
    return spell_names.get(kind);
}

pub fn unqRenderCard(self: *const Spell, cmd_buf: *ImmUI.CmdBuf, pos: V2f, caster: ?*const Thing, scaling: f32) void {
    const data = App.get().data;
    var show_as_disabled = false;
    if (caster) |c|
        if (c.mana) |mana|
            if (self.mana_cost.getActualCost(c)) |cost| {
                show_as_disabled = (cost > mana.curr);
            };

    if (data.card_sprites.getRenderFrame(.card_base)) |rf| {
        cmd_buf.appendAssumeCapacity(.{ .texture = .{
            .pos = pos,
            .texture = rf.texture,
            .opt = .{
                .src_dims = rf.size.toV2f(),
                .src_pos = rf.pos.toV2f(),
                .uniform_scaling = scaling,
            },
        } });
    }
    // art and rarity frame
    const art_topleft = pos.add(card_art_topleft_offset.scale(scaling));
    const rii: sprites.RenderIconInfo = blk: {
        const kind = std.meta.activeTag(self.kind);
        if (data.spell_icons.getRenderFrame(kind)) |render_frame| {
            break :blk .{ .frame = render_frame };
        } else {
            const name = spell_names.get(kind);
            break :blk .{ .letter = .{
                .str = [1]u8{std.ascii.toUpper(name[0])},
                .color = self.color,
            } };
        }
    };
    rii.unqRender(cmd_buf, art_topleft, scaling) catch @panic("failed renderino");
    if (data.card_sprites.getRenderFrame(CardSpriteEnum.fromRarity(self.rarity))) |rf| {
        cmd_buf.appendAssumeCapacity(.{ .texture = .{
            .pos = pos,
            .texture = rf.texture,
            .opt = .{
                .src_dims = rf.size.toV2f(),
                .src_pos = rf.pos.toV2f(),
                .uniform_scaling = scaling,
            },
        } });
    }
    // title
    const title_center_pos = pos.add(card_title_center_offset.scale(scaling));
    const title_font = data.fonts.get(.pixeloid);
    cmd_buf.appendAssumeCapacity(.{ .label = .{
        .pos = title_center_pos,
        .text = ImmUI.initLabel(self.getName()),
        .opt = .{
            .color = .white,
            .size = title_font.base_size * utl.as(u32, scaling),
            .center = true,
            .font = title_font,
            .smoothing = .none,
            .border = .{
                .color = .black,
                .dist = scaling,
            },
        },
    } });
    // mana crystal
    const mana_topleft = pos.add(card_mana_topleft_offset.scale(scaling));
    if (data.card_mana_cost.getRenderFrame(.crystal)) |rf| {
        cmd_buf.appendAssumeCapacity(.{ .texture = .{
            .pos = mana_topleft,
            .texture = rf.texture,
            .opt = .{
                .src_dims = rf.size.toV2f(),
                .src_pos = rf.pos.toV2f(),
                .uniform_scaling = scaling,
            },
        } });
    }
    // mana cost
    if (data.card_mana_cost.getRenderFrame(self.mana_cost.toSpriteEnum())) |rf| {
        const tint: Colorf = if (show_as_disabled) .red else .white;
        cmd_buf.appendAssumeCapacity(.{ .texture = .{
            .pos = mana_topleft,
            .texture = rf.texture,
            .opt = .{
                .src_dims = rf.size.toV2f(),
                .src_pos = rf.pos.toV2f(),
                .uniform_scaling = scaling,
                .tint = tint,
            },
        } });
    }
    // tags
    {
        const tags = self.getTags();
        const tag_topleft = pos.add(card_tags_topleft_offset.scale(scaling));
        var curr_tag_topleft = tag_topleft;
        for (tags.constSlice()) |tag| {
            // first measure
            const tag_dims = measureTag(&tag);
            const tag_dims_scaled = tag_dims.scale(scaling);
            if (curr_tag_topleft.x != tag_topleft.x and (tag.start_on_new_line or curr_tag_topleft.x + tag_dims_scaled.x > tag_topleft.x + card_tags_dims.x * scaling)) {
                curr_tag_topleft.y += tag_dims_scaled.y + (1 * scaling);
                curr_tag_topleft.x = tag_topleft.x;
            }
            // now actually draw
            unqRenderTag(&tag, cmd_buf, curr_tag_topleft, tag_dims, scaling);
            curr_tag_topleft.x += tag_dims_scaled.x + 1 * scaling;
        }
    }
    {
        const tags = self.getNewTags() catch NewTag.Array{};
        const tag_topleft = pos.add(card_tags_topleft_offset.scale(scaling));
        var curr_tag_topleft = tag_topleft;
        for (tags.constSlice()) |tag| {
            // first measure
            const tag_dims = icon_text.measureIconText(tag.card_label.constSlice()).add(v2f(2, 1));
            const tag_dims_scaled = tag_dims.scale(scaling);
            if (curr_tag_topleft.x != tag_topleft.x and (tag.start_on_new_line or curr_tag_topleft.x + tag_dims_scaled.x > tag_topleft.x + card_tags_dims.x * scaling)) {
                curr_tag_topleft.y += tag_dims_scaled.y + (1 * scaling);
                curr_tag_topleft.x = tag_topleft.x;
            }
            // now actually draw
            cmd_buf.appendAssumeCapacity(.{
                .rect = .{
                    .pos = curr_tag_topleft,
                    .dims = tag_dims_scaled,
                    .opt = .{
                        .fill_color = .black,
                        .edge_radius = 0.3,
                    },
                },
            });
            icon_text.unqRenderIconText(
                cmd_buf,
                tag.card_label.constSlice(),
                curr_tag_topleft.add(V2f.splat(1 * scaling)),
                scaling,
                .white,
            ) catch {};
            curr_tag_topleft.x += tag_dims_scaled.x + 1 * scaling;
        }
    }
    // tint disabled
    if (show_as_disabled) {
        if (data.card_sprites.getRenderFrame(.card_blank)) |rf| {
            cmd_buf.appendAssumeCapacity(.{ .texture = .{
                .pos = pos,
                .texture = rf.texture,
                .opt = .{
                    .src_dims = rf.size.toV2f(),
                    .src_pos = rf.pos.toV2f(),
                    .uniform_scaling = scaling,
                    .tint = Colorf.black.fade(0.5),
                },
            } });
        }
    }
}

pub fn measureTag(tag: *const Tag) V2f {
    const plat = getPlat();
    const data = App.get().data;
    const tag_font = data.fonts.get(.seven_x_five);
    const tag_text_opt = draw.TextOpt{
        .color = .white,
        .font = tag_font,
        .size = tag_font.base_size,
        .smoothing = .none,
    };
    var width_x: f32 = 1;
    for (tag.parts.constSlice()) |part| {
        switch (part) {
            .icon => |s| {
                width_x += (data.spell_tags_icons.sprite_dims_cropped.?.get(s.sprite_enum).x + 1);
            },
            .label => |label| {
                const sz = plat.measureText(label.constSlice(), tag_text_opt) catch V2f{};
                width_x += sz.x + 1;
            },
        }
    }

    return v2f(width_x, Tag.height);
}

pub fn unqRenderTag(tag: *const Tag, cmd_buf: *ImmUI.CmdBuf, pos: V2f, bg_dims: ?V2f, scaling: f32) void {
    const plat = getPlat();
    const data = App.get().data;
    const tag_font = data.fonts.get(.seven_x_five);
    const tag_text_opt = draw.TextOpt{
        .color = .white,
        .font = tag_font,
        .size = tag_font.base_size * utl.as(u32, scaling),
        .smoothing = .none,
    };
    if (bg_dims) |dims| {
        cmd_buf.appendAssumeCapacity(.{
            .rect = .{
                .pos = pos,
                .dims = dims.scale(scaling), // TODO put somewhere
                .opt = .{
                    .fill_color = .black,
                    .edge_radius = 0.3,
                },
            },
        });
    }
    var curr_part_topleft = pos.add(V2f.splat(1 * scaling));
    for (tag.parts.constSlice()) |part| {
        switch (part) {
            .icon => |s| {
                const cropped_dims = data.spell_tags_icons.sprite_dims_cropped.?.get(s.sprite_enum);
                if (data.spell_tags_icons.getRenderFrame(s.sprite_enum)) |rf| {
                    cmd_buf.appendAssumeCapacity(.{ .texture = .{
                        .pos = curr_part_topleft,
                        .texture = rf.texture,
                        .opt = .{
                            .src_dims = cropped_dims,
                            .src_pos = rf.pos.toV2f(),
                            .uniform_scaling = scaling,
                            .tint = s.tint,
                        },
                    } });
                }
                curr_part_topleft.x += (cropped_dims.x + 1) * scaling;
            },
            .label => |label| {
                const sz = plat.measureText(label.constSlice(), tag_text_opt) catch V2f{};
                cmd_buf.appendAssumeCapacity(.{ .label = .{
                    .pos = curr_part_topleft,
                    .text = ImmUI.initLabel(label.constSlice()),
                    .opt = tag_text_opt,
                } });
                curr_part_topleft.x += sz.x + 1 * scaling;
            },
        }
    }
}

pub fn unqRenderToolTip(self: *const Spell, cmd_buf: *ImmUI.CmdBuf, pos: V2f) Error!void {
    const scaling: f32 = 3;
    const kind = std.meta.activeTag(self.kind);
    const name = spell_names.get(kind);
    const flavor = self.getFlavor();
    const tags = self.getTags();
    if (tags.len > 0) {
        try unqRenderToolTipWithTags(cmd_buf, pos, name, flavor, &tags, scaling);
    }
    const new_tags = try self.getNewTags();
    if (new_tags.len > 0) {
        try unqRenderToolTipWithNewTags(cmd_buf, pos, name, flavor, &new_tags, 2);
    }
}

pub fn unqRenderToolTipWithTags(cmd_buf: *ImmUI.CmdBuf, pos: V2f, title: []const u8, flavor: []const u8, tags: *const Tag.Array, scaling: f32) Error!void {
    const plat = App.getPlat();
    const data = App.get().data;

    const title_font = data.fonts.get(.pixeloid);
    const title_opt = draw.TextOpt{
        .color = .white,
        .size = title_font.base_size * utl.as(u32, scaling),
        .font = title_font,
        .smoothing = .none,
    };
    const title_dims = try plat.measureText(title, title_opt);
    const flavor_opt = draw.TextOpt{
        .color = .white,
        .size = title_font.base_size * utl.as(u32, scaling),
        .font = title_font,
        .smoothing = .none,
    };
    const tag_desc_font = data.fonts.get(.seven_x_five);
    const tag_desc_opt = draw.TextOpt{
        .color = .white,
        .size = tag_desc_font.base_size * utl.as(u32, scaling),
        .font = tag_desc_font,
        .smoothing = .none,
    };
    const flavor_dims = try plat.measureText(flavor, flavor_opt);
    var tag_desc_dimses = std.BoundedArray(V2f, (Tag.Array{}).buffer.len){};
    // measure le tags
    var total_tags_dims = V2f{};
    for (tags.constSlice()) |tag| {
        // first measure
        const tag_dims = measureTag(&tag);
        const tag_dims_scaled = tag_dims.scale(scaling);
        const tag_desc_dims = try plat.measureText(tag.desc.constSlice(), tag_desc_opt);
        tag_desc_dimses.appendAssumeCapacity(tag_desc_dims);

        total_tags_dims.y += tag_dims_scaled.y + tag_desc_dims.y + 2 * scaling;
        total_tags_dims.x = @max(@max(total_tags_dims.x, tag_dims_scaled.x), tag_desc_dims.x);
    }
    const content_dims = v2f(
        @max(@max(title_dims.x, flavor_dims.x), total_tags_dims.x),
        title_dims.y + total_tags_dims.y + flavor_dims.y + 2 * scaling,
    );
    const modal_dims = content_dims.add(v2f(4, 4).scale(scaling));

    var adjusted_pos = pos;
    const bot_right = adjusted_pos.add(modal_dims);
    const native_cropped_rect_bot_right = plat.native_rect_cropped_offset.add(plat.native_rect_cropped_dims);
    if (bot_right.x > native_cropped_rect_bot_right.x) {
        adjusted_pos.x -= (bot_right.x - native_cropped_rect_bot_right.x);
    }
    if (bot_right.y > native_cropped_rect_bot_right.y) {
        adjusted_pos.y -= (bot_right.y - native_cropped_rect_bot_right.y);
    }
    adjusted_pos = adjusted_pos.floor();

    try cmd_buf.append(.{ .rect = .{
        .pos = adjusted_pos,
        .dims = modal_dims,
        .opt = .{
            .fill_color = Colorf.black.fade(0.9),
            .edge_radius = 0.2,
        },
    } });

    var content_curr_pos = adjusted_pos.add(v2f(2, 2).scale(scaling));
    try (cmd_buf.append(.{ .label = .{
        .pos = content_curr_pos,
        .text = ImmUI.initLabel(title),
        .opt = title_opt,
    } }));
    content_curr_pos.y += title_dims.y + 1 * scaling;

    for (tags.constSlice(), 0..) |*tag, i| {
        unqRenderTag(tag, cmd_buf, content_curr_pos, null, scaling);
        content_curr_pos.y += (Tag.height + 1) * scaling;
        try (cmd_buf.append(.{ .label = .{
            .pos = content_curr_pos,
            .text = ImmUI.initLabel(tag.desc.constSlice()),
            .opt = flavor_opt,
        } }));
        content_curr_pos.y += tag_desc_dimses.get(i).y + 1 * scaling;
    }

    try (cmd_buf.append(.{ .label = .{
        .pos = content_curr_pos,
        .text = ImmUI.initLabel(flavor),
        .opt = flavor_opt,
    } }));
}

pub fn unqRenderToolTipWithNewTags(cmd_buf: *ImmUI.CmdBuf, pos: V2f, title: []const u8, flavor: []const u8, tags: *const NewTag.Array, scaling: f32) Error!void {
    const plat = App.getPlat();
    const data = App.get().data;
    const padding = V2f.splat(10);
    const section_spacing: f32 = 10;
    const tag_line_spacing: f32 = 8;
    const info_tooltip_spacing: f32 = 0;
    var all_tag_infos = NewTag.InfoArr{};
    for (tags.constSlice()) |tag| {
        loop: for (tag.info_tooltips.constSlice()) |new_info| {
            for (all_tag_infos.constSlice()) |info| {
                if (info.eql(new_info)) {
                    continue :loop;
                }
            }
            try all_tag_infos.append(new_info);
        }
    }

    const title_font = data.fonts.get(.pixeloid);
    const title_opt = draw.TextOpt{
        .color = .white,
        .size = title_font.base_size * utl.as(u32, scaling + 1),
        .font = title_font,
        .smoothing = .none,
    };
    const title_dims = try plat.measureText(title, title_opt);
    const flavor_opt = draw.TextOpt{
        .color = .white,
        .size = title_font.base_size * utl.as(u32, scaling),
        .font = title_font,
        .smoothing = .none,
    };
    const flavor_dims = try plat.measureText(flavor, flavor_opt);
    // measure le infos
    var tag_dimses = std.BoundedArray(V2f, (NewTag.Array{}).buffer.len){};
    var total_tags_dims = V2f{};
    for (tags.constSlice()) |tag| {
        const tag_dims = icon_text.measureIconText(tag.tooltip_label.constSlice());
        const tag_dims_scaled = tag_dims.scale(scaling);
        tag_dimses.appendAssumeCapacity(tag_dims_scaled);

        total_tags_dims.y += tag_dims_scaled.y;
        total_tags_dims.x = @max(total_tags_dims.x, tag_dims_scaled.x);
    }
    total_tags_dims.y += tag_line_spacing * @max(utl.as(f32, tag_dimses.len) - 1, 0);

    const main_content_dims = v2f(
        @max(@max(title_dims.x, flavor_dims.x), total_tags_dims.x),
        title_dims.y + total_tags_dims.y + flavor_dims.y + 2 * section_spacing,
    );
    const main_tooltip_dims = main_content_dims.add(padding.scale(2));

    // measure le infos
    var infos_dimses = std.BoundedArray(V2f, (NewTag.InfoArr{}).buffer.len){};
    var total_infos_dims = V2f{};
    for (all_tag_infos.constSlice()) |*info| {
        const info_dims = tooltip.measureToolTipContent(info);
        const info_dims_scaled = info_dims.scale(scaling);
        infos_dimses.appendAssumeCapacity(info_dims_scaled);

        total_infos_dims.y += info_dims_scaled.y + tooltip.tooltip_padding.y * 2;
        total_infos_dims.x = @max(total_infos_dims.x, info_dims_scaled.x);
    }
    total_infos_dims.y += info_tooltip_spacing * @max(utl.as(f32, infos_dimses.len) - 1, 0);
    total_infos_dims.x += tooltip.tooltip_padding.x * 2;

    const entire_everything_dims = v2f(
        @max(main_tooltip_dims.x, total_infos_dims.x),
        main_tooltip_dims.y + if (infos_dimses.len > 0) info_tooltip_spacing + total_infos_dims.y else 0,
    );

    var adjusted_pos = pos;
    const bot_right = adjusted_pos.add(entire_everything_dims);
    const native_cropped_rect_bot_right = plat.native_rect_cropped_offset.add(plat.native_rect_cropped_dims);
    if (bot_right.x > native_cropped_rect_bot_right.x) {
        adjusted_pos.x -= (bot_right.x - native_cropped_rect_bot_right.x);
    }
    if (bot_right.y > native_cropped_rect_bot_right.y) {
        adjusted_pos.y -= (bot_right.y - native_cropped_rect_bot_right.y);
    }
    adjusted_pos = adjusted_pos.floor();

    // now drawawwwww
    // main tooltip
    try cmd_buf.append(.{ .rect = .{
        .pos = adjusted_pos,
        .dims = main_tooltip_dims,
        .opt = .{
            .fill_color = Colorf.black.fade(0.9),
            .edge_radius = 0.2,
        },
    } });

    var content_curr_pos = adjusted_pos.add(padding);
    try (cmd_buf.append(.{ .label = .{
        .pos = content_curr_pos,
        .text = ImmUI.initLabel(title),
        .opt = title_opt,
    } }));
    content_curr_pos.y += title_dims.y + section_spacing;

    try (cmd_buf.append(.{ .label = .{
        .pos = content_curr_pos,
        .text = ImmUI.initLabel(flavor),
        .opt = flavor_opt,
    } }));
    content_curr_pos.y += flavor_dims.y + section_spacing;

    for (tags.constSlice(), 0..) |*tag, i| {
        icon_text.unqRenderIconText(cmd_buf, tag.tooltip_label.constSlice(), content_curr_pos, scaling, .white) catch {};
        content_curr_pos.y += tag_dimses.get(i).y + tag_line_spacing;
    }

    var info_tooltip_pos = adjusted_pos.add(v2f(0, main_tooltip_dims.y + info_tooltip_spacing));
    for (all_tag_infos.constSlice(), 0..) |*info, i| {
        tooltip.unqRenderToolTip(info, cmd_buf, info_tooltip_pos, scaling) catch {};
        info_tooltip_pos.y += infos_dimses.get(i).y + info_tooltip_spacing;
    }
}
