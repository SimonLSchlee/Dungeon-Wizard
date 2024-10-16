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
const Spell = @import("Spell.zig");
const Params = Spell.Params;
const TargetKind = Spell.TargetKind;
const TargetingData = Spell.TargetingData;

const Item = @This();

pub const Pool = pool.BoundedPool(Item, 32);
pub const Id = pool.Id;

pub const PotionHP = struct {
    pub const title = "Hp Potion";
    pub const description =
        \\Restore 30 HP instantly (self only).
    ;

    pub const enum_name = "pot_hp";
    pub const Controllers = [_]type{};

    pub const proto = Item.makeProto(
        std.meta.stringToEnum(Item.Kind, enum_name).?,
        .{
            .color = .green,
            .targeting_data = .{
                .kind = .self,
            },
        },
    );

    hp_restored: i32 = 30,

    pub fn use(self: *const Item, user: *Thing, _: *Room, params: Spell.Params) Error!void {
        assert(std.meta.activeTag(params.target) == Item.TargetKind.self);
        const hp_up = self.kind.hp_up;
        if (user.hp) |*hp| {
            hp.heal(hp_up.hp_restored);
        }
    }
};

pub const ItemTypes = [_]type{
    PotionHP,
};

pub const Kind = utl.EnumFromTypes(&ItemTypes, "enum_name");
pub const KindData = utl.TaggedUnionFromTypes(&ItemTypes, "enum_name", Kind);
const all_items = blk: {
    const kind_info = @typeInfo(Kind).@"enum";
    var ret: [kind_info.fields.len]Item = undefined;
    for (kind_info.fields, 0..) |f, i| {
        const kind: Kind = @enumFromInt(f.value);
        const proto = getProto(kind);
        ret[i] = proto;
    }
    break :blk ret;
};

const item_names = blk: {
    var ret: std.EnumArray(Kind, []const u8) = undefined;
    for (std.meta.fields(Kind)) |f| {
        const kind: Kind = @enumFromInt(f.value);
        const T = GetKindType(kind);
        ret.set(kind, T.title);
    }
    break :blk ret;
};
const item_descriptions = blk: {
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
    @compileError("No Item kind: " ++ @tagName(kind));
}

pub fn getProto(kind: Kind) Item {
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

pub const Controller = struct {
    const ControllerTypes = blk: {
        var num = 0;
        for (ItemTypes) |M| {
            for (M.Controllers) |_| {
                num += 1;
            }
        }
        var Types: [num]type = undefined;
        var i = 0;
        for (ItemTypes) |M| {
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
    item: Item,
    params: Params,

    pub fn update(self: *Thing, room: *Room) Error!void {
        // TODO
        if (false) {
            const scontroller = self.controller.item;
            switch (scontroller.controller) {
                inline else => |s| {
                    try @TypeOf(s).update(self, room);
                },
            }
        }
    }
};

pub const max_items_in_array = 256;
pub const ItemArray = std.BoundedArray(Item, max_items_in_array);
const WeightsArray = std.BoundedArray(f32, max_items_in_array);

const rarity_weight_base = std.EnumArray(Rarity, f32).init(.{
    .pedestrian = 0.5,
    .interesting = 0.30,
    .exceptional = 0.15,
    .brilliant = 0.05,
});

pub fn getItemWeights(items: []const Item) WeightsArray {
    var ret = WeightsArray{};
    for (items) |item| {
        ret.append(rarity_weight_base.get(item.rarity)) catch unreachable;
    }
    return ret;
}

pub const Reward = struct {
    pub const base_item_rewards: usize = 2;
    items: std.BoundedArray(Item, 8) = .{},

    pub fn init(rng: std.Random) Reward {
        var ret = Reward{};
        var item_pool = ItemArray{};
        item_pool.insertSlice(0, &all_items) catch unreachable;
        for (0..base_item_rewards) |_| {
            const weights = getItemWeights(item_pool.constSlice());
            const idx = rng.weightedIndex(f32, weights.constSlice());
            const spell = item_pool.swapRemove(idx);
            ret.items.append(spell) catch unreachable;
        }
        return ret;
    }
};

pub const BufferedItem = struct {
    item: Item,
    params: Params,
    slot_idx: i32,
};

// only valid if spawn_state == .card
id: Id = undefined,
alloc_state: pool.AllocState = undefined,
//
spawn_state: enum {
    instance, // not in any pool
    allocated, // a card allocated in a pool
} = .instance,
kind: KindData = undefined,
rarity: Rarity = .pedestrian,
color: Colorf = .black,
targeting_data: TargetingData = .{},

pub fn makeProto(kind: Kind, the_rest: Item) Item {
    var ret = the_rest;
    ret.kind = @unionInit(KindData, @tagName(kind), .{});
    return ret;
}

pub fn use(self: *const Item, caster: *Thing, room: *Room, params: Params) Error!void {
    switch (self.kind) {
        inline else => |k| {
            const K = @TypeOf(k);
            if (std.meta.hasMethod(K, "use")) {
                try K.cast(self, caster, room, params);
            }
        },
    }
}

pub fn getRenderIconInfo(self: *const Item) sprites.RenderIconInfo {
    const data = App.get().data;
    const kind = std.meta.activeTag(self.kind);
    if (data.item_icons.getRenderFrame(kind)) |render_frame| {
        return .{ .frame = render_frame };
    } else {
        const name = item_names.get(kind);
        return .{ .letter = .{
            .str = [1]u8{std.ascii.toUpper(name[0])},
            .color = self.color,
        } };
    }
}

pub fn renderInfo(self: *const Spell, rect: geom.Rectf) Error!void {
    const plat = App.getPlat();
    const title_rect_dims = v2f(rect.dims.x, rect.dims.y * 0.2);
    const description_dims = v2f(rect.dims.x, rect.dims.y * 0.4);

    const kind = std.meta.activeTag(self.kind);
    const name = item_names.get(kind);

    plat.rectf(rect.pos, rect.dims, .{ .fill_color = .darkgray });
    try menuUI.textInRect(rect.pos, title_rect_dims, .{ .fill_color = null }, v2f(5, 5), "{s}", .{name}, .{ .color = .white, .center = false });

    const description_text = item_descriptions.get(kind);
    const description_rect_topleft = rect.pos.add(v2f(0, title_rect_dims.y));
    try menuUI.textInRect(description_rect_topleft, description_dims, .{ .fill_color = null }, v2f(10, 10), "{s}", .{description_text}, .{ .color = .white });
}
