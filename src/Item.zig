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
const Run = @import("Run.zig");
const Tooltip = @import("Tooltip.zig");
const StatusEffect = @import("StatusEffect.zig");
const Spell = @import("Spell.zig");
const Params = Spell.Params;
const TargetKind = Spell.TargetKind;
const TargetingData = Spell.TargetingData;
pub const Obtainableness = Spell.Obtainableness;

const Item = @This();

pub const Pool = pool.BoundedPool(Item, 32);
pub const Id = pool.Id;

pub const icon_dims = v2f(24, 24);

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

    pub fn use(self: *const Item, user: *Thing, room: *Room, params: Params) Error!void {
        params.validate(.self, user);
        const pot_hp = self.kind.pot_hp;
        if (user.hp) |*hp| {
            hp.heal(hp.max * (pot_hp.hp_restored_percent * 0.01), user, room);
        }
    }

    pub fn canUse(self: *const Item, _: *const Room, user: *const Thing) bool {
        return self.canUseInRun(user, null);
    }

    pub fn useInRun(self: *const Item, user: *Thing, maybe_run: ?*Run) Error!void {
        assert(self.canUseInRun(user, maybe_run));
        const pot_hp = self.kind.pot_hp;
        if (user.hp) |*hp| {
            _ = hp.healNoVFX(hp.max * (pot_hp.hp_restored_percent * 0.01));
        }
    }

    pub fn canUseInRun(_: *const Item, user: *const Thing, _: ?*const Run) bool {
        if (user.hp) |hp| {
            return (hp.curr < hp.max);
        }
        return false;
    }
};

pub const PotionInvis = struct {
    pub const title = "Unseeability Powder";

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
        params.validate(.self, user);
        user.statuses.getPtr(.unseeable).stacks = self.kind.pot_invis.invis_stacks;
    }

    pub fn getTooltip(self: *const Item, tt: *Tooltip) Error!void {
        const pot_invis: @This() = self.kind.pot_invis;
        const fmt =
            \\Makes you {any}unseeable for {d:.0}
            \\seconds.
        ;
        tt.desc = try Tooltip.Desc.fromSlice(
            try std.fmt.bufPrint(&tt.desc.buffer, fmt, .{
                StatusEffect.getIcon(.unseeable),
                @floor(StatusEffect.getDurationSeconds(.unseeable, pot_invis.invis_stacks).?),
            }),
        );
        tt.title = try Tooltip.Title.fromSlice(title);
        tt.infos.appendAssumeCapacity(.{ .status = .unseeable });
    }
};

pub const PotionThorns = struct {
    pub const title = "Prickly Potion";

    pub const enum_name = "pot_thorns";
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

    thorny_stacks: i32 = 5,

    pub fn use(self: *const Item, user: *Thing, _: *Room, params: Params) Error!void {
        params.validate(.self, user);
        user.statuses.getPtr(.prickly).stacks = self.kind.pot_thorns.thorny_stacks;
    }

    pub fn getTooltip(self: *const Item, tt: *Tooltip) Error!void {
        const pot_thorns: @This() = self.kind.pot_thorns;
        const stacks = pot_thorns.thorny_stacks;
        const fmt =
            \\Gain {} {any}prickly stacks
        ;
        tt.desc = try Tooltip.Desc.fromSlice(
            try std.fmt.bufPrint(&tt.desc.buffer, fmt, .{
                stacks,
                StatusEffect.getIcon(.prickly),
            }),
        );
        tt.title = try Tooltip.Title.fromSlice(title);
        tt.infos.appendAssumeCapacity(.{ .status = .prickly });
    }
};

pub const PotionMana = struct {
    pub const title = "Mana Potion";
    pub const description =
        \\Fill mana bar to maximum.
    ;

    pub const enum_name = "pot_mana";
    pub const Controllers = [_]type{};

    pub const proto = Item.makeProto(
        std.meta.stringToEnum(Item.Kind, enum_name).?,
        .{
            .color = .green,
            .obtainable_modes = Run.Mode.Mask.initMany(&.{ .mandy_3_mana, .crispin_picker }),
            .targeting_data = .{
                .kind = .self,
            },
        },
    );

    pub fn use(self: *const Item, user: *Thing, room: *Room, params: Params) Error!void {
        params.validate(.self, user);
        _ = self;
        _ = room;
        if (user.mana) |*mana| {
            mana.curr = mana.max;
        }
    }

    pub fn canUse(_: *const Item, _: *const Room, caster: *const Thing) bool {
        if (caster.mana) |mana| {
            return (mana.curr < mana.max);
        }
        return false;
    }
};

pub const PotionImp = struct {
    pub const title = "Bottled Imp";
    pub const description =
        \\Unbottle a friendly imp.
    ;

    pub const enum_name = "pot_imp";
    pub const Controllers = [_]type{};

    pub const proto = Item.makeProto(
        std.meta.stringToEnum(Item.Kind, enum_name).?,
        .{
            .color = .green,
            .rarity = .interesting,
            .targeting_data = .{
                .kind = .pos,
                .target_mouse_pos = true,
                .max_range = 100,
                .show_max_range_ring = true,
            },
        },
    );

    pub fn use(self: *const Item, user: *Thing, room: *Room, params: Params) Error!void {
        params.validate(.pos, user);
        _ = self;
        const target_pos = params.pos;
        const spawner = Thing.SpawnerController.prototype(.impling);
        _ = try room.queueSpawnThing(&spawner, target_pos);
    }
};

pub const ItemTypes = [_]type{
    PotionHP,
    PotionInvis,
    PotionThorns,
    PotionMana,
    PotionImp,
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

pub fn generateRandom(rng: std.Random, mask: Obtainableness.Mask, mode: Run.Mode, allow_duplicates: bool, buf: []Item) []Item {
    var num: usize = 0;
    var item_pool = ItemArray{};
    for (all_items) |item| {
        if (item.obtainable_modes.contains(mode) and item.obtainableness.intersectWith(mask).count() > 0) {
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
    return buf[0..num];
}

pub fn makeRoomReward(rng: std.Random, mode: Run.Mode, buf: []Item) []Item {
    return generateRandom(rng, Obtainableness.Mask.initOne(.room_reward), mode, false, buf);
}

pub fn makeShopItems(rng: std.Random, mode: Run.Mode, buf: []Item) []Item {
    return generateRandom(rng, Obtainableness.Mask.initOne(.shop), mode, false, buf);
}

kind: KindData = undefined,
rarity: Rarity = .pedestrian,
obtainableness: Obtainableness.Mask = Obtainableness.Mask.initMany(&.{ .room_reward, .shop }),
obtainable_modes: Run.Mode.Mask = Run.Mode.Mask.initFull(),
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

pub fn canUse(self: *const Item, room: *const Room, user: *const Thing) bool {
    switch (self.kind) {
        inline else => |k| {
            const K = @TypeOf(k);
            if (std.meta.hasMethod(K, "canUse")) {
                return K.canUse(self, room, user);
            }
        },
    }
    return true;
}

pub fn useInRun(self: *const Item, user: *Thing, maybe_run: ?*Run) Error!void {
    assert(self.canUseInRun(user, maybe_run));
    switch (self.kind) {
        inline else => |k| {
            const K = @TypeOf(k);
            if (std.meta.hasMethod(K, "useInRun")) {
                return K.useInRun(self, user, maybe_run);
            }
        },
    }
}

pub fn canUseInRun(self: *const Item, user: *const Thing, maybe_run: ?*const Run) bool {
    switch (self.kind) {
        inline else => |k| {
            const K = @TypeOf(k);
            if (std.meta.hasMethod(K, "canUseInRun")) {
                return K.canUseInRun(self, user, maybe_run);
            }
        },
    }
    // NOTE: false by default, not true like canUse!
    return false;
}

pub fn getDescription(self: *const Item) Error![]const u8 {
    return item_descriptions.get(std.meta.activeTag(self.kind));
}

const rarity_price_base = std.EnumArray(Rarity, i32).init(.{
    .pedestrian = 8,
    .interesting = 13,
    .exceptional = 16,
    .brilliant = 21,
});

const rarity_price_variance = std.EnumArray(Rarity, i32).init(.{
    .pedestrian = 2,
    .interesting = 3,
    .exceptional = 4,
    .brilliant = 3,
});

pub fn getShopPrice(self: *const Item, rng: std.Random) i32 {
    const base = rarity_price_base.get(self.rarity);
    const variance = rarity_price_variance.get(self.rarity);
    return base - variance + rng.intRangeAtMost(i32, 0, variance * 2);
}

pub inline fn getTargetParams(self: *const Item, room: *Room, caster: *const Thing, mouse_pos: V2f) ?Params {
    return self.targeting_data.getParams(room, caster, mouse_pos);
}

pub inline fn renderTargeting(self: *const Item, room: *const Room, caster: *const Thing, params: ?Params) Error!void {
    return self.targeting_data.render(room, caster, params);
}

pub inline fn unqRenderIcon(self: *const Item, cmd_buf: *ImmUI.CmdBuf, pos: V2f, scaling: f32) Error!void {
    return try self.getRenderIconInfo().unqRender(cmd_buf, pos, scaling);
}

pub inline fn unqRenderIconTint(self: *const Item, cmd_buf: *ImmUI.CmdBuf, pos: V2f, scaling: f32, tint: Colorf) Error!void {
    return try self.getRenderIconInfo().unqRenderTint(cmd_buf, pos, scaling, tint);
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

pub fn getName(self: *const Item) []const u8 {
    const kind = std.meta.activeTag(self.kind);
    return item_names.get(kind);
}

pub fn getTooltip(self: *const Item, info: *Tooltip) Error!void {
    switch (self.kind) {
        inline else => |k| {
            const K = @TypeOf(k);
            if (std.meta.hasMethod(K, "getTooltip")) {
                return try K.getTooltip(self, info);
            } else {
                if (@hasDecl(K, "title")) {
                    info.title = try Tooltip.Title.fromSlice(K.title);
                }
                if (@hasDecl(K, "description")) {
                    info.desc = try Tooltip.Desc.fromSlice(K.description);
                }
            }
        },
    }
}

pub fn unqRenderTooltip(self: *const Item, cmd_buf: *ImmUI.CmdBuf, pos: V2f, scaling: f32) Error!void {
    var tt: Tooltip = .{};
    try self.getTooltip(&tt);
    if (tt.desc.len > 0 or tt.title.len > 0) {
        try tt.unqRender(cmd_buf, pos, scaling);
    }
}
