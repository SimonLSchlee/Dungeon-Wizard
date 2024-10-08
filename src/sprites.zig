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

const Thing = @This();
const App = @import("App.zig");
const getPlat = App.getPlat;
const Data = @import("Data.zig");

pub const CreatureAnim = struct {
    pub const Kind = enum {
        wizard,
        troll,
        gobbow,
    };
    pub const AnimKind = enum {
        idle,
        move,
        attack,
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
    pub const RenderFrame = struct {
        pos: V2i,
        size: V2i,
        texture: Platform.Texture2D,
        origin: draw.TextureOrigin,
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
    origin: draw.TextureOrigin = .center,
};

pub const CreatureAnimKindSet = std.EnumSet(CreatureAnim.AnimKind);

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

    pub fn getCurrRenderFrame(self: *const CreatureAnimator, dir: V2f) CreatureAnim.RenderFrame {
        const sprite_sheet = App.get().data.creature_sprite_sheets.get(self.creature_kind).get(self.curr_anim).?;
        const anim = App.get().data.creature_anims.get(self.creature_kind).get(self.curr_anim).?;
        const num_dirs_f = utl.as(f32, anim.num_dirs);
        const angle_inc = utl.tau / num_dirs_f;
        const shifted_dir = dir.rotRadians(angle_inc * 0.5);
        const shifted_angle = shifted_dir.toAngleRadians();
        const a = utl.normalizeRadians0_Tau(shifted_angle);
        assert(a >= 0 and a <= utl.tau);
        const f = a / utl.tau;
        const i = f * num_dirs_f;
        assert(i >= 0 and i < num_dirs_f);
        const dir_index = utl.as(i32, @floor(f * num_dirs_f));
        assert(dir_index >= 0 and dir_index < anim.num_dirs);
        const frame_idx = utl.as(usize, dir_index * anim.num_frames + self.curr_anim_frame);
        const ssframe: Data.SpriteSheet.Frame = sprite_sheet.frames[frame_idx];
        const rframe = CreatureAnim.RenderFrame{
            .pos = ssframe.pos,
            .size = ssframe.size,
            .texture = sprite_sheet.texture,
            .origin = anim.origin,
        };

        return rframe;
    }

    pub fn play(self: *CreatureAnimator, anim_kind: CreatureAnim.AnimKind, params: PlayParams) std.EnumSet(CreatureAnim.Event.Kind) {
        var ret = std.EnumSet(CreatureAnim.Event.Kind).initEmpty();
        const anim = if (App.get().data.creature_anims.get(self.creature_kind).get(anim_kind)) |a| a else {
            std.debug.print("{s}: WARNING: tried to play non-existent anim: {any}\n", .{ @src().file, anim_kind });
            return ret;
        };

        if (params.reset or self.curr_anim != anim_kind) {
            self.anim_tick = 0;
            self.tick_in_frame = 0;
            self.curr_anim_frame = 0;
        }
        self.curr_anim = anim_kind;

        const sprite_sheet = App.get().data.creature_sprite_sheets.get(self.creature_kind).get(self.curr_anim).?;
        // NOTE: We assume all the dirs of the anim are the same durations in each frame; not a big deal probably(!)
        const ssframe: Data.SpriteSheet.Frame = sprite_sheet.frames[utl.as(usize, self.curr_anim_frame)];
        const frame_ticks_f = utl.as(f32, ssframe.duration_ms) * 0.06; // TODO! 60 fps means 1 / 16.66ms == 0.06
        const frame_ticks = utl.as(i32, frame_ticks_f);

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
