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
const data = @import("data.zig");
const pool = @import("pool.zig");

const Spell = @This();

pub const Pool = pool.BoundedPool(Spell, 32);
pub const Id = pool.Id;

pub const SpellImports = [_]type{
    @import("spells/Unherring.zig"),
    @import("spells/Protec.zig"),
};

// uses SpellImports to make enum members with names from field: enum_name
pub const Kind = blk: {
    const EnumField = std.builtin.Type.EnumField;
    const empty = EnumField{
        .name = "",
        .value = 0,
    };
    var fields: [SpellImports.len]EnumField = [_]EnumField{empty} ** SpellImports.len;
    for (SpellImports, 0..) |M, i| {
        fields[i] = .{
            .name = M.enum_name,
            .value = i,
        };
    }
    break :blk @Type(.{
        .@"enum" = .{
            .tag_type = u32,
            .fields = &fields,
            .decls = &.{},
            .is_exhaustive = true,
        },
    });
};

// maps Kind enum to spell type
pub const KindData = blk: {
    const UnionField = std.builtin.Type.UnionField;
    const empty = UnionField{
        .name = "",
        .type = void,
        .alignment = 1,
    };
    var fields: [SpellImports.len]UnionField = [_]UnionField{empty} ** SpellImports.len;
    for (SpellImports, 0..) |M, i| {
        fields[i] = .{
            .name = M.enum_name,
            .type = M,
            .alignment = @alignOf(M),
        };
    }
    break :blk @Type(.{
        .@"union" = .{
            .layout = .auto,
            .tag_type = Kind,
            .fields = &fields,
            .decls = &.{},
        },
    });
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
    target: union(TargetKind) {
        self,
        thing: Thing.Id,
        pos: V2f,
    },
};

pub const TargetingData = struct {
    kind: TargetKind = .self,
    color: Colorf = .blue,
    line_to_mouse: bool = false,
    target_enemy: bool = false,
    target_ally: bool = false,
    target_mouse_pos: bool = false,
    radius_under_mouse: ?f32 = null,
    cone_from_self_to_mouse: ?struct {
        radius: f32,
        radians: f32,
    } = null,
};

pub const ThingData = struct {
    spell: Spell,
    params: Params,

    pub fn render(self: *const Thing, room: *const Room) Error!void {
        try self.defaultRender(room);
    }

    pub fn update(self: *Thing, room: *Room) Error!void {
        const spell_data = self.kind.spell;
        switch (spell_data.spell.kind) {
            inline else => |s| try @TypeOf(s).update(self, room),
        }
    }
};

pub fn makeProto(kind: Kind, the_rest: Spell) Spell {
    var ret = the_rest;
    ret.kind = @unionInit(KindData, @tagName(kind), .{});
    ret.cast_time_ticks = 30 * ret.cast_time;
    return ret;
}

// TODO move these spells to own files
pub const FrostVom = struct {
    pub const proto: Spell = makeProto(
        .frostvom,
        .{
            .cast_time = 2,
            .color = .blue,
            .targeting_data = .{
                .kind = .pos,
                .cone_from_self_to_mouse = true,
            },
        },
    );
    pub fn render(self: *const Thing, room: *const Room) Error!void {
        _ = self;
        _ = room;
    }
    pub fn update(self: *Thing, room: *Room) Error!void {
        _ = self;
        _ = room;
    }
    pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
        _ = self;
        _ = caster;
        _ = room;
        _ = params;
    }
};

pub const Mint = struct {
    pub const proto: Spell = makeProto(
        .mint,
        .{
            .color = .red,
            .targeting_data = .{
                .kind = .pos,
                .line_to_mouse = true,
            },
        },
    );
    pub fn render(self: *const Thing, room: *const Room) Error!void {
        _ = self;
        _ = room;
    }
    pub fn update(self: *Thing, room: *Room) Error!void {
        _ = self;
        _ = room;
    }
    pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
        _ = self;
        _ = caster;
        _ = room;
        _ = params;
    }
};

pub const Impling = struct {
    pub const proto: Spell = makeProto(
        .impling,
        .{
            .cast_time = 2,
            .color = .red,
            .targeting_data = .{
                .kind = .pos,
                .target_mouse_pos = true,
            },
        },
    );
    pub fn render(self: *const Thing, room: *const Room) Error!void {
        _ = self;
        _ = room;
    }
    pub fn update(self: *Thing, room: *Room) Error!void {
        _ = self;
        _ = room;
    }
    pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
        _ = self;
        _ = caster;
        _ = room;
        _ = params;
    }
};

pub const Promptitude = struct {
    pub const proto: Spell = makeProto(
        .promptitude,
        .{
            .cast_time = 2,
            .color = .red,
            .targeting_data = .{
                .kind = .self,
            },
        },
    );
    pub fn render(self: *const Thing, room: *const Room) Error!void {
        _ = self;
        _ = room;
    }
    pub fn update(self: *Thing, room: *Room) Error!void {
        _ = self;
        _ = room;
    }
    pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
        _ = self;
        _ = caster;
        _ = room;
        _ = params;
    }
};

pub const FlameExplode = struct {
    pub const proto: Spell = makeProto(
        .flameexplode,
        .{
            .cast_time = 2,
            .color = .red,
            .targeting_data = .{
                .kind = .pos,
                .line_to_mouse = true,
                .radius_under_mouse = 100,
            },
        },
    );

    direct_hit_damage: f32 = 20,
    aoe_damage: f32 = 50,

    pub fn render(self: *const Thing, room: *const Room) Error!void {
        _ = self;
        _ = room;
    }
    pub fn update(self: *Thing, room: *Room) Error!void {
        _ = self;
        _ = room;
    }
    pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
        _ = self;
        _ = caster;
        _ = room;
        _ = params;
    }
};

pub const Blackmail = struct {
    pub const proto: Spell = makeProto(
        .blackmail,
        .{
            .cast_time = 2,
            .color = .red,
            .targeting_data = .{
                .kind = .thing,
                .target_enemy = true,
            },
        },
    );

    pub fn render(self: *const Thing, room: *const Room) Error!void {
        _ = self;
        _ = room;
    }
    pub fn update(self: *Thing, room: *Room) Error!void {
        _ = self;
        _ = room;
    }
    pub fn cast(self: *const Spell, caster: *Thing, room: *Room, params: Params) Error!void {
        _ = self;
        _ = caster;
        _ = room;
        _ = params;
    }
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
cast_time: i8 = 1,
cast_time_ticks: i64 = 30,
color: Colorf = .black,
targeting_data: TargetingData = .{},

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
