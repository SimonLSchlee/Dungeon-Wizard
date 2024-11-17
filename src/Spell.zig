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

pub const SpellTypes = [_]type{
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
const spell_descriptions = blk: {
    var ret: std.EnumArray(Kind, []const u8) = undefined;
    for (std.meta.fields(Kind)) |f| {
        const kind: Kind = @enumFromInt(f.value);
        const T = GetKindType(kind);
        ret.set(kind, T.description);
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

pub const TargetKind = enum {
    self,
    thing,
    pos,
};

pub const Params = struct {
    face_dir: ?V2f = null,
    cast_orig: ?V2f = null,
    target: union(TargetKind) {
        self,
        thing: Thing.Id,
        pos: V2f,
    },
};

pub const TargetingData = struct {
    pub const Ray = struct {
        ends_at_coll_mask: Collision.Mask = Collision.Mask.initEmpty(),
        thickness: f32 = 1,
        cast_orig_dist: f32 = 0,
    };
    kind: TargetKind = .self,
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
                    .target = .{ .pos = target_pos },
                    .face_dir = target_pos.sub(caster.pos).normalizedChecked() orelse caster.dir,
                };
                if (targeting_data.ray_to_mouse) |ray| {
                    const cast_orig = caster.pos.add(target_dir.scale(ray.cast_orig_dist));
                    if (target_pos.sub(cast_orig).dot(target_dir) < 0) {
                        ret.target.pos = cast_orig;
                    }
                    ret.cast_orig = cast_orig;
                }
                return ret;
            },
            .self => {
                return .{
                    .target = .self,
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
                            .target = .{ .thing = thing.id },
                            .face_dir = thing.pos.sub(caster.pos).normalizedChecked() orelse caster.dir,
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
                plat.circlef(caster.pos, targeting_data.max_range + caster.coll_radius, .{ .outline_color = targeting_data.color.fade(0.5), .fill_color = null });
            }
        }

        switch (targeting_data.kind) {
            .pos => {
                const mouse_pos = if (params) |p| p.target.pos else plat.getMousePosWorld(room.camera);
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
                    plat.linef(cast_orig, target_circle_pos, ray.thickness, targeting_data.color);
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
                    room.getConstThingById(p.target.thing)
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
                                    .outline_color = Colorf.red.fade(0.6),
                                    .outline_thickness = 3,
                                });
                            }
                        }
                        if (targeting_data.radius_at_target) |r| {
                            plat.circlef(caster.pos, r, .{ .fill_color = targeting_color.fade(0.4) });
                        }
                        if (targeting_data.ray_to_mouse) |ray| {
                            const ray_radius = ray.thickness * 0.5;
                            plat.linef(caster.pos, thing.pos, ray.thickness, targeting_color);
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
            for (M.Controllers) |_| {
                num += 1;
            }
        }
        var Types: [num]type = undefined;
        var i = 0;
        for (SpellTypes) |M| {
            for (M.Controllers) |C| {
                Types[i] = C;
                i += 1;
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

pub fn generateRandom(rng: std.Random, mask: Obtainableness.Mask, allow_duplicates: bool, buf: []Spell) usize {
    var num: usize = 0;
    var spell_pool = SpellArray{};
    for (all_spells) |spell| {
        if (spell.obtainableness.intersectWith(mask).count() > 0) {
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

pub fn makeRoomReward(rng: std.Random, buf: []Spell) usize {
    return generateRandom(rng, Obtainableness.Mask.initOne(.room_reward), false, buf);
}

pub fn makeShopSpells(rng: std.Random, buf: []Spell) usize {
    return generateRandom(rng, Obtainableness.Mask.initOne(.shop), false, buf);
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

pub const Tag = struct {
    pub const Array = std.BoundedArray(Tag, 16);
    pub const Label = utl.BoundedString(8);
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
        spiral,
        doorway,
        monster_with_sword,
        ice_ball,
        arrow_180_CC,
    };
    pub const Part = union(enum) {
        icon: struct {
            sprite_enum: SpriteEnum,
            tint: Colorf = .white,
        },
        label: Label,
    };
    pub const PartArray = std.BoundedArray(Part, 6);

    parts: PartArray = .{},

    pub fn makeArray(grouped_parts: []const []const Spell.Tag.Part) Spell.Tag.Array {
        var ret = Spell.Tag.Array{};
        for (grouped_parts) |parts| {
            ret.appendAssumeCapacity(.{ .parts = utl.initBoundedArray(Spell.Tag.PartArray, parts) });
        }
        return ret;
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
tags: Tag.Array = .{},

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

pub fn getDescription(self: *const Spell) Error![]const u8 {
    var len: usize = 0;
    var buf = desc_buf[0..];
    len += (try std.fmt.bufPrint(
        buf,
        "Cast time: {s} ({d:.2} secs)\nSlot cooldown: {d:.1} secs\n{s}",
        .{
            @tagName(self.cast_time),
            self.cast_secs,
            core.fups_to_secsf(self.getSlotCooldownTicks()),
            if (self.mislay) "Mislay: Only use once per room\n" else "",
        },
    )).len;
    len += (try self.targeting_data.fmtDesc(buf[len..])).len;
    const b = blk: switch (self.kind) {
        inline else => |k| {
            const K = @TypeOf(k);
            if (std.meta.hasMethod(K, "getDescription")) {
                break :blk try K.getDescription(self, buf[len..]);
            } else {
                break :blk try std.fmt.bufPrint(buf, "{s}", .{spell_descriptions.get(std.meta.activeTag(self.kind))});
            }
        },
    };
    len += b.len;
    return buf[0..len];
}

pub fn getTags(self: *const Spell) ?Tag.Array {
    switch (self.kind) {
        inline else => |k| {
            const K = @TypeOf(k);
            if (std.meta.hasMethod(K, "getTags")) {
                return K.getTags(self);
            }
        },
    }
    return null;
}

pub inline fn getTargetParams(self: *const Spell, room: *Room, caster: *const Thing, mouse_pos: V2f) ?Params {
    return self.targeting_data.getParams(room, caster, mouse_pos);
}

pub inline fn renderTargeting(self: *const Spell, room: *const Room, caster: *const Thing, params: ?Params) Error!void {
    return self.targeting_data.render(room, caster, params);
}

pub inline fn renderIcon(self: *const Spell, rect: geom.Rectf) Error!void {
    return try self.getRenderIconInfo().render(rect);
}

pub inline fn unqRenderIcon(self: *const Spell, cmd_buf: *ImmUI.CmdBuf, rect: geom.Rectf) Error!void {
    return try self.getRenderIconInfo().unqRender(cmd_buf, rect);
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
        if (data.spell_icons_2.getRenderFrame(kind)) |render_frame| {
            break :blk .{ .frame = render_frame };
        } else {
            const name = spell_names.get(kind);
            break :blk .{ .letter = .{
                .str = [1]u8{std.ascii.toUpper(name[0])},
                .color = self.color,
            } };
        }
    };
    rii.unqRender(cmd_buf, .{ .pos = art_topleft, .dims = card_art_dims.scale(scaling) }) catch @panic("failed renderino");
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
        .text = ImmUI.Command.LabelString.initTrunc(self.getName()),
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
    if (self.getTags()) |tags| {
        const plat = getPlat();
        const tag_font = data.fonts.get(.seven_x_five);
        const tag_text_opt = draw.TextOpt{
            .color = .white,
            .font = tag_font,
            .size = tag_font.base_size * utl.as(u32, scaling),
            .smoothing = .none,
        };
        const tag_topleft = pos.add(card_tags_topleft_offset.scale(scaling));
        var curr_tag_topleft = tag_topleft;
        for (tags.constSlice()) |tag| {
            // first measure
            var width_x: f32 = 1 * scaling;
            for (tag.parts.constSlice()) |part| {
                switch (part) {
                    .icon => |s| {
                        width_x += (data.spell_tags_icons.sprite_dims_cropped.?.get(s.sprite_enum).x + 1) * scaling;
                    },
                    .label => |label| {
                        const sz = plat.measureText(label.constSlice(), tag_text_opt) catch V2f{};
                        width_x += sz.x + 1 * scaling;
                    },
                }
            }
            if (curr_tag_topleft.x != tag_topleft.x and curr_tag_topleft.x + width_x > tag_topleft.x + card_tags_dims.x * scaling) {
                curr_tag_topleft.y += (9 + 1) * scaling; // TODO put somewhere
                curr_tag_topleft.x = tag_topleft.x;
            }
            // now actually draw
            cmd_buf.appendAssumeCapacity(.{
                .rect = .{
                    .pos = curr_tag_topleft,
                    .dims = v2f(width_x, 9 * scaling), // TODO put somewhere
                    .opt = .{
                        .fill_color = .black,
                        .edge_radius = 0.3,
                    },
                },
            });
            var curr_part_topleft = curr_tag_topleft.add(V2f.splat(1 * scaling));
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
                            .text = ImmUI.Command.LabelString.initTrunc(label.constSlice()),
                            .opt = tag_text_opt,
                        } });
                        curr_part_topleft.x += sz.x + 1 * scaling;
                    },
                }
            }
            curr_tag_topleft.x += width_x + 1 * scaling;
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

pub fn getRenderIconInfo(self: *const Spell) sprites.RenderIconInfo {
    const data = App.get().data;
    const kind = std.meta.activeTag(self.kind);
    if (data.spell_icons.getRenderFrame(kind)) |render_frame| {
        return .{ .frame = render_frame };
    } else {
        const name = spell_names.get(kind);
        return .{ .letter = .{
            .str = [1]u8{std.ascii.toUpper(name[0])},
            .color = self.color,
        } };
    }
}

pub fn renderToolTip(self: *const Spell, pos: V2f) Error!void {
    const kind = std.meta.activeTag(self.kind);
    const name = spell_names.get(kind);
    const desc = try self.getDescription();
    return menuUI.renderToolTip(name, desc, pos);
}
