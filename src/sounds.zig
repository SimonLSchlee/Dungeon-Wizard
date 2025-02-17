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
const debug = @import("debug.zig");

const Run = @This();
const config = @import("config");
const App = @import("App.zig");
const Log = App.Log;
const getPlat = App.getPlat;
const Room = @import("Room.zig");
const Spell = @import("Spell.zig");
const Thing = @import("Thing.zig");
const Data = @import("Data.zig");
const menuUI = @import("menuUI.zig");
const gameUI = @import("gameUI.zig");
const Shop = @import("Shop.zig");
const Item = @import("Item.zig");
const player = @import("player.zig");
const ImmUI = @import("ImmUI.zig");
const sprites = @import("sprites.zig");
const Tooltip = @import("Tooltip.zig");
const TileMap = @import("TileMap.zig");
const pool = @import("pool.zig");

pub const max_playing_sfx = 64;
pub const Id = pool.Id;
pub const Pool = pool.BoundedPool(PlayingSound, max_playing_sfx);

pub const PlayingSound = struct {
    pub const Kind = enum {
        sfx,
        music,
    };
    id: Id = undefined,
    alloc_state: pool.AllocState = undefined,

    kind: Kind = .sfx,
    ref: Data.Ref(Data.Sound),
    audio_stream: Platform.AudioStream,
    // set to false after one loop. reset to true if ya want it to keep looping!
    loop_once: bool = false,
    stopped: bool = false,
    volume: f32 = 1,

    pub fn update(self: *PlayingSound) void {
        const audio = &App.get().options.audio;
        const volume = switch (self.kind) {
            .sfx => audio.sfx_volume,
            .music => audio.music_volume,
        } * self.volume;
        self.audio_stream.setVolume(volume);
        if (self.audio_stream.updateSound(self.loop_once)) {
            if (!self.loop_once) {
                self.stopAndFree();
            } else {
                self.loop_once = false;
            }
        }
    }
    pub fn setVolume(self: *PlayingSound, volume: f32) void {
        self.volume = volume;
    }
    pub fn stopAndFree(self: *PlayingSound) void {
        self.audio_stream.stop();
        self.loop_once = false;
        self.stopped = true;
    }
};

pub const SFXPlayer = struct {
    pub const PlayParams = struct {
        loop: bool = false,
        kind: PlayingSound.Kind = .sfx,
        volume: f32 = 1,
    };
    sounds: pool.BoundedPool(PlayingSound, max_playing_sfx) = undefined,

    pub fn init() SFXPlayer {
        const plat = getPlat();
        var ret = SFXPlayer{};
        ret.sounds.init(0);
        for (&ret.sounds.items) |*ps| {
            ps.audio_stream = plat.createAudioStream();
        }
        return ret;
    }

    pub fn deinit(self: *SFXPlayer) void {
        const plat = getPlat();
        for (&self.sounds.items) |*ps| {
            plat.destroyAudioStream(ps.audio_stream);
        }
    }

    pub fn playSound(self: *SFXPlayer, sound_ref: *Data.Ref(Data.Sound), params: PlayParams) ?Id {
        const sound = sound_ref.tryGetOrDefault() orelse return null;
        const ps = self.sounds.alloc() orelse return null;
        ps.kind = params.kind;
        ps.ref = sound_ref.*;
        ps.loop_once = params.loop;
        ps.volume = params.volume;
        ps.stopped = false;
        ps.audio_stream.setSound(sound.sound);
        ps.update();
        ps.audio_stream.play();
        return ps.id;
    }

    pub fn getById(self: *SFXPlayer, id: Id) ?*PlayingSound {
        return self.sounds.get(id);
    }

    pub fn update(self: *SFXPlayer) void {
        for (&self.sounds.items) |*ps| {
            if (ps.alloc_state != .allocated) continue;
            ps.update();
            if (ps.stopped) {
                self.sounds.free(ps.id);
            }
        }
    }
};

const MusicRef = struct {
    var menu = Data.Ref(Data.Sound).init("menu-music");
};
pub const MusicKind = enum {
    menu,
};

pub const MusicPlayer = struct {
    playing: ?struct {
        id: Id,
        kind: MusicKind,
    } = null,

    pub fn init() MusicPlayer {
        return .{};
    }
    pub fn update(self: *MusicPlayer, sfx_player: *SFXPlayer) void {
        if (self.playing) |*p| {
            if (sfx_player.getById(p.id)) |playing| {
                playing.loop_once = true;
            }
        }
    }
    pub fn setMusic(self: *MusicPlayer, sfx_player: *SFXPlayer, kind: ?MusicKind) void {
        if (self.playing) |*p| {
            if (kind == null or p.kind != kind.?) {
                if (sfx_player.getById(p.id)) |playing| {
                    playing.stopAndFree();
                }
                self.playing = null;
            }
        }
        if (self.playing == null and kind != null) {
            const ref = switch (kind.?) {
                .menu => &MusicRef.menu,
            };
            self.playing = .{
                .id = sfx_player.playSound(ref, .{ .loop = true, .kind = .music }) orelse return,
                .kind = kind.?,
            };
        }
    }
};
