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
const ImmUI = @import("ImmUI.zig");

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
        slime,
        gobbomber,
    };

    pub const kind_strings: Data.EnumToBoundedStringArrayType(Kind) = Data.enumToBoundedStringArray(Kind);
    pub const anim_kind_strings: Data.EnumToBoundedStringArrayType(AnimName) = Data.enumToBoundedStringArray(AnimName);

    creature_kind: Kind,
    anim_kind: AnimName,
    num_frames: i32 = 1,
    // TODO
    events: std.BoundedArray(AnimEvent, 8) = .{},
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
    cast_offset: V2f = .{},

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
        trailblaze,
        herring,
        mana_pickup,
        swirlies,
    };
    pub const AnimNameIdxMapping = std.EnumArray(AnimName, ?usize);
    pub const IdxMapping = std.EnumArray(SheetName, AnimNameIdxMapping);

    sheet_name: SheetName,
    anim_name: AnimName,
    start_frame: i32 = 0,
    num_frames: i32 = 1,
    events: std.BoundedArray(AnimEvent, 8) = .{},
    origin: draw.TextureOrigin = .center,

    pub fn getRenderFrame(self: VFXAnim, anim_frame: i32) RenderFrame {
        const sprite_sheet: Data.SpriteSheet = App.get().data.getVFXSpriteSheet(self.sheet_name, self.anim_name).?;
        const frame_idx = utl.as(usize, self.start_frame + anim_frame);
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

pub const AnimName = enum {
    none,
    //creature
    idle,
    move,
    attack,
    charge,
    cast,
    hit,
    die,
    // spellcasting
    basic_loop,
    basic_cast,
    basic_fizzle,
    // trailblaze, herring, pickup, swirlies
    loop,
    end,
};

pub const AnimEnum = enum {
    creature,
    vfx,
};

pub const AnimKindUnion = union(AnimEnum) {
    creature: CreatureAnim.Kind,
    vfx: VFXAnim.SheetName,
};

pub const AnimUnion = union(AnimEnum) {
    creature: CreatureAnim,
    vfx: VFXAnim,
};

pub const Animator = struct {
    pub const PlayParams = struct {
        reset: bool = false, // always true if new anim played
        loop: bool = false,
    };

    kind: union(AnimEnum) {
        creature: struct {
            kind: CreatureAnim.Kind = .wizard,
        },
        vfx: struct {
            sheet_name: VFXAnim.SheetName = .spellcasting,
        },
    },
    curr_anim: AnimName = .none,
    curr_anim_frame: i32 = 0,
    tick_in_frame: i32 = 0,
    anim_tick: i32 = 0,

    pub fn getCurrAnim(self: *const Animator) ?AnimUnion {
        switch (self.kind) {
            .vfx => |vfx| if (App.get().data.getVFXAnim(vfx.sheet_name, self.curr_anim)) |anim| {
                return .{
                    .vfx = anim,
                };
            },
            .creature => |creature| if (App.get().data.getCreatureAnimOrDefault(creature.kind, self.curr_anim)) |anim| {
                return .{
                    .creature = anim,
                };
            },
        }
        debug.err("No anim found: anim: {any} kind: {any}", .{ self.curr_anim, self.kind });
        return null;
    }

    pub fn getCurrSpriteSheet(self: *const Animator) ?Data.SpriteSheet {
        switch (self.kind) {
            .vfx => |vfx| {
                return App.get().data.getVFXSpriteSheet(vfx.sheet_name, self.curr_anim);
            },
            .creature => |creature| {
                return App.get().data.getCreatureAnimSpriteSheetOrDefault(creature.kind, self.curr_anim);
            },
        }
        debug.err("No spritesheet found: anim: {any} kind: {any}", .{ self.curr_anim, self.kind });
        return null;
    }

    pub fn getTicksUntilEvent(self: *const Animator, event: AnimEvent.Kind) ?i64 {
        if (self.getCurrAnim()) |anim_union| {
            switch (anim_union) {
                inline else => |anim| {
                    for (anim.events.constSlice()) |e| {
                        if (e.kind == event) {
                            const e_frame_idx = utl.as(usize, e.frame);
                            if (e.frame <= self.curr_anim_frame) return null;
                            if (self.getCurrSpriteSheet()) |sprite_sheet| {
                                const curr_frame_idx = utl.as(usize, self.curr_anim_frame);
                                var num_ticks: i64 = core.ms_to_ticks(sprite_sheet.frames[curr_frame_idx].duration_ms) - self.tick_in_frame;
                                for (sprite_sheet.frames[curr_frame_idx + 1 .. e_frame_idx]) |frame| {
                                    num_ticks += core.ms_to_ticks(frame.duration_ms);
                                }
                                return num_ticks;
                            }
                        }
                    }
                },
            }
        }
        return null;
    }

    pub fn getCurrRenderFrameDir(self: *const Animator, dir: V2f) RenderFrame {
        return if (self.getCurrAnim()) |anim_union| switch (anim_union) {
            .vfx => |anim| anim.getRenderFrame(self.curr_anim_frame),
            .creature => |anim| anim.getRenderFrame(dir, self.curr_anim_frame),
        } else {
            @panic("huh");
        };
    }

    pub fn getCurrRenderFrame(self: *const Animator) RenderFrame {
        return self.getCurrRenderFrameDir(.{});
    }

    pub fn play(self: *Animator, anim_name: AnimName, params: PlayParams) AnimEvent.Set {
        var ret = std.EnumSet(AnimEvent.Kind).initEmpty();
        if (params.reset or self.curr_anim != anim_name) {
            self.anim_tick = 0;
            self.tick_in_frame = 0;
            self.curr_anim_frame = 0;
        }
        self.curr_anim = anim_name;
        if (self.getCurrAnim()) |anim_union| switch (anim_union) {
            inline else => |anim| {
                const sprite_sheet = if (self.getCurrSpriteSheet()) |s| s else {
                    std.debug.print("{s}: WARNING: tried to get non-existent spritesheet\n", .{@src().file});
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
            },
        } else {
            std.debug.print("{s}: WARNING: tried to play non-existent anim: {any} \n", .{ @src().file, self.kind });
            ret.insert(.end);
            return ret;
        }
    }
};
