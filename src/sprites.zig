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
const Log = App.Log;
const getPlat = App.getPlat;
const Data = @import("Data.zig");
const Thing = @import("Thing.zig");
const ImmUI = @import("ImmUI.zig");

pub const RenderFrame = struct {
    pos: V2i,
    size: V2i,
    texture: Platform.Texture2D,
    origin: draw.TextureOrigin,
    pub fn toTextureOpt(self: *const RenderFrame, scaling: f32) draw.TextureOpt {
        return .{
            .origin = self.origin,
            .src_pos = self.pos.toV2f(),
            .src_dims = self.size.toV2f(),
            .uniform_scaling = scaling,
        };
    }
};

pub const RenderIconInfo = union(enum) {
    letter: struct {
        str: [1]u8,
        color: Colorf,
    },
    frame: RenderFrame,

    pub fn unqRender(icon: *const RenderIconInfo, cmd_buf: *ImmUI.CmdBuf, pos: V2f, scaling: f32) Error!void {
        try icon.unqRenderTint(cmd_buf, pos, scaling, .white);
    }

    pub fn unqRenderTint(icon: *const RenderIconInfo, cmd_buf: *ImmUI.CmdBuf, pos: V2f, scaling: f32, tint: Colorf) Error!void {
        switch (icon.*) {
            .frame => |frame| {
                cmd_buf.append(.{ .texture = .{
                    .pos = pos,
                    .texture = frame.texture,
                    .opt = .{
                        .src_pos = frame.pos.toV2f(),
                        .src_dims = frame.size.toV2f(),
                        .uniform_scaling = scaling,
                        .tint = tint,
                        .round_to_pixel = true,
                    },
                } }) catch @panic("Fail to append texture cmd");
            },
            .letter => |letter| {
                cmd_buf.append(.{
                    .label = .{
                        .pos = pos,
                        .text = ImmUI.initLabel(&letter.str),
                        .opt = .{
                            .color = letter.color,
                            .size = utl.as(u32, 12 * scaling), // TODO idk, its placeholder anyway
                        },
                    },
                }) catch @panic("Fail to append label cmd");
            },
        }
    }
};

pub const AnimEvent = struct {
    pub const Kind = enum {
        commit,
        hit,
        end,
    };
    pub const Set = std.EnumSet(AnimEvent.Kind);
    kind: AnimEvent.Kind,
    frame: i32 = 0,
};

pub const DirectionalSpriteAnim = struct {
    pub const Dir = enum {
        E,
        SE,
        S,
        SW,
        W,
        NW,
        N,
        NE,
    };
    pub const dirs_list = utl.enumValueList(Dir);
    pub const max_dirs = dirs_list.len;
    pub const dir_suffixes = blk: {
        const arr = utl.enumValueList(Dir);
        var ret: [arr.len][]const u8 = undefined;
        for (arr, 0..) |d, i| {
            ret[i] = "-" ++ utl.enumToString(Dir, d);
        }
        break :blk ret;
    };
    data_ref: Data.Ref(DirectionalSpriteAnim) = .{}, // e.g. "wizard-move", with 4 directions "E","S","W","N"
    num_dirs: usize = 0,
    anims_by_dir: std.EnumArray(Dir, ?Data.Ref(SpriteAnim)) = std.EnumArray(Dir, ?Data.Ref(SpriteAnim)).initFill(null),

    pub fn dirToSpriteAnim(self: *const DirectionalSpriteAnim, dir: V2f) Data.Ref(SpriteAnim) {
        const max_dirs_f = utl.as(f32, max_dirs);
        //const num_dirs_f = utl.as(f32, self.num_dirs);
        //const angle_inc = utl.tau / max_dirs_f;
        //const shifted_dir = dir.rotRadians(angle_inc * 0.5); // - self.start_angle_rads);
        //const shifted_angle = shifted_dir.toAngleRadians();
        const a = utl.normalizeRadians0_Tau(dir.toAngleRadians());
        assert(a >= 0 and a <= utl.tau);
        const f = a / utl.tau;
        const d_i = f * max_dirs_f;
        assert(d_i >= 0 and d_i <= max_dirs_f);
        // accomplishes the same as an angle offset
        const shifted_d_i = d_i + 0.5;
        // d_i could be exactly max_dirs_f, mod it to wrap to 0
        const dir_idx = @mod(utl.as(usize, @floor(shifted_d_i)), max_dirs);
        const dir_enum: Dir = @enumFromInt(dir_idx);
        //assert(dir_idx >= 0 and dir_idx < max_dirs);
        //const dir_frac = d_i - utl.as(f32, dir_idx);
        if (self.anims_by_dir.getPtrConst(dir_enum).*) |*sprite_ref| {
            return sprite_ref.*;
        }
        // find the closest
        var best_diff: f32 = std.math.inf(f32);
        var best_dir: Dir = .E;
        var best_ref: ?*const Data.Ref(SpriteAnim) = null;
        for (dirs_list) |a_dir| {
            if (self.anims_by_dir.getPtrConst(a_dir).*) |*sprite_ref| {
                const a_dir_i = utl.as(f32, @intFromEnum(a_dir));
                const abs_diff = @abs(a_dir_i - d_i);
                const other_diff = max_dirs_f - abs_diff;
                const diff = @min(abs_diff, other_diff);
                if (diff < best_diff) {
                    best_diff = diff;
                    best_dir = a_dir;
                    best_ref = sprite_ref;
                    if (diff < 1) break;
                }
            }
        }
        return best_ref.?.*;
    }
};

pub const SpriteAnim = struct {
    // additional misc points offset from origin
    pub const PointName = enum {
        cast,
        npc,
    };
    data_ref: Data.Ref(SpriteAnim) = .{}, // spritesheet name dash tag name e.g. "wizard-move-W" or "door-open"

    sheet: Data.Ref(Data.SpriteSheet) = undefined,
    tag_idx: usize = 0,
    // idxs into spritesheet.frames[]
    first_frame_idx: usize = 0,
    last_frame_idx: usize = 0,
    // last - first + 1
    num_frames: usize = 0,
    // core.fups_per_sec == ticks
    dur_ticks: i64 = 0,
    // meta from spritesheet
    origin: draw.TextureOrigin = .topleft,
    events: std.BoundedArray(AnimEvent, 4) = .{},
    points: std.EnumArray(PointName, ?V2f) = std.EnumArray(PointName, ?V2f).initFill(null),

    pub fn getRenderFrame(self: *const SpriteAnim, anim_frame_idx: usize) RenderFrame {
        const sheet = @constCast(self).sheet.get();
        const frame = sheet.frames[@min(self.first_frame_idx + anim_frame_idx, self.last_frame_idx)];
        return .{
            .pos = frame.pos,
            .size = frame.size,
            .texture = sheet.texture,
            .origin = self.origin,
        };
    }

    pub fn getFrameEvents(self: *const SpriteAnim, anim_frame_idx: usize) AnimEvent.Set {
        var ret = std.EnumSet(AnimEvent.Kind).initEmpty();
        for (self.events.constSlice()) |e| {
            if (utl.as(usize, e.frame) == anim_frame_idx) {
                ret.insert(e.kind);
            }
        }
        return ret;
    }

    pub fn tickToFrameIdx(self: *const SpriteAnim, curr_tick: i64) usize {
        const sheet = @constCast(self).sheet.get();
        const bounded_tick = @mod(curr_tick, self.dur_ticks);
        var ticks_sum: i64 = 0;
        for (sheet.frames[self.first_frame_idx..(self.last_frame_idx + 1)], 0..) |frame, i| {
            const frame_ticks = utl.as(i32, core.ms_to_ticks(frame.duration_ms));
            const ticks_left = bounded_tick - ticks_sum;
            if (ticks_left < frame_ticks) {
                return i;
            }
            ticks_sum += frame_ticks;
        }
        unreachable;
    }

    pub inline fn getRenderFrameFromTick(self: *const SpriteAnim, curr_tick: i64) RenderFrame {
        return self.getRenderFrame(self.tickToFrameIdx(curr_tick));
    }
};

pub const DirectionalSpriteAnimator = struct {
    anim: Data.Ref(DirectionalSpriteAnim),
    animator: SpriteAnimator,

    pub fn init(anim: Data.Ref(DirectionalSpriteAnim)) DirectionalSpriteAnimator {
        //const dir_anim: *const DirectionalSpriteAnim = anim.getConst(); // this doesnt work before data is initted
        const default_sprite_anim_name = utl.bufPrintLocal("{s}-E", .{anim.name.constSlice()}) catch "";
        return DirectionalSpriteAnimator{
            .anim = anim,
            .animator = .{
                //.anim = dir_anim.dirToSpriteAnim(V2f.right), // this doesnt work before data is initted
                .anim = Data.Ref(SpriteAnim).init(default_sprite_anim_name),
            },
        };
    }

    pub fn getCurrRenderFrame(self: *const DirectionalSpriteAnimator) RenderFrame {
        return self.animator.getCurrRenderFrame();
    }

    pub fn tickCurrAnim(self: *DirectionalSpriteAnimator, params: SpriteAnimator.PlayParams) AnimEvent.Set {
        const dir_anim = self.anim.get();
        self.animator.anim = dir_anim.dirToSpriteAnim(params.dir);
        return self.animator.tickCurrAnim(params);
    }

    pub fn playAnim(self: *DirectionalSpriteAnimator, anim: Data.Ref(DirectionalSpriteAnim), params: SpriteAnimator.PlayParams) AnimEvent.Set {
        var play_anim = anim;
        const maybe_anim: ?*DirectionalSpriteAnim = play_anim.tryGet();
        if (maybe_anim == null) {
            Log.warn("Can't get anim \"{s}\"", .{play_anim.name.constSlice()});
            return std.EnumSet(AnimEvent.Kind).initOne(.end);
        }
        const new_anim = maybe_anim.?;
        const curr_anim = self.anim.get();
        if (new_anim.data_ref.idx != curr_anim.data_ref.idx) {
            self.animator.resetAnim();
        }
        self.anim = new_anim.data_ref;
        self.animator.anim = new_anim.dirToSpriteAnim(params.dir);
        return self.animator.tickCurrAnim(params);
    }

    pub fn getTicksUntilEvent(self: *const DirectionalSpriteAnimator, event: AnimEvent.Kind) ?i64 {
        return self.animator.getTicksUntilEvent(event);
    }
};

pub const SpriteAnimator = struct {
    pub const PlayParams = struct {
        reset: bool = false, // always true if new anim played via playAnim
        loop: bool = false,
        dir: V2f = .{}, // ignored for non-directional anims
    };

    anim: Data.Ref(SpriteAnim),
    curr_anim_frame: usize = 0,
    tick_in_frame: i32 = 0,
    anim_tick: i32 = 0,

    pub fn init(anim: Data.Ref(SpriteAnim)) SpriteAnimator {
        return SpriteAnimator{
            .anim = anim,
        };
    }

    pub fn getCurrRenderFrame(self: *const SpriteAnimator) RenderFrame {
        return self.anim.getConst().getRenderFrameFromTick(self.anim_tick);
    }

    pub fn resetAnim(self: *SpriteAnimator) void {
        self.anim_tick = 0;
        self.tick_in_frame = 0;
        self.curr_anim_frame = 0;
    }

    pub fn tickCurrAnim(self: *SpriteAnimator, params: PlayParams) AnimEvent.Set {
        var ret = std.EnumSet(AnimEvent.Kind).initEmpty();

        if (params.reset) {
            self.resetAnim();
        }
        const maybe_anim: ?*SpriteAnim = self.anim.tryGetOrDefault();
        if (maybe_anim == null) {
            Log.warn("Can't get anim \"{s}\"", .{self.anim.name.constSlice()});
            ret.insert(.end);
            return ret;
        }
        const anim = maybe_anim.?;
        // This could happen e.g. when switching anims around without explicitly resetting (i.e. not using playAnim())
        // NOT RECOMMENDED since different frames can take different amounts of time so anim_tick may not be lined up
        // with curr_anim_frame at all if switching like this (they could be misaligned without overflowing too)
        if (self.curr_anim_frame >= anim.num_frames or self.anim_tick >= anim.dur_ticks) {
            self.resetAnim();
        }
        const frame: Data.SpriteSheet.Frame = anim.sheet.getConst().frames[anim.first_frame_idx + self.curr_anim_frame];
        const frame_ticks = utl.as(i32, core.ms_to_ticks(frame.duration_ms));

        if (self.tick_in_frame >= frame_ticks) {
            // end of anim: last tick of frame, and on last frame
            if (self.curr_anim_frame >= anim.num_frames - 1) {
                if (params.loop) {
                    self.resetAnim();
                }
                ret.insert(.end);
                return ret;
            }
            self.curr_anim_frame += 1;
            self.tick_in_frame = 0;
        }
        // first tick of a frame; add frame events
        if (self.tick_in_frame == 0) {
            ret = anim.getFrameEvents(self.curr_anim_frame);
        }

        self.anim_tick += 1;
        // make sure we dont loop before tick_in_frame goes over the end of the frame (see above)
        if (self.anim_tick >= anim.dur_ticks) {
            self.anim_tick = utl.as(i32, anim.dur_ticks - 1);
        }
        self.tick_in_frame += 1;
        return ret;
    }

    pub fn playAnim(self: *SpriteAnimator, anim: Data.Ref(SpriteAnim), params: SpriteAnimator.PlayParams) AnimEvent.Set {
        var play_anim = anim;
        const maybe_anim: ?*SpriteAnim = play_anim.tryGetOrDefault();
        if (maybe_anim == null) {
            Log.warn("Can't get anim \"{s}\"", .{play_anim.name.constSlice()});
            return std.EnumSet(AnimEvent.Kind).initOne(.end);
        }
        const new_anim = maybe_anim.?;
        const curr_anim = self.anim.get();
        var new_params = params;
        if (new_anim.data_ref.idx != curr_anim.data_ref.idx) {
            self.resetAnim();
            new_params.reset = false;
        }
        self.anim = new_anim.data_ref;

        return self.tickCurrAnim(new_params);
    }

    pub fn getTicksUntilEvent(self: *const SpriteAnimator, event: AnimEvent.Kind) ?i64 {
        const maybe_anim: ?*const SpriteAnim = self.anim.tryGetConstOrDefault();
        if (maybe_anim == null) {
            Log.warn("Can't get anim \"{s}\"", .{self.anim.name.constSlice()});
            return null;
        }
        const anim = maybe_anim.?;
        for (anim.events.constSlice()) |e| {
            if (e.kind == event) {
                const e_frame_idx = utl.as(usize, e.frame);
                if (e.frame <= self.curr_anim_frame) return null;
                const sprite_sheet = anim.sheet.getConst();
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
};
