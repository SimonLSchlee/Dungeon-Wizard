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

const Spell = @This();

pub const Pool = pool.BoundedPool(Spell, 32);
pub const Id = pool.Id;

pub const SpellTypes = [_]type{
    @import("spells/Unherring.zig"),
    @import("spells/Protec.zig"),
    @import("spells/FrostVom.zig"),
    @import("spells/Blackmail.zig"),
    @import("spells/Mint.zig"),
    @import("spells/Impling.zig"),
    @import("spells/Promptitude.zig"),
    @import("spells/FlameyExplodey.zig"),
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
    target: union(TargetKind) {
        self,
        thing: Thing.Id,
        pos: V2f,
    },
};

pub const TargetingData = struct {
    kind: TargetKind = .self,
    color: Colorf = .cyan,
    fixed_range: bool = false,
    max_range: f32 = 999999,
    ray_to_mouse: ?struct {
        thickness: f32 = 1,
    } = null,
    target_faction_mask: Thing.Faction.Mask = .{},
    target_mouse_pos: bool = false,
    radius_under_mouse: ?f32 = null,
    cone_from_self_to_mouse: ?struct {
        radius: f32,
        radians: f32,
    } = null,

    pub fn getParams(targeting_data: *const TargetingData, room: *Room, caster: *const Thing, mouse_pos: V2f) ?Params {
        switch (targeting_data.kind) {
            .pos => {
                const caster_to_mouse = mouse_pos.sub(caster.pos);
                const target_dir = if (caster_to_mouse.normalizedChecked()) |d| d else V2f.right;
                const mouse_pos_dist = if (targeting_data.fixed_range) targeting_data.max_range else @min(targeting_data.max_range, caster_to_mouse.length());
                const target_pos = caster.pos.add(target_dir.scale(mouse_pos_dist));
                return .{
                    .target = .{ .pos = target_pos },
                    .face_dir = target_pos.sub(caster.pos).normalizedChecked() orelse caster.dir,
                };
            },
            .self => {
                return .{
                    .target = .self,
                };
            },
            .thing => {
                // TODO is it bad if moused_over_thing blocks selecting a valid target?
                if (room.moused_over_thing) |id| {
                    if (room.getThingById(id)) |thing| {
                        if (targeting_data.target_faction_mask.contains(thing.faction)) {
                            return .{
                                .target = .{ .thing = thing.id },
                                .face_dir = thing.pos.sub(caster.pos).normalizedChecked() orelse caster.dir,
                            };
                        }
                    }
                }
            },
        }
        return null;
    }

    pub fn render(targeting_data: *const TargetingData, room: *const Room, caster: *const Thing) Error!void {
        const plat = App.getPlat();
        const mouse_pos = plat.screenPosToCamPos(room.camera, plat.input_buffer.getCurrMousePos());

        switch (targeting_data.kind) {
            .pos => {
                const caster_to_mouse = mouse_pos.sub(caster.pos);
                const target_dir = if (caster_to_mouse.normalizedChecked()) |d| d else V2f.right;
                const mouse_pos_dist = if (targeting_data.fixed_range) targeting_data.max_range else @min(targeting_data.max_range, caster_to_mouse.length());
                var target_hit_pos = caster.pos.add(target_dir.scale(mouse_pos_dist));
                var target_circle_pos = target_hit_pos;
                if (targeting_data.ray_to_mouse) |ray| {
                    const ray_radius = ray.thickness * 0.5;
                    var coll: ?Collision = null;
                    if (caster_to_mouse.lengthSquared() > 0.001) {
                        coll = Collision.getNextSweptCircleCollision(caster.pos, caster_to_mouse, ray_radius, Collision.Mask.initFull(), &.{caster.id}, room);
                        if (coll) |c| {
                            target_hit_pos = c.pos;
                            target_circle_pos = c.pos.add(c.normal.scale(ray_radius));
                        }
                    }
                    plat.linef(caster.pos, target_circle_pos, ray.thickness, targeting_data.color);
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
                if (targeting_data.radius_under_mouse) |r| {
                    plat.circlef(target_circle_pos, r, .{ .fill_color = targeting_data.color.fade(0.4) });
                }
                if (targeting_data.target_mouse_pos) {
                    plat.circlef(target_circle_pos, 10, .{ .fill_color = targeting_data.color.fade(0.4) });
                }
            },
            .self => {
                const draw_radius = caster.selectable.?.radius;
                plat.circlef(caster.pos, draw_radius, .{ .fill_color = targeting_data.color.fade(0.4) });
            },
            .thing => {
                for (&room.things.items) |*thing| {
                    if (!thing.isActive()) continue;
                    if (thing.selectable == null) continue;
                    if (!targeting_data.target_faction_mask.contains(thing.faction)) continue;
                    const selectable = thing.selectable.?;
                    const draw_radius = if (mouse_pos.dist(thing.pos) < selectable.radius) selectable.radius else selectable.radius - 10;
                    plat.circlef(thing.pos, draw_radius, .{ .fill_color = targeting_data.color.fade(0.5) });
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

pub const Reward = struct {
    pub const base_spell_rewards: usize = 3;
    spells: std.BoundedArray(Spell, 8) = .{},
    selected_idx: ?i32 = null,

    pub fn init(rng: std.Random) Reward {
        var ret = Reward{};
        var spell_pool = SpellArray{};
        spell_pool.insertSlice(0, &all_spells) catch unreachable;
        for (0..base_spell_rewards) |_| {
            const weights = getSpellWeights(spell_pool.constSlice());
            const idx = rng.weightedIndex(f32, weights.constSlice());
            const spell = spell_pool.swapRemove(idx);
            ret.spells.append(spell) catch unreachable;
        }
        return ret;
    }
};

pub const BufferedSpell = struct {
    spell: Spell,
    params: Params,
    slot_idx: i32,
};

// only valid if spawn_state == .card
id: Id = undefined,
alloc_state: pool.AllocState = undefined,
//
spawn_state: enum {
    instance, // not in any pool
    card, // a card allocated in a pool
} = .instance,
kind: KindData = undefined,
rarity: Rarity = .pedestrian,
cast_time: i32 = 1,
cast_time_ticks: i32 = 30,
color: Colorf = .black,
targeting_data: TargetingData = .{},

pub fn makeProto(kind: Kind, the_rest: Spell) Spell {
    var ret = the_rest;
    ret.kind = @unionInit(KindData, @tagName(kind), .{});
    ret.cast_time_ticks = 30 * ret.cast_time;
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

pub inline fn getTargetParams(self: *const Spell, room: *Room, caster: *const Thing, mouse_pos: V2f) ?Params {
    return self.targeting_data.getParams(room, caster, mouse_pos);
}

pub inline fn renderTargeting(self: *const Spell, room: *const Room, caster: *const Thing) Error!void {
    return self.targeting_data.render(room, caster);
}

pub fn textInRect(topleft: V2f, dims: V2f, rect_opt: draw.PolyOpt, text_padding: V2f, comptime fmt: []const u8, args: anytype, text_opt: draw.TextOpt) Error!void {
    const plat = App.getPlat();
    const half_dims = dims.scale(0.5);
    const text_rel_pos = if (text_opt.center) half_dims else text_padding;
    const text_dims = dims.sub(text_padding.scale(2));
    assert(text_dims.x > 0 and text_dims.y > 0);
    const text = try utl.bufPrintLocal(fmt, args);
    const fitted_text_opt = try plat.fitTextToRect(text_dims, text, text_opt);
    plat.rectf(topleft, dims, rect_opt);
    try plat.textf(topleft.add(text_rel_pos), fmt, args, fitted_text_opt);
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

pub fn renderInfo(self: *const Spell, rect: menuUI.ClickableRect) Error!void {
    const plat = App.getPlat();
    const title_rect_dims = v2f(rect.dims.x, rect.dims.y * 0.2);
    const icon_rect_dims = v2f(rect.dims.x, rect.dims.y * 0.4);
    const description_dims = v2f(rect.dims.x, rect.dims.y * 0.4);

    const kind = std.meta.activeTag(self.kind);
    const name = spell_names.get(kind);

    plat.rectf(rect.pos, rect.dims, .{ .fill_color = .darkgray });
    try menuUI.textInRect(rect.pos, title_rect_dims, .{ .fill_color = null }, v2f(5, 5), "{s}", .{name}, .{ .color = .white });

    const icon_center_pos = rect.pos.add(v2f(0, title_rect_dims.y)).add(icon_rect_dims.scale(0.5));
    // spell image
    plat.rectf(icon_center_pos.sub(icon_rect_dims.scale(0.5)), icon_rect_dims, .{ .fill_color = .black });
    const icon_square_dim = @min(icon_rect_dims.x, icon_rect_dims.y);
    const icon_square = V2f.splat(icon_square_dim);

    switch (self.getRenderIconInfo()) {
        .frame => |frame| {
            plat.texturef(icon_center_pos, frame.texture, .{
                .origin = .center,
                .src_pos = frame.pos.toV2f(),
                .src_dims = frame.size.toV2f(),
                .scaled_dims = icon_square,
            });
        },
        .letter => |letter| {
            try plat.textf(
                icon_center_pos,
                "{s}",
                .{&letter.str},
                .{
                    .color = letter.color,
                    .size = 40,
                    .center = true,
                },
            );
        },
    }
    const description_text = spell_descriptions.get(kind);
    const description_rect_topleft = rect.pos.add(v2f(0, title_rect_dims.y + icon_rect_dims.y));
    try menuUI.textInRect(description_rect_topleft, description_dims, .{ .fill_color = null }, v2f(10, 10), "{s}", .{description_text}, .{ .color = .white });
}
