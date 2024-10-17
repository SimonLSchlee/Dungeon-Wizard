const std = @import("std");
const assert = std.debug.assert;
const u = @import("util.zig");

pub const Platform = @import("raylib.zig");
const core = @import("core.zig");
const Error = core.Error;
const Key = core.Key;
const draw = @import("draw.zig");
const Colorf = draw.Colorf;
const geom = @import("geometry.zig");
const V2f = @import("V2f.zig");
const v2f = V2f.v2f;
const V2i = @import("V2i.zig");
const v2i = V2i.v2i;

const App = @import("App.zig");
const Thing = @import("Thing.zig");
const Room = @import("Room.zig");
const sprites = @import("sprites.zig");
const Spell = @import("Spell.zig");
const Item = @import("Item.zig");
const PackedRoom = @import("PackedRoom.zig");
const Data = @This();

pub fn EnumToBoundedStringArrayType(E: type) type {
    var max_len = 0;
    const info = @typeInfo(E);
    for (info.@"enum".fields) |f| {
        if (f.name.len > max_len) {
            max_len = f.name.len;
        }
    }
    return std.EnumArray(E, u.BoundedString(max_len));
}

pub fn enumToBoundedStringArray(E: type) EnumToBoundedStringArrayType(E) {
    var ret = EnumToBoundedStringArrayType(E).initUndefined();
    const BoundedArrayType = @TypeOf(ret).Value;
    const info = @typeInfo(E);
    for (info.@"enum".fields) |f| {
        ret.set(@enumFromInt(f.value), BoundedArrayType.init(f.name));
    }
    return ret;
}

pub const SpriteSheet = struct {
    pub const Frame = struct {
        pos: V2i,
        size: V2i,
        duration_ms: i64,
    };
    pub const Tag = struct {
        name: u.BoundedString(16),
        from_frame: i32,
        to_frame: i32,
    };
    pub const Meta = struct {
        name: u.BoundedString(16) = .{},
        data: union(enum) {
            int: i64,
            float: f32,
            string: u.BoundedString(16),
        } = undefined,
    };

    name: u.BoundedString(64) = .{}, // filename without extension (.png)
    texture: Platform.Texture2D = undefined,
    frames: []Frame = &.{},
    tags: []Tag = &.{},
    meta: []Meta = &.{},
};

const test_rooms_strings = [_][]const u8{
    \\#########################
    \\#         ##        ### #
    \\#   ##    ##          # #
    \\##  ###       ###       #
    \\#                a   ## #
    \\#      a  ##        ### #
    \\#         ##       ##   #
    \\#   ##             ##   #
    \\#      ##   p           #
    \\#  ##  ##       #a  ### #
    \\#  ##           #   ### #
    \\#                       #
    \\#########################
    ,
    \\#########################
    \\#                       #
    \\#                       #
    \\#    ## 2      ###      #
    \\#                       #
    \\#     1    #            #
    \\#          #     3      #
    \\#   ##   p    b    ##   #
    \\#                       #
    \\#     3 2       #       #
    \\#     b    1    #       #
    \\#                       #
    \\#########################
    ,
};

const first_room =
    \\###############
    \\#             #
    \\#   #  #  #   #
    \\# p         & #
    \\#   #  #  #   #
    \\#             #
    \\###############
;

const rooms_strings = [_][]const u8{
    \\###############
    \\#             #
    \\#             #
    \\# p2  1 #  2 &#
    \\#             #
    \\#             #
    \\###############
    ,
    \\###############
    \\#  p     1    #
    \\#             #
    \\#     ###     #
    \\#  2  ###  2  #
    \\#             #
    \\#    &   &    #
    \\###############
    ,
    \\#################
    \\#               #
    \\#       2       #
    \\#    ## 3 ##    #
    \\#  1 ## 2 ## 1  #
    \\#       3       #
    \\#     & p &     #
    \\#################
    ,
    \\#################
    \\#     &   &     #
    \\#   #       #   #
    \\#   2   0   2   #
    \\#  1         1  #
    \\#   #       #   #
    \\#       p       #
    \\#################
    ,
    \\#################
    \\###   &   &   ###
    \\#   ##      #   #
    \\#   2    #  2 # #
    \\#  1   ###  #1  #
    \\# ###           #
    \\# #     p     ###
    \\#################
    ,
    \\##################
    \\#  2    &    2   #
    \\#   ###   ###    #
    \\#   #       #    #
    \\#  1  3 # 3  1   #
    \\#   #       #    #
    \\#   ###   ###    #
    \\#  0    p    0   #
    \\#       2        #
    \\##################
    ,
};

pub const CreatureAnimArray = std.EnumArray(sprites.CreatureAnim.AnimKind, ?sprites.CreatureAnim);
pub const AllCreatureAnimArrays = std.EnumArray(sprites.CreatureAnim.Kind, CreatureAnimArray);
pub const CreatureSpriteSheetArray = std.EnumArray(sprites.CreatureAnim.AnimKind, ?SpriteSheet);
pub const AllCreatureSpriteSheetArrays = std.EnumArray(sprites.CreatureAnim.Kind, CreatureSpriteSheetArray);

fn IconSprites(EnumType: type) type {
    return struct {
        pub const IconsFrameIndexArray = std.EnumArray(EnumType, ?i32);

        sprite_sheet: SpriteSheet = undefined,
        icon_indices: IconsFrameIndexArray = undefined,

        pub fn init(sprite_sheet: SpriteSheet) Error!@This() {
            var ret = @This(){
                .sprite_sheet = sprite_sheet,
                .icon_indices = IconsFrameIndexArray.initFill(null),
            };
            tags: for (sprite_sheet.tags) |t| {
                inline for (@typeInfo(EnumType).@"enum".fields) |f| {
                    if (std.mem.eql(u8, f.name, t.name.constSlice())) {
                        const kind = std.meta.stringToEnum(EnumType, f.name).?;
                        ret.icon_indices.set(kind, t.from_frame);
                        continue :tags;
                    }
                }
            }
            return ret;
        }
        pub fn getRenderFrame(self: @This(), kind: EnumType) ?sprites.RenderFrame {
            if (self.icon_indices.get(kind)) |idx| {
                const sheet = self.sprite_sheet;
                const frame = sheet.frames[u.as(usize, idx)];
                return .{
                    .pos = frame.pos,
                    .size = frame.size,
                    .texture = sheet.texture,
                    .origin = .center,
                };
            }
            return null;
        }
    };
}

creatures: std.EnumArray(Thing.CreatureKind, Thing) = undefined,
creature_sprite_sheets: AllCreatureSpriteSheetArrays = undefined,
creature_anims: AllCreatureAnimArrays = undefined,
spell_icons: IconSprites(Spell.Kind) = undefined,
item_icons: IconSprites(Item.Kind) = undefined,
sounds: std.EnumArray(SFX, ?Platform.Sound) = undefined,
test_rooms: std.BoundedArray(PackedRoom, 32) = .{},
rooms: std.BoundedArray(PackedRoom, 32) = .{},

pub const SFX = enum {
    thwack,
};

pub fn init() Error!*Data {
    const plat = App.getPlat();
    const data = plat.heap.create(Data) catch @panic("Out of memory");
    data.* = .{};
    try data.reload();
    return data;
}

pub fn getCreatureAnim(self: *Data, creature_kind: sprites.CreatureAnim.Kind, anim_kind: sprites.CreatureAnim.AnimKind) ?sprites.CreatureAnim {
    return self.creature_anims.get(creature_kind).get(anim_kind);
}

pub fn getCreatureAnimSpriteSheet(self: *Data, creature_kind: sprites.CreatureAnim.Kind, anim_kind: sprites.CreatureAnim.AnimKind) ?SpriteSheet {
    return self.creature_sprite_sheets.get(creature_kind).get(anim_kind);
}

pub fn loadSounds(self: *Data) Error!void {
    const plat = App.getPlat();
    self.sounds = @TypeOf(self.sounds).initFill(null);
    self.sounds.getPtr(.thwack).* = try plat.loadSound("thwack.wav");
}

pub fn loadSpriteSheetFromJson(json_file: std.fs.File, assets_images_rel_dir_path: []const u8) Error!SpriteSheet {
    const plat = App.getPlat();
    const s = json_file.readToEndAlloc(plat.heap, 8 * 1024 * 1024) catch return Error.FileSystemFail;
    //std.debug.print("{s}\n", .{s});
    var scanner = std.json.Scanner.initCompleteInput(plat.heap, s);
    var tree = std.json.Value.jsonParse(plat.heap, &scanner, .{ .max_value_len = s.len }) catch return Error.ParseFail;
    // TODO I guess tree just leaks rn? use arena?

    const meta = tree.object.get("meta").?.object;
    const image_filename = meta.get("image").?.string;
    const image_path = try u.bufPrintLocal("{s}/{s}", .{ assets_images_rel_dir_path, image_filename });

    var sheet = SpriteSheet{};
    var it_dot = std.mem.tokenizeScalar(u8, image_filename, '.');
    const sheet_name = it_dot.next().?;
    sheet.name = try @TypeOf(sheet.name).init(sheet_name);
    const tex = try plat.loadTexture(image_path);
    assert(tex.r_tex.height > 0);
    sheet.texture = tex;

    const frames = tree.object.get("frames").?.array;
    const tags = meta.get("frameTags").?.array;
    const _layers = meta.get("layers");
    var sheet_frames = try std.ArrayList(SpriteSheet.Frame).initCapacity(plat.heap, frames.items.len);
    var sheet_tags = try std.ArrayList(SpriteSheet.Tag).initCapacity(plat.heap, tags.items.len);
    var sheet_meta = try std.ArrayList(SpriteSheet.Meta).initCapacity(plat.heap, tags.items.len);

    for (tags.items) |t| {
        const name = t.object.get("name").?.string;
        const from = t.object.get("from").?.integer;
        const to = t.object.get("to").?.integer;
        assert(from >= 0 and from <= frames.items.len);
        assert(to >= from and to <= frames.items.len);
        try sheet_tags.append(.{
            .name = try @TypeOf(sheet.tags[0].name).init(name),
            .from_frame = u.as(i32, from),
            .to_frame = u.as(i32, to),
        });
    }
    sheet.tags = try sheet_tags.toOwnedSlice();

    for (frames.items) |f| {
        const dur = f.object.get("duration").?.integer;
        const frame = f.object.get("frame").?.object;
        const x = frame.get("x").?.integer;
        const y = frame.get("y").?.integer;
        const w = frame.get("w").?.integer;
        const h = frame.get("h").?.integer;
        try sheet_frames.append(.{
            .duration_ms = dur,
            .pos = V2i.iToV2i(i64, x, y),
            .size = V2i.iToV2i(i64, w, h),
        });
    }
    sheet.frames = try sheet_frames.toOwnedSlice();

    if (_layers) |layers| {
        for (layers.array.items) |layer| {
            if (layer.object.get("cels")) |cels| {
                for (cels.array.items) |cel| {
                    if (cel.object.get("data")) |data| {
                        var it_data = std.mem.tokenizeScalar(u8, data.string, ',');
                        while (it_data.next()) |item| {
                            var it_eq = std.mem.tokenizeScalar(u8, item, '=');
                            const key = it_eq.next().?;
                            const val = it_eq.next().?;
                            var m = SpriteSheet.Meta{};
                            m.name = try @TypeOf(m.name).init(key);
                            blk: {
                                int_blk: {
                                    const int = std.fmt.parseInt(i64, val, 0) catch break :int_blk;
                                    m.data.int = int;
                                    break :blk;
                                }
                                float_blk: {
                                    const float = std.fmt.parseFloat(f32, val) catch break :float_blk;
                                    m.data.float = float;
                                    break :blk;
                                }
                                m.data.string = try @TypeOf(m.data.string).init(val);
                            }
                            try sheet_meta.append(m);
                        }
                    }
                }
            }
        }
    }
    sheet.meta = try sheet_meta.toOwnedSlice();

    return sheet;
}

pub fn loadItemIcons(self: *Data) Error!void {
    const icons_json = std.fs.cwd().openFile("assets/images/ui/item_icons.json", .{}) catch return Error.FileSystemFail;
    const sheet = try loadSpriteSheetFromJson(icons_json, "ui");
    self.item_icons = try @TypeOf(self.item_icons).init(sheet);
}

pub fn loadSpellIcons(self: *Data) Error!void {
    const icons_json = std.fs.cwd().openFile("assets/images/ui/spell_icons.json", .{}) catch return Error.FileSystemFail;
    const sheet = try loadSpriteSheetFromJson(icons_json, "ui");
    self.spell_icons = try @TypeOf(self.spell_icons).init(sheet);
}

pub fn loadSpriteSheets(self: *Data) Error!void {
    try self.loadCreatureSpriteSheets();
    try self.loadSpellIcons();
    try self.loadItemIcons();
}

pub fn loadCreatureSpriteSheets(self: *Data) Error!void {
    const plat = App.getPlat();

    self.creature_anims = @TypeOf(self.creature_anims).initFill(CreatureAnimArray.initFill(null));
    self.creature_sprite_sheets = @TypeOf(self.creature_sprite_sheets).initFill(CreatureSpriteSheetArray.initFill(null));

    var creature = std.fs.cwd().openDir("assets/images/creature", .{ .iterate = true }) catch return Error.FileSystemFail;
    defer creature.close();
    var walker = try creature.walk(plat.heap);
    defer walker.deinit();

    while (walker.next() catch return Error.FileSystemFail) |w_entry| {
        if (!std.mem.endsWith(u8, w_entry.basename, ".json")) continue;
        const json_file = creature.openFile(w_entry.basename, .{}) catch return Error.FileSystemFail;
        const sheet = try loadSpriteSheetFromJson(json_file, "creature");

        var it_dash = std.mem.tokenizeScalar(u8, sheet.name.constSlice(), '-');
        const creature_name = it_dash.next().?;
        const creature_kind = std.meta.stringToEnum(sprites.CreatureAnim.Kind, creature_name).?;
        const anim_name = it_dash.next().?;
        const anim_kind = std.meta.stringToEnum(sprites.CreatureAnim.AnimKind, anim_name).?;
        self.creature_sprite_sheets.getPtr(creature_kind).getPtr(anim_kind).* = sheet;

        // sprite sheet to creature anim
        var anim = sprites.CreatureAnim{
            .creature_kind = creature_kind,
            .anim_kind = anim_kind,
            .num_frames = sheet.tags[0].to_frame - sheet.tags[0].from_frame + 1,
            .num_dirs = u.as(u8, sheet.tags.len), // TODO
        };

        meta_blk: for (sheet.meta) |m| {
            const m_name = m.name.constSlice();
            //std.debug.print("Meta '{s}'\n", .{m_name});

            if (std.mem.eql(u8, m_name, "pivot-y")) {
                const y = switch (m.data) {
                    .int => |i| u.as(f32, i),
                    .float => |f| f,
                    .string => return Error.ParseFail,
                };
                const x = u.as(f32, sheet.frames[0].size.x) * 0.5;
                anim.origin = .{ .offset = v2f(x, y) };
                continue;
            }
            if (std.mem.eql(u8, m_name, "start-angle-deg")) {
                const deg = switch (m.data) {
                    .int => |i| u.as(f32, i),
                    .float => |f| f,
                    .string => return Error.ParseFail,
                };
                const rads = u.degreesToRadians(deg);
                anim.start_angle_rads = rads;
            }

            const event_info = @typeInfo(sprites.CreatureAnim.Event.Kind);
            inline for (event_info.@"enum".fields) |f| {
                if (std.mem.eql(u8, m_name, f.name)) {
                    //std.debug.print("Adding event '{s}' on frame {}\n", .{ f.name, m.data.int });
                    anim.events.append(.{
                        .frame = u.as(i32, m.data.int),
                        .kind = @enumFromInt(f.value),
                    }) catch {
                        std.debug.print("Skipped adding anim event \"{s}\"; buffer full\n", .{f.name});
                    };
                    continue :meta_blk;
                }
            }
        }
        self.creature_anims.getPtr(creature_kind).getPtr(anim_kind).* = anim;
    }
}

pub fn reload(self: *Data) Error!void {
    loadSpriteSheets(self) catch std.debug.print("WARNING: failed to load all sprites\n", .{});
    loadSounds(self) catch std.debug.print("WARNING: failed to load all sounds\n", .{});
    self.creatures = @TypeOf(self.creatures).init(
        .{
            .player = try @import("player.zig").protoype(),
            .bat = try @import("enemies.zig").bat(),
            .troll = try @import("enemies.zig").troll(),
            .gobbow = try @import("enemies.zig").gobbow(),
            .sharpboi = try @import("enemies.zig").sharpboi(),
            .acolyte = try @import("enemies.zig").acolyte(),
            .impling = try @import("spells/Impling.zig").implingProto(),
        },
    );
    self.test_rooms = .{};
    for (test_rooms_strings) |s| {
        try self.test_rooms.append(try PackedRoom.init(s));
    }
    self.rooms = .{};
    for (rooms_strings) |s| {
        try self.rooms.append(try PackedRoom.init(s));
    }
}
