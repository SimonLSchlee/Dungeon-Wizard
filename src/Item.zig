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
pub const Obtainableness = Spell.Obtainableness;

const Item = @This();

pub const Pool = pool.BoundedPool(Item, 32);
pub const Id = pool.Id;

pub const PotionHP = struct {
    pub const title = "Hp Potion";
    pub const description =
        \\Restore 30% of total HP instantly.
        \\(self only)
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

    hp_restored_percent: f32 = 30,

    pub fn use(self: *const Item, user: *Thing, _: *Room, params: Params) Error!void {
        assert(std.meta.activeTag(params.target) == Item.TargetKind.self);
        const pot_hp = self.kind.pot_hp;
        if (user.hp) |*hp| {
            hp.heal(hp.max * (pot_hp.hp_restored_percent * 0.01));
        }
    }

    pub fn canUse(_: *const Item, _: *const Room, caster: *const Thing) bool {
        if (caster.hp) |hp| {
            return (hp.curr < hp.max);
        }
        return false;
    }
};

pub const PotionInvis = struct {
    pub const title = "Unseeability Powder";
    pub const description =
        \\Makes you unseeable by enemies,
        \\temporarily.
        \\Some enemies won't be fooled.
        \\You can cast spells and move as
        \\normal while unseeable.
    ;

    pub const enum_name = "pot_invis";
    pub const Controllers = [_]type{};

    pub const proto = Item.makeProto(
        std.meta.stringToEnum(Item.Kind, enum_name).?,
        .{
            .color = .blue,
            .targeting_data = .{
                .kind = .self,
            },
        },
    );

    invis_stacks: i32 = 7,

    pub fn use(self: *const Item, user: *Thing, _: *Room, params: Params) Error!void {
        assert(std.meta.activeTag(params.target) == Item.TargetKind.self);
        user.statuses.getPtr(.unseeable).stacks = self.kind.pot_invis.invis_stacks;
    }
};

pub const ItemTypes = [_]type{
    PotionHP,
    PotionInvis,
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

pub fn generateRandom(rng: std.Random, mask: Obtainableness.Mask, allow_duplicates: bool, buf: []Item) usize {
    var num: usize = 0;
    var item_pool = ItemArray{};
    for (all_items) |item| {
        if (item.obtainableness.intersectWith(mask).count() > 0) {
            item_pool.append(item) catch unreachable;
        }
    }
    for (0..buf.len) |i| {
        if (item_pool.len == 0) break;
        const weights = getItemWeights(item_pool.constSlice());
        const idx = rng.weightedIndex(f32, weights.constSlice());
        const item = if (allow_duplicates) item_pool.get(idx) else item_pool.swapRemove(idx);
        buf[i] = item;
        num += 1;
    }
    return num;
}

pub fn makeRoomReward(rng: std.Random, buf: []Item) usize {
    return generateRandom(rng, Obtainableness.Mask.initOne(.room_reward), false, buf);
}

pub fn makeShopItems(rng: std.Random, buf: []Item) usize {
    return generateRandom(rng, Obtainableness.Mask.initOne(.shop), false, buf);
}

// only valid if spawn_state == .card
id: Id = undefined,
alloc_state: pool.AllocState = undefined,
//
obtainableness: Obtainableness.Mask = Obtainableness.Mask.initMany(&.{ .room_reward, .shop }),
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
                try K.use(self, caster, room, params);
            }
        },
    }
}

pub fn canUse(self: *const Item, room: *const Room, caster: *const Thing) bool {
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

pub inline fn getTargetParams(self: *const Item, room: *Room, caster: *const Thing, mouse_pos: V2f) ?Params {
    return self.targeting_data.getParams(room, caster, mouse_pos);
}

pub inline fn renderTargeting(self: *const Item, room: *const Room, caster: *const Thing) Error!void {
    return self.targeting_data.render(room, caster);
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

pub fn renderToolTip(self: *const Item, pos: V2f) Error!void {
    const plat = App.getPlat();
    const kind = std.meta.activeTag(self.kind);
    const name = item_names.get(kind);
    const name_opt = draw.TextOpt{
        .color = .white,
        .size = 25,
    };
    const name_dims = try plat.measureText(name, name_opt);
    const desc = item_descriptions.get(kind);
    const desc_opt = draw.TextOpt{
        .color = .white,
        .size = 20,
    };
    const desc_dims = try plat.measureText(desc, desc_opt);
    const text_dims = v2f(@max(name_dims.x, desc_dims.x), name_dims.y + desc_dims.y);
    const modal_dims = text_dims.add(v2f(10, 15));
    plat.rectf(pos, modal_dims, .{ .fill_color = Colorf.black.fade(0.8) });
    var text_pos = pos.add(v2f(5, 5));
    try plat.textf(text_pos, "{s}", .{name}, name_opt);
    text_pos.y += 5 + name_dims.y;
    try plat.textf(text_pos, "{s}", .{desc}, desc_opt);
}

pub fn renderIcon(self: *const Item, rect: menuUI.ClickableRect) Error!void {
    const plat = App.getPlat();
    const icon_center_pos = rect.pos.add(rect.dims.scale(0.5));
    switch (self.getRenderIconInfo()) {
        .frame => |frame| {
            plat.texturef(icon_center_pos, frame.texture, .{
                .origin = .center,
                .src_pos = frame.pos.toV2f(),
                .src_dims = frame.size.toV2f(),
                .scaled_dims = rect.dims,
            });
        },
        .letter => |letter| {
            try plat.textf(
                icon_center_pos,
                "{s}",
                .{&letter.str},
                .{
                    .color = letter.color,
                    .size = utl.as(u32, rect.dims.y),
                    .center = true,
                },
            );
        },
    }
}

pub fn renderInfo(self: *const Item, rect: menuUI.ClickableRect) Error!void {
    const plat = App.getPlat();
    const title_rect_dims = v2f(rect.dims.x, rect.dims.y * 0.2);
    const icon_rect_dims = v2f(rect.dims.x, rect.dims.y * 0.4);
    const description_dims = v2f(rect.dims.x, rect.dims.y * 0.4);

    const kind = std.meta.activeTag(self.kind);
    const name = item_names.get(kind);

    plat.rectf(rect.pos, rect.dims, .{ .fill_color = .darkgray });
    try menuUI.textInRect(rect.pos, title_rect_dims, .{ .fill_color = null }, v2f(5, 5), "{s}", .{name}, .{ .color = .white });

    const icon_center_pos = rect.pos.add(v2f(0, title_rect_dims.y)).add(icon_rect_dims.scale(0.5));
    const icon_top_left = icon_center_pos.sub(icon_rect_dims.scale(0.5));
    // item image
    plat.rectf(icon_top_left, icon_rect_dims, .{ .fill_color = .black });
    const icon_square_dim = @min(icon_rect_dims.x, icon_rect_dims.y);
    const icon_square = V2f.splat(icon_square_dim);
    const icon_square_top_left = icon_center_pos.sub(icon_square.scale(0.5));

    try self.renderIcon(.{ .pos = icon_square_top_left, .dims = icon_square });

    const description_text = item_descriptions.get(kind);
    const description_rect_topleft = rect.pos.add(v2f(0, title_rect_dims.y + icon_rect_dims.y));
    try menuUI.textInRect(description_rect_topleft, description_dims, .{ .fill_color = null }, v2f(10, 10), "{s}", .{description_text}, .{ .color = .white });
}
