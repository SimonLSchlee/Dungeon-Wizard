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
const Data = @import("Data.zig");
const Thing = @import("Thing.zig");

pub const RenderFrame = struct {
    pos: V2i,
    size: V2i,
    texture: Platform.Texture2D,
    origin: draw.TextureOrigin,
};

pub const RenderIconInfo = union(enum) {
    letter: struct {
        str: [1]u8,
        color: Colorf,
    },
    frame: RenderFrame,
};

pub const CreatureAnim = struct {
    pub const Kind = enum {
        creature, // misc anim
        wizard,
        dummy,
        bat,
        troll,
        gobbow,
        sharpboi,
        impling,
        acolyte,
    };
    pub const AnimKind = enum {
        idle,
        move,
        attack,
        charge,
        cast,
        hit,
        die,
    };
    pub const Event = struct {
        pub const Kind = enum {
            commit,
            hit,
            end,
        };
        kind: Event.Kind,
        frame: i32 = 0,
    };

    pub const kind_strings: Data.EnumToBoundedStringArrayType(Kind) = Data.enumToBoundedStringArray(Kind);
    pub const anim_kind_strings: Data.EnumToBoundedStringArrayType(AnimKind) = Data.enumToBoundedStringArray(AnimKind);

    creature_kind: Kind,
    anim_kind: AnimKind,
    num_frames: i32 = 1,
    // TODO
    events: std.BoundedArray(Event, 8) = .{},
    // equal to number of rows in SpriteSheet
    // power of 2, going anticlockwise
    // Thing.dir will get mapped to the appropriate sprite direction
    // 1
    // 2 = right/left
    // 4 = right/down/left/up
    // 8 = ...etc
    num_dirs: u8 = 1,
    // offset the 0th dir
    start_angle_rads: f32 = 0,
    origin: draw.TextureOrigin = .center,

    pub fn getRenderFrame(self: CreatureAnim, dir: V2f, anim_frame: i32) RenderFrame {
        const sprite_sheet: Data.SpriteSheet = App.get().data.getCreatureAnimSpriteSheetOrDefault(self.creature_kind, self.anim_kind).?;
        const num_dirs_f = utl.as(f32, self.num_dirs);
        const angle_inc = utl.tau / num_dirs_f;
        const shifted_dir = dir.rotRadians(angle_inc * 0.5 - self.start_angle_rads);
        const shifted_angle = shifted_dir.toAngleRadians();
        const a = utl.normalizeRadians0_Tau(shifted_angle);
        assert(a >= 0 and a <= utl.tau);
        const f = a / utl.tau;
        const i = f * num_dirs_f;
        assert(i >= 0 and i <= num_dirs_f);
        // i could be exactly num_dirs_f, mod it to wrap to 0
        const dir_index = @mod(utl.as(i32, @floor(i)), self.num_dirs);
        assert(dir_index >= 0 and dir_index < self.num_dirs);
        const frame_idx = utl.as(usize, dir_index * self.num_frames + anim_frame);
        const ssframe: Data.SpriteSheet.Frame = sprite_sheet.frames[frame_idx];
        const rframe = RenderFrame{
            .pos = ssframe.pos,
            .size = ssframe.size,
            .texture = sprite_sheet.texture,
            .origin = self.origin,
        };

        return rframe;
    }
};

pub const CreatureAnimKindSet = std.EnumSet(CreatureAnim.AnimKind);

pub const VFXAnim = struct {
    pub const SheetName = enum {
        spellcasting,
    };
    pub const AnimName = enum {
        basic_loop,
        basic_cast,
        basic_fizzle,
    };
    pub const AnimNameIdxMapping = std.EnumArray(AnimName, ?usize);
    pub const IdxMapping = std.EnumArray(SheetName, AnimNameIdxMapping);
    pub const Event = struct {
        pub const Kind = enum {
            end,
        };
        kind: Event.Kind,
        frame: i32 = 0,
    };

    sheet_name: SheetName,
    anim_name: AnimName,
    num_frames: i32 = 1,
    events: std.BoundedArray(Event, 8) = .{},
    origin: draw.TextureOrigin = .center,

    pub fn getRenderFrame(self: CreatureAnim, anim_frame: i32) RenderFrame {
        const sprite_sheet: Data.SpriteSheet = App.get().data.getCreatureAnimSpriteSheetOrDefault(self.creature_kind, self.anim_kind).?;
        // TODO
        const dir_index = 0;
        const frame_idx = utl.as(usize, dir_index * self.num_frames + anim_frame);
        const ssframe: Data.SpriteSheet.Frame = sprite_sheet.frames[frame_idx];
        const rframe = RenderFrame{
            .pos = ssframe.pos,
            .size = ssframe.size,
            .texture = sprite_sheet.texture,
            .origin = self.origin,
        };

        return rframe;
    }
};

pub const CreatureAnimator = struct {
    pub const PlayParams = struct {
        reset: bool = false, // always true if new anim played
        loop: bool = false,
    };

    creature_kind: CreatureAnim.Kind = .wizard,
    curr_anim: CreatureAnim.AnimKind = .idle,
    curr_anim_frame: i32 = 0,
    tick_in_frame: i32 = 0,
    anim_tick: i32 = 0,

    pub fn getTicksUntilEvent(self: *const CreatureAnimator, event: CreatureAnim.Event.Kind) ?i64 {
        const anim: CreatureAnim = App.get().data.getCreatureAnim(self.creature_kind, self.curr_anim).?;
        for (anim.events.constSlice()) |e| {
            if (e.kind == event) {
                const e_frame_idx = utl.as(usize, e.frame);
                if (e.frame <= self.curr_anim_frame) return null;
                const sprite_sheet: Data.SpriteSheet = App.get().data.getCreatureAnimSpriteSheet(self.creature_kind, self.curr_anim).?;
                const curr_frame_idx = utl.as(usize, self.curr_anim_frame);
                var num_ticks: i64 = core.ms_to_ticks(sprite_sheet.frames[curr_frame_idx].duration_ms) - self.tick_in_frame;
                for (sprite_sheet.frames[curr_frame_idx + 1 .. e_frame_idx]) |frame| {
                    num_ticks += core.ms_to_ticks(frame.duration_ms);
                }
                return num_ticks;
            }
        }
        return null;
    }

    pub fn getCurrRenderFrame(self: *const CreatureAnimator, dir: V2f) RenderFrame {
        const anim: CreatureAnim = App.get().data.getCreatureAnimOrDefault(self.creature_kind, self.curr_anim).?;
        return anim.getRenderFrame(dir, self.curr_anim_frame);
    }

    pub fn play(self: *CreatureAnimator, anim_kind: CreatureAnim.AnimKind, params: PlayParams) std.EnumSet(CreatureAnim.Event.Kind) {
        const data = App.get().data;
        var ret = std.EnumSet(CreatureAnim.Event.Kind).initEmpty();
        const anim = if (data.getCreatureAnimOrDefault(self.creature_kind, self.curr_anim)) |a| a else {
            std.debug.print("{s}: WARNING: tried to play non-existent creature anim: {any}, {any}\n", .{ @src().file, self.creature_kind, anim_kind });
            ret.insert(.end);
            return ret;
        };

        if (params.reset or self.curr_anim != anim_kind) {
            self.anim_tick = 0;
            self.tick_in_frame = 0;
            self.curr_anim_frame = 0;
        }
        self.curr_anim = anim_kind;

        const sprite_sheet = if (data.getCreatureAnimSpriteSheetOrDefault(self.creature_kind, self.curr_anim)) |s| s else {
            std.debug.print("{s}: WARNING: tried to get non-existent creature spritesheet: {any}, {any}\n", .{ @src().file, self.creature_kind, anim_kind });
            ret.insert(.end);
            return ret;
        };

        // NOTE: We assume all the dirs of the anim are the same durations in each frame; not a big deal probably(!)
        const ssframe: Data.SpriteSheet.Frame = sprite_sheet.frames[utl.as(usize, self.curr_anim_frame)];
        const frame_ticks = utl.as(i32, core.ms_to_ticks(ssframe.duration_ms));

        if (self.tick_in_frame >= frame_ticks) {
            // end of anim: last tick of frame, and on last frame
            if (self.curr_anim_frame >= anim.num_frames - 1) {
                if (params.loop) {
                    self.anim_tick = 0;
                    self.tick_in_frame = 0;
                    self.curr_anim_frame = 0;
                }
                ret.insert(.end);
                return ret;
            }
            self.curr_anim_frame += 1;
            self.tick_in_frame = 0;
        }

        // first tick of a frame; add frame events
        if (self.tick_in_frame == 0) {
            for (anim.events.constSlice()) |e| {
                if (self.curr_anim_frame == e.frame) {
                    ret.insert(e.kind);
                }
            }
        }

        // TODO self.anim_tick is useless?
        self.anim_tick += 1;
        self.tick_in_frame += 1;
        return ret;
    }
};
