const std = @import("std");
const assert = std.debug.assert;
const u = @import("util.zig");

pub const Platform = @import("raylib.zig");
const debug = @import("debug.zig");
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
const Log = App.Log;
const Thing = @import("Thing.zig");
const Room = @import("Room.zig");
const sprites = @import("sprites.zig");
const Spell = @import("Spell.zig");
const Item = @import("Item.zig");
const player = @import("player.zig");
const TileMap = @import("TileMap.zig");
const creatures = @import("creatures.zig");
const icon_text = @import("icon_text.zig");
const Data = @This();

pub const TileSet = struct {
    pub const NameBuf = u.BoundedString(64);
    pub const GameTileCorner = enum(u4) {
        NW,
        NE,
        SW,
        SE,
        const Map = std.EnumArray(GameTileCorner, bool);
        // map a tile coordinate to a game tile coordinate by adding these
        // note they don't actually point in NW/NE etc directions!
        const dir_map = std.EnumArray(GameTileCorner, V2i).init(.{
            .NW = v2i(-1, -1),
            .NE = v2i(0, -1),
            .SW = v2i(-1, 0),
            .SE = v2i(0, 0),
        });
    };
    pub const TileProperties = struct {
        colls: GameTileCorner.Map = GameTileCorner.Map.initFill(false),
        spikes: GameTileCorner.Map = GameTileCorner.Map.initFill(false),
    };

    name: NameBuf = .{}, // filename without extension (.tsj)
    id: i32 = 0,
    texture: Platform.Texture2D = undefined,
    tile_dims: V2i = .{},
    sheet_dims: V2i = .{},
    tiles: std.BoundedArray(TileProperties, TileMap.max_map_tiles) = .{},
};

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
        name: u.BoundedString(32),
        from_frame: i32,
        to_frame: i32,
    };
    pub const Meta = struct {
        name: u.BoundedString(32) = .{},
        data: union(enum) {
            int: i64,
            float: f32,
            string: u.BoundedString(32),
        } = undefined,

        pub fn asf32(self: @This()) Error!f32 {
            return switch (self.data) {
                .int => |i| u.as(f32, i),
                .float => |f| f,
                .string => {
                    Log.warn("Failed to parse Meta.data \"{s}\" as f32\n", .{self.name.constSlice()});
                    return Error.ParseFail;
                },
            };
        }
    };

    name: u.BoundedString(64) = .{}, // filename without extension (.png)
    texture: Platform.Texture2D = undefined,
    frames: []Frame = &.{},
    tags: []Tag = &.{},
    meta: []Meta = &.{},
};

pub const CreatureAnimArray = std.EnumArray(sprites.AnimName, ?sprites.CreatureAnim);
pub const AllCreatureAnimArrays = std.EnumArray(sprites.CreatureAnim.Kind, CreatureAnimArray);
pub const CreatureSpriteSheetArray = std.EnumArray(sprites.AnimName, ?SpriteSheet);
pub const AllCreatureSpriteSheetArrays = std.EnumArray(sprites.CreatureAnim.Kind, CreatureSpriteSheetArray);

fn EnumSpriteSheet(EnumType: type) type {
    return struct {
        pub const SpriteFrameIndexArray = std.EnumArray(EnumType, ?i32);

        sprite_sheet: SpriteSheet = undefined,
        sprite_indices: SpriteFrameIndexArray = undefined,
        sprite_dims_cropped: ?std.EnumArray(EnumType, V2f) = null,

        pub fn init(sprite_sheet: SpriteSheet) Error!@This() {
            var ret = @This(){
                .sprite_sheet = sprite_sheet,
                .sprite_indices = SpriteFrameIndexArray.initFill(null),
            };
            tags: for (sprite_sheet.tags) |t| {
                inline for (@typeInfo(EnumType).@"enum".fields) |f| {
                    if (std.mem.eql(u8, f.name, t.name.constSlice())) {
                        const kind = std.meta.stringToEnum(EnumType, f.name).?;
                        ret.sprite_indices.set(kind, t.from_frame);
                        continue :tags;
                    }
                }
            }
            return ret;
        }
        pub fn initCropped(sprite_sheet: SpriteSheet, crop_color: draw.Coloru) Error!@This() {
            const plat = App.getPlat();
            var ret = try @This().init(sprite_sheet);
            ret.sprite_dims_cropped = std.EnumArray(EnumType, V2f).initFill(.{});
            const image_buf = plat.textureToImageBuf(sprite_sheet.texture);
            defer plat.unloadImageBuf(image_buf);
            tags: for (sprite_sheet.tags) |t| {
                inline for (@typeInfo(EnumType).@"enum".fields) |f| {
                    if (std.mem.eql(u8, f.name, t.name.constSlice())) {
                        const kind = std.meta.stringToEnum(EnumType, f.name).?;
                        const render_frame = ret.getRenderFrame(kind).?;
                        const cropped_dims = ret.sprite_dims_cropped.?.getPtr(kind);
                        cropped_dims.* = render_frame.size.toV2f();
                        for (0..u.as(usize, render_frame.size.x)) |x_off| {
                            const x = render_frame.pos.x + u.as(i32, x_off);
                            const y = render_frame.pos.y;
                            const color: draw.Coloru = image_buf.data[u.as(usize, x + y * sprite_sheet.texture.dims.x)];
                            if (color.eql(crop_color)) {
                                cropped_dims.x = u.as(f32, x - render_frame.pos.x);
                                break;
                            }
                        }
                        for (0..u.as(usize, render_frame.size.y)) |y_off| {
                            const y = render_frame.pos.y + u.as(i32, y_off);
                            const x = render_frame.pos.x;
                            const color: draw.Coloru = image_buf.data[u.as(usize, x + y * sprite_sheet.texture.dims.x)];
                            if (color.eql(crop_color)) {
                                cropped_dims.y = u.as(f32, y - render_frame.pos.y);
                                break;
                            }
                        }
                        continue :tags;
                    }
                }
            }
            return ret;
        }
        pub fn getRenderFrame(self: @This(), kind: EnumType) ?sprites.RenderFrame {
            if (self.sprite_indices.get(kind)) |idx| {
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

pub const MiscIcon = enum {
    pub const dims = Item.icon_dims;

    discard,
    hourglass_up,
    hourglass_down,
    cards,
    gold_stacks,
    knife,
};

pub const TileMapIdxBuf = std.BoundedArray(usize, 16);

pub const SFX = enum {
    thwack,
    spell_casting,
    spell_cast,
    spell_fizzle,
};

pub const ShaderName = enum {
    tile_foreground_fade,
    fog_blur,
};
pub const ShaderArr = std.EnumArray(ShaderName, Platform.Shader);

pub const FontName = enum {
    alagard,
    pixeloid,
    seven_x_five,
};
pub const FontArr = std.EnumArray(FontName, Platform.Font);

pub const MusicName = enum {
    dungongnu,
};
pub const MusicArr = std.EnumArray(MusicName, Platform.Sound);

pub const RoomKind = enum {
    testu,
    first,
    smol,
    big,
    boss,
};

// iterates over files in a directory, with a given suffix (including dot, e.g. ".json")
pub fn FileWalkerIterator(assets_rel_dir: []const u8, file_suffix: []const u8) type {
    return struct {
        allocator: std.mem.Allocator,
        dir: std.fs.Dir,
        walker: std.fs.Dir.Walker,

        pub fn init(allocator: std.mem.Allocator) Error!@This() {
            const plat = App.getPlat();
            const path = try u.bufPrintLocal("{s}/{s}", .{ plat.assets_path, assets_rel_dir });
            var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch |err| {
                Log.err("Error opening dir \"{s}\"", .{path});
                Log.errorAndStackTrace(err);
                return Error.FileSystemFail;
            };
            const walker = try dir.walk(allocator);

            return .{
                .allocator = allocator,
                .dir = dir,
                .walker = walker,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.walker.deinit();
            self.dir.close();
        }

        pub fn nextFile(self: *@This()) Error!?std.fs.File {
            while (self.walker.next() catch return Error.FileSystemFail) |entry| {
                if (!std.mem.endsWith(u8, entry.basename, file_suffix)) continue;
                const file = self.dir.openFile(entry.basename, .{}) catch return Error.FileSystemFail;
                return file;
            }
            return null;
        }

        pub fn nextFileAsOwnedString(self: *@This()) Error!?[]u8 {
            while (self.walker.next() catch return Error.FileSystemFail) |entry| {
                if (!std.mem.endsWith(u8, entry.basename, file_suffix)) continue;
                const file = self.dir.openFile(entry.basename, .{}) catch return Error.FileSystemFail;
                const str = file.readToEndAlloc(self.allocator, 8 * 1024 * 1024) catch return Error.FileSystemFail;
                return str;
            }
            return null;
        }

        pub fn next(self: *@This()) Error!?struct { basename: []const u8, owned_string: []u8 } {
            while (self.walker.next() catch return Error.FileSystemFail) |entry| {
                if (!std.mem.endsWith(u8, entry.basename, file_suffix)) continue;
                const file = self.dir.openFile(entry.basename, .{}) catch return Error.FileSystemFail;
                const str = file.readToEndAlloc(self.allocator, 8 * 1024 * 1024) catch return Error.FileSystemFail;
                return .{
                    .basename = entry.basename,
                    .owned_string = str,
                };
            }
            return null;
        }
    };
}

tilesets: std.ArrayList(TileSet),
tilemaps: std.ArrayList(TileMap),
creature_protos: std.EnumArray(Thing.CreatureKind, Thing),
creature_sprite_sheets: AllCreatureSpriteSheetArrays,
creature_anims: AllCreatureAnimArrays,
vfx_sprite_sheets: std.ArrayList(SpriteSheet),
vfx_sprite_sheet_mappings: sprites.VFXAnim.IdxMapping,
vfx_anims: std.ArrayList(sprites.VFXAnim),
vfx_anim_mappings: sprites.VFXAnim.IdxMapping,
spell_icons: EnumSpriteSheet(Spell.Kind),
item_icons: EnumSpriteSheet(Item.Kind),
misc_icons: EnumSpriteSheet(MiscIcon),
spell_tags_icons: EnumSpriteSheet(Spell.Tag.SpriteEnum),
text_icons: EnumSpriteSheet(icon_text.Icon),
card_sprites: EnumSpriteSheet(Spell.CardSpriteEnum),
card_mana_cost: EnumSpriteSheet(Spell.ManaCost.SpriteEnum),
sounds: std.EnumArray(SFX, ?Platform.Sound),
music: MusicArr,
shaders: ShaderArr,
fonts: FontArr,
// roooms
room_kind_tilemaps: std.EnumArray(RoomKind, TileMapIdxBuf),

pub fn init() Error!*Data {
    const plat = App.getPlat();
    const data = plat.heap.create(Data) catch @panic("Out of memory");
    data.vfx_anims = @TypeOf(data.vfx_anims).init(plat.heap);
    data.vfx_sprite_sheets = @TypeOf(data.vfx_sprite_sheets).init(plat.heap);
    data.tilesets = @TypeOf(data.tilesets).init(plat.heap);
    data.tilemaps = @TypeOf(data.tilemaps).init(plat.heap);
    try data.reload();
    return data;
}

pub fn getVFXAnim(self: *Data, sheet_name: sprites.VFXAnim.SheetName, anim_name: sprites.AnimName) ?sprites.VFXAnim {
    if (self.vfx_anim_mappings.getPtr(sheet_name).get(anim_name)) |idx| {
        return self.vfx_anims.items[idx];
    }
    return null;
}

pub fn getVFXSpriteSheet(self: *Data, sheet_name: sprites.VFXAnim.SheetName, anim_name: sprites.AnimName) ?SpriteSheet {
    if (self.vfx_sprite_sheet_mappings.getPtr(sheet_name).get(anim_name)) |idx| {
        return self.vfx_sprite_sheets.items[idx];
    }
    return null;
}

pub fn getCreatureAnim(self: *Data, creature_kind: sprites.CreatureAnim.Kind, anim_kind: sprites.AnimName) ?sprites.CreatureAnim {
    return self.creature_anims.get(creature_kind).get(anim_kind);
}

pub fn getCreatureAnimOrDefault(self: *Data, creature_kind: sprites.CreatureAnim.Kind, anim_kind: sprites.AnimName) ?sprites.CreatureAnim {
    if (self.creature_anims.get(creature_kind).get(anim_kind)) |a| {
        return a;
    }
    return self.creature_anims.get(.creature).get(anim_kind);
}

pub fn getCreatureAnimSpriteSheet(self: *Data, creature_kind: sprites.CreatureAnim.Kind, anim_kind: sprites.AnimName) ?SpriteSheet {
    return self.creature_sprite_sheets.get(creature_kind).get(anim_kind);
}

pub fn getCreatureAnimSpriteSheetOrDefault(self: *Data, creature_kind: sprites.CreatureAnim.Kind, anim_kind: sprites.AnimName) ?SpriteSheet {
    if (self.creature_sprite_sheets.get(creature_kind).get(anim_kind)) |s| {
        return s;
    }
    return self.creature_sprite_sheets.get(.creature).get(anim_kind);
}

pub fn loadSounds(self: *Data) Error!void {
    const plat = App.getPlat();
    self.sounds = @TypeOf(self.sounds).initFill(null);
    const list = [_]struct { SFX, []const u8 }{
        .{ .thwack, "thwack.wav" },
        .{ .spell_casting, "casting.wav" },
        .{ .spell_cast, "cast-end.wav" },
    };
    for (list) |s| {
        self.sounds.getPtr(s[0]).* = try plat.loadSound(s[1]);
    }
}

pub fn loadSpriteSheetFromJsonString(sheet_filename: []const u8, json_string: []u8, assets_rel_dir_path: []const u8) Error!SpriteSheet {
    const plat = App.getPlat();
    //std.debug.print("{s}\n", .{s});
    var scanner = std.json.Scanner.initCompleteInput(plat.heap, json_string);
    var tree = std.json.Value.jsonParse(plat.heap, &scanner, .{ .max_value_len = json_string.len }) catch return Error.ParseFail;
    // TODO I guess tree just leaks rn? use arena?

    const meta = tree.object.get("meta").?.object;
    const image_filename = meta.get("image").?.string;
    const image_path = try u.bufPrintLocal("{s}/{s}", .{ assets_rel_dir_path, image_filename });

    var sheet = SpriteSheet{};
    var it_dot = std.mem.tokenizeScalar(u8, sheet_filename, '.');
    const sheet_name = it_dot.next().?;
    sheet.name = try @TypeOf(sheet.name).fromSlice(sheet_name);
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
            .name = try @TypeOf(sheet.tags[0].name).fromSlice(name),
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
                            m.name = try @TypeOf(m.name).fromSlice(key);
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
                                m.data.string = try @TypeOf(m.data.string).fromSlice(val);
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

pub fn loadSpriteSheetFromJsonPath(assets_rel_dir: []const u8, json_file_name: []const u8) Error!SpriteSheet {
    const plat = App.getPlat();
    const path = try u.bufPrintLocal("{s}/{s}/{s}", .{ plat.assets_path, assets_rel_dir, json_file_name });
    const icons_json = std.fs.cwd().openFile(path, .{}) catch return Error.FileSystemFail;
    const str = icons_json.readToEndAlloc(plat.heap, 8 * 1024 * 1024) catch return Error.FileSystemFail;
    defer plat.heap.free(str);
    const sheet = try loadSpriteSheetFromJsonString(json_file_name, str, assets_rel_dir);
    return sheet;
}

pub fn loadCreatureSpriteSheets(self: *Data) Error!void {
    const plat = App.getPlat();

    self.creature_anims = @TypeOf(self.creature_anims).initFill(CreatureAnimArray.initFill(null));
    self.creature_sprite_sheets = @TypeOf(self.creature_sprite_sheets).initFill(CreatureSpriteSheetArray.initFill(null));

    var file_it = try FileWalkerIterator("images/creature", ".json").init(plat.heap);
    defer file_it.deinit();

    while (try file_it.next()) |s| {
        defer plat.heap.free(s.owned_string);

        const sheet = try loadSpriteSheetFromJsonString(s.basename, s.owned_string, "images/creature");

        var it_dash = std.mem.tokenizeScalar(u8, sheet.name.constSlice(), '-');
        const creature_name = it_dash.next().?;
        const creature_kind = std.meta.stringToEnum(sprites.CreatureAnim.Kind, creature_name).?;
        const anim_name = it_dash.next().?;
        const anim_kind = std.meta.stringToEnum(sprites.AnimName, anim_name).?;
        self.creature_sprite_sheets.getPtr(creature_kind).getPtr(anim_kind).* = sheet;
        if (anim_kind == .idle) {
            const none_sheet = self.creature_sprite_sheets.getPtr(creature_kind).getPtr(.none);
            if (none_sheet.* == null) {
                none_sheet.* = sheet;
            }
        }

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
                const y = m.asf32() catch continue;
                const x = u.as(f32, sheet.frames[0].size.x) * 0.5;
                anim.origin = .{ .offset = v2f(x, y) };
                continue;
            }
            if (std.mem.eql(u8, m_name, "cast-y")) {
                anim.cast_offset.y = m.asf32() catch continue;
                continue;
            }
            if (std.mem.eql(u8, m_name, "cast-x")) {
                anim.cast_offset.x = m.asf32() catch continue;
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

            const event_info = @typeInfo(sprites.AnimEvent.Kind);
            inline for (event_info.@"enum".fields) |f| {
                if (std.mem.eql(u8, m_name, f.name)) {
                    //std.debug.print("Adding event '{s}' on frame {}\n", .{ f.name, m.data.int });
                    anim.events.append(.{
                        .frame = u.as(i32, m.data.int),
                        .kind = @enumFromInt(f.value),
                    }) catch {
                        Log.warn("Skipped adding anim event \"{s}\"; buffer full", .{f.name});
                    };
                    continue :meta_blk;
                }
            }
        }
        self.creature_anims.getPtr(creature_kind).getPtr(anim_kind).* = anim;
        if (anim_kind == .idle) {
            const none_anim = self.creature_anims.getPtr(creature_kind).getPtr(.none);
            if (none_anim.* == null) {
                none_anim.* = anim;
            }
        }
    }
}

pub fn loadVFXSpriteSheets(self: *Data) Error!void {
    const plat = App.getPlat();

    self.vfx_anims.clearRetainingCapacity();
    self.vfx_anim_mappings = @TypeOf(self.vfx_anim_mappings).initFill(sprites.VFXAnim.AnimNameIdxMapping.initFill(null));
    self.vfx_sprite_sheets.clearRetainingCapacity();
    self.vfx_sprite_sheet_mappings = @TypeOf(self.vfx_sprite_sheet_mappings).initFill(sprites.VFXAnim.AnimNameIdxMapping.initFill(null));

    var file_it = try FileWalkerIterator("images/vfx", ".json").init(plat.heap);
    defer file_it.deinit();

    while (try file_it.next()) |s| {
        defer plat.heap.free(s.owned_string);

        const sheet = try loadSpriteSheetFromJsonString(s.basename, s.owned_string, "images/vfx");
        const sheet_idx = self.vfx_sprite_sheets.items.len;
        try self.vfx_sprite_sheets.append(sheet);

        if (std.meta.stringToEnum(sprites.VFXAnim.SheetName, sheet.name.constSlice())) |vfx_sheet_name| {
            // sprite sheet to vfx anims
            for (sheet.tags) |tag| {
                if (std.meta.stringToEnum(sprites.AnimName, tag.name.constSlice())) |vfx_anim_name| {
                    var anim: sprites.VFXAnim = .{
                        .sheet_name = vfx_sheet_name,
                        .anim_name = vfx_anim_name,
                        .start_frame = tag.from_frame,
                        .num_frames = tag.to_frame - tag.from_frame + 1,
                    };

                    meta_blk: for (sheet.meta) |m| {
                        const m_name = m.name.constSlice();
                        //std.debug.print("Meta '{s}'\n", .{m_name});

                        if (std.mem.eql(u8, m_name, "pivot-y")) {
                            const y = m.asf32() catch continue;
                            const x = u.as(f32, sheet.frames[0].size.x) * 0.5;
                            anim.origin = .{ .offset = v2f(x, y) };
                            continue;
                        }
                        const event_info = @typeInfo(sprites.AnimEvent.Kind);
                        inline for (event_info.@"enum".fields) |f| {
                            if (std.mem.eql(u8, m_name, f.name)) {
                                //std.debug.print("Adding event '{s}' on frame {}\n", .{ f.name, m.data.int });
                                anim.events.append(.{
                                    .frame = u.as(i32, m.data.int),
                                    .kind = @enumFromInt(f.value),
                                }) catch {
                                    Log.err("Skipped adding vfx anim event \"{s}\"; buffer full", .{f.name});
                                };
                                continue :meta_blk;
                            }
                        }
                    }
                    const anim_idx = self.vfx_anims.items.len;
                    try self.vfx_anims.append(anim);
                    self.vfx_sprite_sheet_mappings.getPtr(vfx_sheet_name).getPtr(vfx_anim_name).* = sheet_idx;
                    self.vfx_anim_mappings.getPtr(vfx_sheet_name).getPtr(vfx_anim_name).* = anim_idx;
                } else {
                    Log.warn("Unknown vfx anim skipped: {s}", .{tag.name.constSlice()});
                }
            }
        } else {
            Log.warn("Unknown vfx spritesheet skipped: {s}", .{sheet.name.constSlice()});
        }
    }
}

pub fn loadSpriteSheets(self: *Data) Error!void {
    try self.loadCreatureSpriteSheets();
    try self.loadVFXSpriteSheets();
    self.item_icons = try @TypeOf(self.item_icons).init(try loadSpriteSheetFromJsonPath("images/ui", "item_icons.json"));
    self.misc_icons = try @TypeOf(self.misc_icons).init(try loadSpriteSheetFromJsonPath("images/ui", "misc-icons.json"));
    self.spell_icons = try @TypeOf(self.spell_icons).init(try loadSpriteSheetFromJsonPath("images/ui", "spell-icons.json"));
    self.spell_tags_icons = try @TypeOf(self.spell_tags_icons).initCropped(try loadSpriteSheetFromJsonPath("images/ui", "spell-tags-icons.json"), .magenta);
    self.text_icons = try @TypeOf(self.text_icons).initCropped(try loadSpriteSheetFromJsonPath("images/ui", "small_text_icons.json"), .magenta);
    self.card_sprites = try @TypeOf(self.card_sprites).init(try loadSpriteSheetFromJsonPath("images/ui", "card.json"));
    self.card_mana_cost = try @TypeOf(self.card_mana_cost).initCropped(try loadSpriteSheetFromJsonPath("images/ui", "card-mana-cost.json"), .magenta);
}

pub fn loadTileSetFromJsonString(tileset: *TileSet, json_string: []u8, assets_rel_path: []const u8) Error!void {
    const plat = App.getPlat();
    //std.debug.print("{s}\n", .{s});
    var scanner = std.json.Scanner.initCompleteInput(plat.heap, json_string);
    const _tree = std.json.Value.jsonParse(plat.heap, &scanner, .{ .max_value_len = json_string.len }) catch return Error.ParseFail;
    var tree = _tree.object;
    // TODO I guess tree just leaks rn? use arena?

    const image_filename = tree.get("image").?.string;
    const image_path = try u.bufPrintLocal("{s}/{s}", .{ assets_rel_path, image_filename });

    const name = tree.get("name").?.string;
    const tile_dims = V2i.iToV2i(
        i64,
        tree.get("tilewidth").?.integer,
        tree.get("tileheight").?.integer,
    );
    const image_dims = V2i.iToV2i(
        i64,
        tree.get("imagewidth").?.integer,
        tree.get("imageheight").?.integer,
    );
    const columns = tree.get("columns").?.integer;
    const sheet_dims = V2i.iToV2i(i64, columns, @divExact(image_dims.y, tile_dims.y));

    tileset.* = .{
        .name = try TileSet.NameBuf.fromSlice(name),
        .sheet_dims = sheet_dims,
        .tile_dims = tile_dims,
        .texture = try plat.loadTexture(image_path),
    };
    assert(tileset.texture.dims.x == image_dims.x);
    assert(tileset.texture.dims.y == image_dims.y);

    try tileset.tiles.resize(u.as(usize, tileset.sheet_dims.x * tileset.sheet_dims.y));
    if (tree.get("tiles")) |tiles| {
        for (tiles.array.items) |t| {
            const id = t.object.get("id").?.integer;
            const idx = u.as(usize, id);
            const props = t.object.get("properties").?.array;
            var prop = TileSet.TileProperties{};
            for (props.items) |p| {
                const prop_name = p.object.get("name").?.string;
                const val = p.object.get("value").?.string;
                const type_info = @typeInfo(TileSet.TileProperties);
                inline for (type_info.@"struct".fields) |f| {
                    if (std.mem.eql(u8, prop_name, f.name)) {
                        var prop_it = std.mem.tokenizeScalar(u8, val, ',');
                        var c_i: usize = 0;
                        while (prop_it.next()) |c| {
                            const set: bool = if (c[0] == '0') false else true;
                            @field(prop, f.name).getPtr(@enumFromInt(c_i)).* = set;
                            c_i += 1;
                        }
                    }
                }
            }
            assert(idx < tileset.tiles.len);
            tileset.tiles.buffer[idx] = prop;
        }
    }
}

pub fn loadTileSets(self: *Data) Error!void {
    const plat = App.getPlat();

    for (self.tilesets.items) |t| {
        plat.unloadTexture(t.texture);
    }
    self.tilesets.clearRetainingCapacity();

    var file_it = try FileWalkerIterator("maps/tilesets", ".tsj").init(plat.heap);
    defer file_it.deinit();

    while (try file_it.nextFileAsOwnedString()) |str| {
        defer plat.heap.free(str);
        const id = u.as(i32, self.tilesets.items.len);
        const tileset = try self.tilesets.addOne();
        try loadTileSetFromJsonString(tileset, str, "maps/tilesets");
        tileset.id = id;
        Log.info("Loaded tileset: {s}", .{tileset.name.constSlice()});
    }
}

pub fn loadTileMapFromJsonString(tilemap: *TileMap, json_string: []u8) Error!void {
    const plat = App.getPlat();
    //std.debug.print("{s}\n", .{s});
    var scanner = std.json.Scanner.initCompleteInput(plat.heap, json_string);
    const _tree = std.json.Value.jsonParse(plat.heap, &scanner, .{ .max_value_len = json_string.len }) catch return Error.ParseFail;
    var tree = _tree.object;
    // TODO I guess tree just leaks rn? use arena?

    // TODO use?
    const tile_dims = V2i.iToV2i(
        i64,
        tree.get("tilewidth").?.integer,
        tree.get("tileheight").?.integer,
    );
    _ = tile_dims;
    const map_dims = V2i.iToV2i(
        i64,
        tree.get("width").?.integer,
        tree.get("height").?.integer,
    );
    const game_dims = map_dims.sub(v2i(1, 1));

    tilemap.* = .{
        .dims_tiles = map_dims,
        .dims_game = game_dims,
        .rect_dims = map_dims.toV2f().scale(TileMap.tile_sz_f),
    };
    var game_tile_coord: V2i = .{};
    for (0..u.as(usize, tilemap.dims_game.x * tilemap.dims_game.y)) |_| {
        tilemap.game_tiles.append(.{ .coord = game_tile_coord }) catch unreachable;
        game_tile_coord.x += 1;
        if (game_tile_coord.x >= tilemap.dims_game.x) {
            game_tile_coord.x = 0;
            game_tile_coord.y += 1;
        }
    }
    if (tree.get("properties")) |_props| {
        const props = _props.array;
        for (props.items) |p| {
            const p_name = p.object.get("name").?.string;
            if (std.mem.eql(u8, p_name, "name")) {
                const name = p.object.get("value").?.string;
                tilemap.name = try TileMap.NameBuf.fromSlice(name);
                continue;
            } else if (std.mem.eql(u8, p_name, "room_kind")) {
                const kind_str = p.object.get("value").?.string;
                tilemap.kind = std.meta.stringToEnum(RoomKind, kind_str).?;
                continue;
            }
        }
    }
    {
        // get tilesets without looking them up yet
        const tilesets = tree.get("tilesets").?.array;
        for (tilesets.items) |ts| {
            const first_gid = ts.object.get("firstgid").?.integer;
            const tileset_path = ts.object.get("source").?.string;
            const tileset_file_name = std.fs.path.basename(tileset_path);
            const tileset_name = tileset_file_name[0..(tileset_file_name.len - 4)];
            try tilemap.tilesets.append(.{
                .name = try TileSet.NameBuf.fromSlice(tileset_name),
                .first_gid = u.as(usize, first_gid),
            });
        }
    }
    {
        const startsWith = std.mem.startsWith;
        const layers = tree.get("layers").?.array;
        var above_objects = false;
        for (layers.items) |_layer| {
            const layer = _layer.object;
            const visible = layer.get("visible").?.bool;
            if (!visible) continue;
            const kind = layer.get("type").?.string;
            if (std.mem.eql(u8, kind, "tilelayer")) {
                var tile_layer = TileMap.TileLayer{
                    .above_objects = above_objects,
                };
                // TODO x,y,width,height?
                const data = layer.get("data").?.array;
                for (data.items) |d| {
                    const tile_gid = d.integer;
                    try tile_layer.tiles.append(.{
                        .idx = u.as(TileMap.TileIndex, tile_gid),
                    });
                }
                try tilemap.tile_layers.append(tile_layer);
            } else if (std.mem.eql(u8, kind, "objectgroup")) {
                above_objects = true;
                const objects = layer.get("objects").?.array;
                for (objects.items) |_obj| {
                    const obj = _obj.object;
                    if (!obj.get("visible").?.bool) continue;
                    if (obj.get("point").?.bool) {
                        const obj_name = obj.get("name").?.string;
                        // TODO clean up arrgh
                        // transform map pixel pos to game tile pixel pos
                        const pos = v2f(
                            u.as(f32, switch (obj.get("x").?) {
                                .float => |f| f,
                                .integer => |i| u.as(f64, i),
                                else => return Error.ParseFail,
                            }),
                            u.as(f32, switch (obj.get("y").?) {
                                .float => |f| f,
                                .integer => |i| u.as(f64, i),
                                else => return Error.ParseFail,
                            }),
                        ).scale(core.game_sprite_scaling).sub(TileMap.tile_dims_2);
                        if (startsWith(u8, obj_name, "creature")) {
                            var it = std.mem.tokenizeScalar(u8, obj_name, ':');
                            _ = it.next() orelse return Error.ParseFail;
                            const creature_kind_str = it.next() orelse return Error.ParseFail;
                            try tilemap.creatures.append(.{
                                .kind = std.meta.stringToEnum(Thing.CreatureKind, creature_kind_str) orelse return Error.ParseFail,
                                .pos = pos,
                            });
                        } else if (startsWith(u8, obj_name, "exit")) {
                            try tilemap.exits.append(pos);
                        } else if (startsWith(u8, obj_name, "spawn")) {
                            try tilemap.wave_spawns.append(pos);
                        }
                    } else {
                        // ??
                        @panic("unimplemented");
                    }
                }
            }
        }
    }
}

pub fn tileIdxAndTileSetRefToTileProperties(self: *Data, tileset_ref: TileMap.TileSetReference, tile_idx: usize) ?Data.TileSet.TileProperties {
    assert(tileset_ref.data_idx < self.tilesets.items.len);
    const tileset = &self.tilesets.items[tileset_ref.data_idx];
    assert(tile_idx >= tileset_ref.first_gid);
    const tileset_tile_idx = tile_idx - tileset_ref.first_gid;
    assert(tileset_tile_idx < tileset.tiles.len);
    return tileset.tiles.get(tileset_tile_idx);
}

pub fn loadTileMaps(self: *Data) Error!void {
    const plat = App.getPlat();

    self.tilemaps.clearRetainingCapacity();

    var file_it = try FileWalkerIterator("maps", ".tmj").init(plat.heap);
    defer file_it.deinit();

    while (try file_it.nextFileAsOwnedString()) |str| {
        defer plat.heap.free(str);
        const id = u.as(i32, self.tilemaps.items.len);
        const tilemap: *TileMap = try self.tilemaps.addOne();
        try loadTileMapFromJsonString(tilemap, str);
        tilemap.id = id;
        // init tilemap refs
        for (tilemap.tilesets.slice()) |*ts_ref| {
            for (self.tilesets.items) |*ts| {
                if (std.mem.eql(u8, ts_ref.name.constSlice(), ts.name.constSlice())) {
                    ts_ref.data_idx = u.as(usize, ts.id);
                    break;
                }
            }
        }
        // init game tiles
        for (tilemap.tile_layers.constSlice()) |layer| {
            if (layer.above_objects) continue;
            var tile_coord: V2i = .{};
            for (layer.tiles.constSlice()) |tile| {
                var props = blk: {
                    if (tilemap.tileIdxToTileSetRef(tile.idx)) |ref| {
                        break :blk self.tileIdxAndTileSetRefToTileProperties(ref, tile.idx);
                    }
                    break :blk null;
                };
                if (props) |*tile_props| {
                    inline for (std.meta.fields(TileSet.GameTileCorner)) |f| {
                        const corner: TileSet.GameTileCorner = @enumFromInt(f.value);
                        const dir = TileSet.GameTileCorner.dir_map.get(corner);
                        const game_tile_coord = tile_coord.add(dir);
                        if (tilemap.gameTileCoordToGameTile(game_tile_coord)) |game_tile| {
                            if (tile_props.colls.get(corner)) {
                                game_tile.coll_layers.insert(.wall);
                                game_tile.path_layers = TileMap.PathLayer.Mask.initEmpty();
                            }
                            if (tile_props.spikes.get(corner)) {
                                game_tile.coll_layers.insert(.spikes);
                                game_tile.path_layers.remove(.normal);
                            }
                        }
                    }
                }
                tile_coord.x += 1;
                if (tile_coord.x >= tilemap.dims_tiles.x) {
                    tile_coord.x = 0;
                    tile_coord.y += 1;
                }
            }
        }
        try tilemap.updateConnectedComponents();
        Log.info("Loaded tilemap: {s}", .{tilemap.name.constSlice()});
    }
}

pub fn loadShaders(self: *Data) Error!void {
    const plat = App.getPlat();
    // TODO deinit?

    self.shaders.getPtr(.tile_foreground_fade).* = try plat.loadShader(null, "tile_foreground_fade.fs");
    self.shaders.getPtr(.fog_blur).* = try plat.loadShader(null, "fog_blur.fs");
}

pub fn loadFonts(self: *Data) Error!void {
    const plat = App.getPlat();
    // TODO deinit?

    self.fonts.getPtr(.alagard).* = try plat.loadPixelFont("alagard.png", 16);
    self.fonts.getPtr(.pixeloid).* = try plat.loadPixelFont("PixeloidSans.ttf", 11);
    self.fonts.getPtr(.seven_x_five).* = try plat.loadPixelFont("7x5.ttf", 8);
}

pub fn loadMusic(self: *Data) Error!void {
    const plat = App.getPlat();
    self.music.getPtr(.dungongnu).* = try plat.loadMusic("dungongnu.wav");
}

pub fn reload(self: *Data) Error!void {
    self.loadSpriteSheets() catch |err| Log.warn("failed to load all sprites: {any}", .{err});
    self.loadSounds() catch |err| Log.warn("failed to load all sounds: {any}", .{err});
    self.loadMusic() catch |err| Log.warn("failed to load all music: {any}", .{err});
    inline for (@typeInfo(creatures.Kind).@"enum".fields) |f| {
        const kind: creatures.Kind = @enumFromInt(f.value);
        self.creature_protos.getPtr(kind).* = creatures.proto_fns.get(kind)();
    }
    self.loadTileSets() catch |err| Log.warn("failed to load all tilesets: {any}", .{err});
    self.loadTileMaps() catch |err| Log.warn("failed to load all tilemaps: {any}", .{err});
    inline for (std.meta.fields(RoomKind)) |f| {
        const kind: RoomKind = @enumFromInt(f.value);
        const tilemaps = self.room_kind_tilemaps.getPtr(kind);
        tilemaps.clear();
        for (self.tilemaps.items) |tilemap| {
            if (tilemap.kind == kind) {
                try tilemaps.append(u.as(usize, tilemap.id));
            }
        }
    }
    self.loadShaders() catch |err| Log.warn("failed to load all shaders: {any}", .{err});
    self.loadFonts() catch |err| Log.warn("failed to load all fonts: {any}", .{err});
}
