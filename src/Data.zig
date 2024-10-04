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
const Data = @This();

const test_levels = [_][]const u8{
    \\#########################
    \\#                       #
    \\#                       #
    \\#                       #
    \\#                       #
    \\#                       #
    \\#       p   t           #
    \\#                       #
    \\#                       #
    \\#                       #
    \\#                       #
    \\#                       #
    \\#########################
    ,
    \\#######################################################
    \\##           ###    ##          ####                 ##
    \\#         ##  #          # ##   #       ####    ### ###
    \\####     ##   #         ####        # ####           ##
    \\#######  t      ##      #                       #######
    \\#AAAAA##         ####      #####     ##      ####BBBBB#
    \\#AAAAA p     #         ########      #   #   ####BBBBB#
    \\#AAAAA    #    ##   ############     #####       BBBBB#
    \\#AAAAA##    #   #      ########     ##           BBBBB#
    \\#AAAAA##    ##     ##     ### ##  ##         ####BBBBB#
    \\#######     ###            #       # # ###   ##########
    \\####  #   #         ##        #        ##      ########
    \\#      #  ##     ### ##     ###   ##     #            #
    \\#   #           #     ##     ####  ####        #    ###
    \\#######################################################
    ,
};

pub const CreatureAnimArray = std.EnumArray(sprites.CreatureAnim.AnimKind, ?sprites.CreatureAnim);
pub const AllCreatureAnimArrays = std.EnumArray(sprites.CreatureAnim.Kind, CreatureAnimArray);
pub const CreatureSpriteSheetArray = std.EnumArray(sprites.CreatureAnim.AnimKind, ?sprites.SpriteSheet);
pub const AllCreatureSpriteSheetArrays = std.EnumArray(sprites.CreatureAnim.Kind, CreatureSpriteSheetArray);

levels: []const []const u8 = undefined,
things: std.EnumMap(Thing.Kind, Thing) = undefined,
//sprite_sheets: std.StringArrayHashMap(sprites.SpriteSheet) = undefined,
creature_sprite_sheets: AllCreatureSpriteSheetArrays = undefined,
creature_anims: AllCreatureAnimArrays = undefined,

pub fn init() Error!*Data {
    const plat = App.getPlat();
    const data = plat.heap.create(Data) catch @panic("Out of memory");
    data.* = .{};
    try data.reload();
    return data;
}

pub fn loadSpriteSheets(self: *Data) Error!void {
    const SpriteSheet = sprites.SpriteSheet;
    const plat = App.getPlat();

    self.creature_anims = @TypeOf(self.creature_anims).initFill(CreatureAnimArray.initFill(null));
    self.creature_sprite_sheets = @TypeOf(self.creature_sprite_sheets).initFill(CreatureSpriteSheetArray.initFill(null));

    var creature = std.fs.cwd().openDir("assets/images/creature", .{ .iterate = true }) catch return Error.FileSystemFail;
    defer creature.close();
    var walker = try creature.walk(plat.heap);
    defer walker.deinit();

    while (walker.next() catch return Error.FileSystemFail) |w_entry| {
        if (std.mem.endsWith(u8, w_entry.basename, ".json")) {
            var json_file = creature.openFile(w_entry.basename, .{}) catch return Error.FileSystemFail;
            const s = json_file.readToEndAlloc(plat.heap, 8 * 1024 * 1024) catch return Error.FileSystemFail;
            //std.debug.print("{s}\n", .{s});
            var scanner = std.json.Scanner.initCompleteInput(plat.heap, s);
            var tree = std.json.Value.jsonParse(plat.heap, &scanner, .{ .max_value_len = s.len }) catch return Error.ParseFail;
            // TODO I guess tree just leaks rn? use arena?

            const meta = tree.object.get("meta").?.object;
            const image_filename = meta.get("image").?.string;
            const image_path = try u.bufPrintLocal("creature/{s}", .{image_filename});

            var sheet = sprites.SpriteSheet{};
            var it_dot = std.mem.tokenizeScalar(u8, image_filename, '.');
            const sheet_name = it_dot.next().?;
            sheet.file_name = try @TypeOf(sheet.file_name).init(sheet_name);
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
                assert(from >= 0 and from < frames.items.len);
                assert(to >= from and to < frames.items.len);
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

            var it_dash = std.mem.tokenizeScalar(u8, sheet_name, '-');
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
            for (sheet.meta) |m| {
                if (std.mem.eql(u8, m.name.constSlice(), "pivot-y")) {
                    const y = switch (m.data) {
                        .int => |i| u.as(f32, i),
                        .float => |f| f,
                        .string => return Error.ParseFail,
                    };
                    const x = u.as(f32, sheet.frames[0].size.x) * 0.5;
                    anim.origin = .{ .offset = v2f(x, y) };
                }
            }
            self.creature_anims.getPtr(creature_kind).getPtr(anim_kind).* = anim;
        }
    }
}

pub fn reload(self: *Data) Error!void {
    loadSpriteSheets(self) catch std.debug.print("WARNING: failed to load all sprites\n", .{});
    self.levels = &test_levels;
    self.things = @TypeOf(self.things).init(
        .{
            .player = try @import("player.zig").protoype(),
            .troll = try @import("enemies.zig").troll(),
        },
    );
}
