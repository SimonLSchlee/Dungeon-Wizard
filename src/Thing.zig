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
const Log = App.Log;
const getPlat = App.getPlat;
const Room = @import("Room.zig");
const TileMap = @import("TileMap.zig");
const Data = @import("Data.zig");
const pool = @import("pool.zig");
const sprites = @import("sprites.zig");

const player = @import("player.zig");
const creatures = @import("creatures.zig");
const Spell = @import("Spell.zig");
const Item = @import("Item.zig");
pub const StatusEffect = @import("StatusEffect.zig");
pub const Collision = @import("Collision.zig");
const AI = @import("AI.zig");
const Action = @import("Action.zig");
const icon_text = @import("icon_text.zig");
const projectiles = @import("projectiles.zig");
const sounds = @import("sounds.zig");

pub const Kind = enum {
    creature,
    projectile,
    shield,
    spawner,
    vfx,
    pickup,
    reward_chest,
};

pub const CreatureKind = creatures.Kind;

pub const SizeCategory = enum {
    none,
    smol,
    medium,
    big,

    pub const coll_radii = std.EnumArray(SizeCategory, f32).init(.{
        .none = 0,
        .smol = @round(0.065 * TileMap.tile_sz_f),
        .medium = @round(0.14 * TileMap.tile_sz_f),
        .big = @round(0.172 * TileMap.tile_sz_f),
    });
    pub const draw_radii = std.EnumArray(SizeCategory, f32).init(.{
        .none = 0,
        .smol = @round(0.17 * TileMap.tile_sz_f),
        .medium = @round(0.24 * TileMap.tile_sz_f),
        .big = @round(0.38 * TileMap.tile_sz_f),
    });
    pub const hurtbox_radii = draw_radii;
    pub const select_radii = std.EnumArray(SizeCategory, f32).init(.{
        .none = 0,
        .smol = @round(0.275 * TileMap.tile_sz_f),
        .medium = @round(0.375 * TileMap.tile_sz_f),
        .big = @round(0.45 * TileMap.tile_sz_f),
    });
    pub const hp_bar_width = std.EnumArray(SizeCategory, f32).init(.{
        .none = 0,
        .smol = draw_radii.get(.smol) * 2.5,
        .medium = draw_radii.get(.medium) * 2.75,
        .big = draw_radii.get(.big) * 2.5,
    });
};

pub const Selectable = struct {
    // its a half capsule shape
    radius: f32 = 10,
    height: f32 = 25,

    pub fn pointIsIn(selectable: Selectable, point: V2f, thing: *const Thing) bool {
        const rect = geom.Rectf{
            .pos = thing.pos.sub(v2f(selectable.radius, selectable.height)),
            .dims = v2f(selectable.radius * 2, selectable.height),
        };
        //const top_circle_pos = thing.pos.sub(v2f(0, selectable.height));

        return point.dist(thing.pos) < selectable.radius or
            geom.pointIsInRectf(point, rect); //or
        //mouse_pos.dist(top_circle_pos) < selectable.radius)

    }
};

pub const Pool = pool.BoundedPool(Thing, Room.max_things_in_room);
// TODO wrap
pub const Id = pool.Id;

id: Id = undefined,
alloc_state: pool.AllocState = undefined,
spawn_state: enum {
    instance, // not in any pool
    spawning, // in pool. yet to be spawned
    spawned, // active in the world
    freeable, // in pool. yet to be freed
} = .instance,
//
kind: Kind = undefined,
creature_kind: ?CreatureKind = null,
pos: V2f = .{},
dir: V2f = V2f.right,
dirv: f32 = 0,
dir_accel_params: DirAccelParams = .{},
// motion and collision
accel_params: AccelParams = .{},
vel: V2f = .{},
size_category: SizeCategory = .none,
draw_radius: f32 = 0,
coll_radius: f32 = 0,
coll_mask: Collision.Mask = .{},
coll_layer: Collision.Mask = .{},
coll_mass: f32 = 0,
last_coll: ?Collision = null,
//
vision_range: f32 = 0,
dbg: struct {
    coords_searched: std.BoundedArray(V2i, 128) = .{},
    hitbox_active_timer: utl.TickCounter = utl.TickCounter.initStopped(60),
} = .{},
player_input: ?player.Input = null,
controller: union(enum) {
    default: DefaultController,
    player: player.Controller,
    ai_actor: AI.ActorController,
    spell: Spell.Controller,
    item: Item.Controller, // not pickup-able items, stuff/vfx that using an item may spawn or whatnot
    projectile: projectiles.Controller,
    spawner: SpawnerController,
    cast_vfx: CastVFXController,
    text_vfx: TextVFXController,
    mana_pickup: ManaPickupController,
    loop_vfx: LoopVFXController,
    chest: ChestController,
} = .default,
renderer: union(enum) {
    none: struct {},
    shape: ShapeRenderer,
    spawner: SpawnerRenderer,
    sprite: SpriteRenderer,
    lightning: LightningRenderer,
} = .none,
on_die: union(enum) {
    default: struct {},
    djinn_boss: struct {
        pub fn onDie(self: *Thing, room: *Room) Error!void {
            _ = try room.queueSpawnCreatureByKind(.djinn_smoke, self.pos);
        }
    },
} = .default,
path: std.BoundedArray(V2f, 32) = .{},
pathing_layer: TileMap.PathLayer = .normal,
hitbox: ?HitBox = null,
hurtbox: ?HurtBox = null,
hp: ?HP = null,
mana: ?struct {
    curr: i32,
    max: i32,
    regen: ?struct {
        timer: utl.TickCounter,
        max_threshold: i32,
    } = null,
} = null,
faction: Faction = .object,
selectable: ?Selectable = null,
statuses: StatusEffect.StatusArray = StatusEffect.status_array,
enemy_difficulty: f32 = 0,
find_path_timer: utl.TickCounter = utl.TickCounter.init(6),
shadow_radius_x: f32 = 0,
hit_airborne: ?struct {
    landing_pos: V2f,
    z_vel: f32 = 0,
    z_accel: f32 = 0,
} = null,
dashing: bool = false,
rmb_interactable: ?struct {
    kind: enum {
        reward_chest,
        shop,
    },
    interact_radius: f32 = 40,
    hovered: bool = false,
    selected: bool = false,
    in_range: bool = false,
} = null,
manas_given: i32 = 0,
is_summon: bool = false,
is_boss: bool = false,
sound_player: SoundPlayer = .{},

pub const Faction = enum {
    object,
    neutral,
    player,
    ally,
    enemy,
    bezerk,

    pub const Mask = std.EnumSet(Faction);
    // factions' natural enemies - who they will aggro on, and use to supply hitbox masks for (some, not all) projectiles
    pub const opposing_masks = std.EnumArray(Faction, Faction.Mask).init(.{
        .object = .{},
        .neutral = .{},
        .player = Faction.Mask.initMany(&.{ .enemy, .bezerk }),
        .ally = Faction.Mask.initMany(&.{ .enemy, .bezerk }),
        .enemy = Faction.Mask.initMany(&.{ .player, .ally, .bezerk }),
        .bezerk = Faction.Mask.initMany(&.{ .neutral, .player, .ally, .enemy, .bezerk }),
    });
};

pub const HP = struct {
    const AnimRefs = struct {
        var swirlies = Data.Ref(Data.SpriteAnim).init("swirlies-loop");
    };

    pub const Shield = struct {
        curr: f32,
        max: f32,
        timer: ?utl.TickCounter,
    };

    curr: f32 = 10,
    max: f32 = 10,
    total_damage_done: f32 = 0,
    shields: std.BoundedArray(Shield, 8) = .{},

    pub const faction_colors = std.EnumArray(Faction, Colorf).init(.{
        .object = Colorf.gray,
        .neutral = Colorf.gray,
        .player = Colorf.green,
        .ally = Colorf.rgb(0, 0.5, 1),
        .enemy = Colorf.red,
        .bezerk = Colorf.orange,
    });

    pub fn init(max: f32) HP {
        return .{
            .curr = max,
            .max = max,
        };
    }
    pub fn update(self: *HP) void {
        var i: usize = 0;
        while (i < self.shields.len) {
            const shield = &self.shields.buffer[i];
            if (shield.timer) |*timer| {
                if (timer.tick(false)) {
                    _ = self.shields.orderedRemove(i);
                    continue;
                }
            }
            i += 1;
        }
    }

    pub fn heal(hp: *HP, amount: f32, self: *Thing, room: *Room) void {
        const amount_healed = @min(amount, hp.max - hp.curr);
        hp.curr += amount_healed;
        _ = AnimRefs.swirlies.get();
        const proto = Thing.LoopVFXController.proto(
            AnimRefs.swirlies,
            0.8,
            1,
            true,
            .green,
            true,
        );
        _ = room.queueSpawnThing(&proto, self.pos) catch {};
        if (amount_healed > 0) {
            const str = utl.bufPrintLocal("{d:.0}", .{amount_healed}) catch "";
            if (str.len > 0) {
                TextVFXController.spawn(self, str, .green, 1, room) catch {};
            }
        }
    }

    pub fn addShield(self: *HP, amount: f32, ticks: ?i64) void {
        if (self.shields.len >= self.shields.buffer.len) {
            _ = self.shields.orderedRemove(0);
            Log.warn("Ran out of shields space!", .{});
        }
        self.shields.append(.{
            .curr = amount,
            .max = amount,
            .timer = if (ticks) |t| utl.TickCounter.init(t) else null,
        }) catch unreachable;
    }

    pub fn doDamage(self: *HP, kind: Damage.Kind, amount: f32, thing: *Thing, room: *Room) void {
        if (amount <= 0) return;
        var damage_left = amount;
        // damage hits the outermost shield, continuing inwards until it hits the actual current hp
        while (self.shields.len > 0 and damage_left > 0) {
            const last = &self.shields.buffer[self.shields.len - 1];
            // this shield blocked all the remaining damage
            if (damage_left < last.curr) {
                last.curr -= damage_left;
                return;
            }
            // too much damage - pop the shield and continue
            damage_left -= last.curr;
            _ = self.shields.pop();
        }
        if (damage_left <= 0) return;
        // shield are all popped
        const final_damage_amount = @min(self.curr, damage_left);

        const str = utl.bufPrintLocal("{d:.0}", .{@floor(final_damage_amount)}) catch "";
        if (str.len > 0) {
            TextVFXController.spawn(thing, str, .red, 1, room) catch {};
        }
        Thing.LoopVFXController.spawnExplodeHit(thing, kind, amount, room);

        assert(final_damage_amount > 0);
        self.curr -= final_damage_amount;
        self.total_damage_done += final_damage_amount;
    }
    pub const FmtOpts = packed struct(usize) {
        max_only: bool = false,
        _: utl.PaddingBits(usize, 1) = 0,
    };
    pub fn format(self: HP, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) Error!void {
        _ = fmt;
        var opts: FmtOpts = .{};
        if (options.precision) |p| {
            opts = @bitCast(p);
        }
        if (opts.max_only) {
            writer.print("{any}{any}{any}{d:.0}", .{ icon_text.Fmt{ .tint = .red }, icon_text.Icon.heart, icon_text.Fmt{ .tint = .white }, @ceil(self.max) }) catch return Error.EncodingFail;
        } else {
            writer.print("{any}{any}{any}{d:.0}/{d:.0}", .{ icon_text.Fmt{ .tint = .red }, icon_text.Icon.heart, icon_text.Fmt{ .tint = .white }, @ceil(self.curr), @ceil(self.max) }) catch return Error.EncodingFail;
        }
    }
};

pub const Damage = struct {
    pub const Kind = enum {
        physical,
        magic,
        fire,
        ice,
        lightning,
        acid,

        pub fn getHitAnim(self: Damage.Kind, amount: f32) Data.Ref(Data.SpriteAnim) {
            const AnimRef = Data.Ref(Data.SpriteAnim);
            const Refs = struct {
                var magic_smol = AnimRef.init("explode_hit-magic_smol");
                var magic_big = AnimRef.init("explode_hit-magic_big");
                var fire_smol = AnimRef.init("explode_hit-fire_smol");
                var physical_smol = AnimRef.init("explode_hit-physical_smol");
                var physical_big = AnimRef.init("explode_hit-physical_big");
            };
            const ref = switch (self) {
                //.water => .water,
                .magic => if (amount < 8) &Refs.magic_smol else &Refs.magic_big,
                .fire => &Refs.fire_smol,
                else => if (amount < 8) &Refs.physical_smol else &Refs.physical_big,
            };
            _ = ref.get();
            return ref.*;
        }
        pub fn getHitSound(self: Damage.Kind, amount: f32) Data.Ref(Data.Sound) {
            const SoundRef = Data.Ref(Data.Sound);
            const Refs = struct {
                var thwack = SoundRef.init("thwack");
                var bash = SoundRef.init("hit-bash");
                var crunch = SoundRef.init("hit-crunch");
                var woosh = SoundRef.init("hit-woosh");
            };
            const ref = switch (self) {
                //.water => .water,
                .physical => if (amount < 8) &Refs.bash else &Refs.thwack,
                else => &Refs.woosh,
            };
            _ = ref.get();
            return ref.*;
        }

        pub inline fn getIcon(self: Damage.Kind, aoe: bool) icon_text.Icon {
            return switch (self) {
                .magic => if (aoe) .aoe_magic else .magic,
                .fire => if (aoe) .aoe_fire else .fire,
                .ice => if (aoe) .aoe_ice else .icicle,
                .lightning => if (aoe) .aoe_lightning else .lightning,
                else => .blood_splat,
            };
        }
        pub inline fn getName(self: Damage.Kind) []const u8 {
            return switch (self) {
                .physical => "Physical",
                .magic => "Magic",
                .fire => "Fire",
                .ice => "Ice",
                .lightning => "Lightning",
                .acid => "Acid",
            };
        }

        pub fn fmtName(buf: []u8, kind: Damage.Kind, aoe: bool) Error![]u8 {
            var icon: icon_text.Icon = .blood_splat;
            var dmg_type_string: []const u8 = "";
            switch (kind) {
                .magic => {
                    icon = if (aoe) .aoe_magic else .magic;
                    dmg_type_string = "Magic ";
                },
                .fire => {
                    icon = if (aoe) .aoe_fire else .fire;
                    dmg_type_string = "Fire ";
                },
                .ice => {
                    icon = if (aoe) .aoe_ice else .icicle;
                    dmg_type_string = "Ice ";
                },
                .lightning => {
                    icon = if (aoe) .aoe_lightning else .lightning;
                    dmg_type_string = "Lightning ";
                },
                //.acid => {
                //    icon = .slime;
                //    dmg_type_string = "Acid ";
                //},
                else => {},
            }
            return try std.fmt.bufPrint(buf, "{any}{s}", .{ icon, dmg_type_string });
        }
        pub fn fmtDesc(buf: []u8, kind: Damage.Kind) Error![]u8 {
            return switch (kind) {
                .magic => try std.fmt.bufPrint(buf, "It's maaaagic", .{}),
                .fire => try std.fmt.bufPrint(buf, "Applies a stack of {any}lit", .{StatusEffect.proto_array.get(.lit).icon}),
                .ice => try std.fmt.bufPrint(buf, "Cold", .{}),
                .lightning => try std.fmt.bufPrint(buf, "Zappy. Applies {any}stun", .{StatusEffect.proto_array.get(.lit).icon}),
                else => try std.fmt.bufPrint(buf, "It hurts", .{}),
            };
        }
        pub const FmtOpts = packed struct(usize) {
            aoe: bool = false,
            name_string: bool = false,
            _: utl.PaddingBits(usize, 2) = 0,
        };
        pub fn format(self: Damage.Kind, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) Error!void {
            _ = fmt;
            var opts: Damage.Kind.FmtOpts = .{};
            if (options.precision) |p| {
                opts = @bitCast(p);
            }
            const icon = self.getIcon(opts.aoe);
            if (opts.name_string) {
                writer.print("{any}{s}", .{ icon, self.getName() }) catch return Error.EncodingFail;
            } else {
                writer.print("{any}", .{icon}) catch return Error.EncodingFail;
            }
        }
    };
    kind: Damage.Kind,
    amount: f32,
    pub const FmtOpts = packed struct(usize) {
        aoe: bool = false,
        _: utl.PaddingBits(usize, 1) = 0,
    };
    pub fn format(self: Damage, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) Error!void {
        _ = fmt;
        var opts: Damage.FmtOpts = .{};
        if (options.precision) |p| {
            opts = @bitCast(p);
        }
        writer.print("{any}{d:.0}", .{ self.kind.getIcon(opts.aoe), @floor(self.amount) }) catch return Error.EncodingFail;
    }
};

pub const HitEffect = struct {
    damage_kind: Damage.Kind = .physical,
    damage: f32 = 1,
    status_stacks: StatusEffect.StacksArray = StatusEffect.StacksArray.initDefault(0, .{}),
    force: union(enum) {
        none,
        from_center: f32, // magnitude
        fixed: V2f,
    } = .none,
    can_be_blocked: bool = true,
};

pub const HitBox = struct {
    rel_pos: V2f = .{},
    sweep_to_rel_pos: ?V2f = null,
    radius: f32 = 0,
    mask: Faction.Mask = Faction.Mask.initEmpty(),
    path_mask: TileMap.PathLayer.Mask = TileMap.PathLayer.Mask.initFull(),
    active: bool = false,
    deactivate_on_update: bool = true,
    deactivate_on_hit: bool = true,
    effect: HitEffect,
    indicator: ?struct {
        state: enum {
            fade_in,
            fade_out,
        } = .fade_in,
        timer: utl.TickCounter,
    } = null,

    pub fn update(_: *HitBox, self: *Thing, room: *Room) void {
        const hitbox = &self.hitbox.?;

        if (hitbox.indicator) |*indicator| {
            switch (indicator.state) {
                .fade_in => if (indicator.timer.tick(false)) {
                    indicator.state = .fade_out;
                    indicator.timer = utl.TickCounter.init(core.secsToTicks(0.15));
                },
                .fade_out => if (indicator.timer.tick(false)) {
                    hitbox.indicator = null;
                },
            }
        }
        if (!hitbox.active) {
            _ = self.dbg.hitbox_active_timer.tick(false);
            return;
        }
        // for debug vis
        self.dbg.hitbox_active_timer.restart();

        const start_pos = self.pos.add(hitbox.rel_pos);
        const maybe_ray_v: ?V2f = if (hitbox.sweep_to_rel_pos) |e| e.sub(hitbox.rel_pos) else null;
        for (&room.things.items) |*thing| {
            if (!thing.isActive()) continue;
            if (thing.hurtbox == null) continue;
            var hurtbox = &thing.hurtbox.?;
            if (!hitbox.mask.contains(thing.faction)) continue;
            if (!hitbox.path_mask.contains(thing.pathing_layer)) continue;
            const hurtbox_pos = thing.pos.add(hurtbox.rel_pos);

            const effective_radius = hitbox.radius + hurtbox.radius;

            const did_hit = blk: {
                if (maybe_ray_v) |ray_v| {
                    if (Collision.getRayCircleCollision(start_pos, ray_v, hurtbox_pos, effective_radius)) |_| {
                        break :blk true;
                    }
                } else {
                    const dist = start_pos.dist(hurtbox_pos);
                    break :blk dist <= effective_radius;
                }
                break :blk false;
            };
            if (did_hit) {
                hurtbox.hit(thing, room, hitbox.effect, self);
                if (hitbox.deactivate_on_hit) {
                    hitbox.active = false;
                    break;
                }
            }
        }

        if (hitbox.deactivate_on_update) {
            hitbox.active = false;
        }
    }
};

pub const HurtBox = struct {
    rel_pos: V2f = .{},
    radius: f32 = 0,

    pub fn hit(_: *HurtBox, self: *Thing, room: *Room, effect: HitEffect, maybe_hitter: ?*Thing) void {
        // TODO put in StatusEffect/PricklyPotion?
        const prickly_stacks = self.statuses.get(.prickly).stacks;
        if (prickly_stacks > 0) {
            if (maybe_hitter) |hitter| {
                if (!hitter.id.eql(self.id)) { // don't prickle yourself!
                    if (hitter.hurtbox) |*hitter_hurtbox| {
                        const prickle_effect = HitEffect{
                            .damage = utl.as(f32, prickly_stacks),
                            .can_be_blocked = false,
                        };
                        hitter_hurtbox.hit(hitter, room, prickle_effect, null);
                    }
                }
            }
        }
        // TODO put in StatusEffect/Protec?
        if (effect.can_be_blocked) {
            const protect_stacks = &self.statuses.getPtr(.protected).stacks;
            if (protect_stacks.* > 0) {
                protect_stacks.* -= 1;
                return;
            }
        }
        { // compute and apply the damage
            var damage = effect.damage;
            if (self.statuses.get(.exposed).stacks > 0) {
                damage *= 1.3;
            }
            if (self.hp) |*hp| {
                const pre_damage_done = hp.total_damage_done;
                hp.doDamage(effect.damage_kind, damage, self, room);
                const post_damage_done = hp.total_damage_done;
                if ((room.init_params.mode == .crispin_picker or room.init_params.mode == .harriet_hoarder) and self.isEnemy() and !self.is_summon) {
                    const total_manas = @max(@ceil(self.enemy_difficulty * 2.5), 1);
                    const manas_left = total_manas - utl.as(f32, self.manas_given);
                    if (manas_left > 0) {
                        const damage_per_mana = hp.max / total_manas;
                        const post_manas = @floor(post_damage_done / damage_per_mana);
                        const pre_manas = @floor(pre_damage_done / damage_per_mana);
                        const num_manas = utl.as(usize, @min(post_manas - pre_manas, manas_left));
                        ManaPickupController.spawnSome(num_manas, self.pos, room);
                        self.manas_given += utl.as(i32, num_manas);
                    }
                }
            }
        }
        force_blk: {
            const force = switch (effect.force) {
                .none => break :force_blk,
                .from_center => |mag| center_blk: {
                    if (maybe_hitter) |hitter| {
                        if (hitter.hitbox) |hitbox| {
                            const dir = self.pos.sub(hitter.pos.add(hitbox.rel_pos)).normalizedChecked() orelse break :force_blk;
                            break :center_blk dir.scale(mag);
                        }
                    }
                    break :force_blk;
                },
                .fixed => |dir| dir,
            };
            const mag = force.length();
            self.updateVel(
                force.normalizedOrZero(),
                .{
                    .accel = mag,
                    .max_speed = self.accel_params.max_speed + mag,
                },
            );
        }
        // then apply statuses
        for (&self.statuses.values) |*status| {
            const stacks = effect.status_stacks.get(status.kind);
            if (stacks > 0) {
                status.addStacks(self, stacks);
            }
        }
        // then kill
        if (self.hp) |hp| {
            if (hp.curr == 0) {
                // TODO put in StatusEffect/Mint?
                // TODO maybe dont access Run here, more testable/reproduceableeeu?
                // e.g. have something like Room.rewards and add it there, and Run will grab it later
                const run = &App.get().run;
                const mint_status = self.statuses.get(.mint);
                if (mint_status.stacks > 0) {
                    run.gold += mint_status.stacks;
                }
                // stop getting hit by stuff
                self.hurtbox = null;
                if (self.player_input == null) {
                    self.shadow_radius_x = 0;
                }
                // and hitting stuff
                // and etc
                self.hitbox = null;
                self.coll_mask = @TypeOf(self.coll_mask).initEmpty();
                self.coll_layer = @TypeOf(self.coll_mask).initEmpty();
                self.selectable = null;
            }
        }
    }
};

pub const LoopVFXController = struct {
    anim_to_loop: Data.Ref(Data.SpriteAnim) = undefined,
    tint: Colorf = .white,
    timer: utl.TickCounter = utl.TickCounter.init(core.secsToTicks(2)),
    fade_secs: f32 = 1,
    loop: bool = true,
    state: enum {
        loop,
        fade,
    } = .loop,

    pub fn update(self: *Thing, room: *Room) Error!void {
        assert(self.spawn_state == .spawned);
        const controller = &self.controller.loop_vfx;

        const events = self.renderer.sprite.playNormal(controller.anim_to_loop, .{ .loop = controller.loop });

        switch (controller.state) {
            .loop => {
                if (controller.timer.tick(false) or (!controller.loop and events.contains(.end))) {
                    controller.timer = utl.TickCounter.init(core.secsToTicks(controller.fade_secs));
                    controller.state = .fade;
                }
            },
            .fade => {
                self.renderer.sprite.sprite_tint = controller.tint.fade(1 - controller.timer.remapTo0_1());
                if (controller.timer.tick(false)) {
                    self.deferFree(room);
                }
            },
        }
    }
    pub fn proto(anim: Data.Ref(Data.SpriteAnim), lifetime_secs: f32, fade_secs: f32, loop: bool, tint: Colorf, draw_over: bool) Thing {
        var ret = Thing{
            .kind = .vfx,
            .controller = .{ .loop_vfx = .{
                .anim_to_loop = anim,
                .timer = utl.TickCounter.init(core.secsToTicks(@max(lifetime_secs, 0))),
                .tint = tint,
                .fade_secs = @max(fade_secs, 0),
                .loop = loop,
            } },
            .renderer = .{ .sprite = .{
                .draw_normal = !draw_over,
                .draw_over = draw_over,
                .sprite_tint = tint,
            } },
        };
        ret.renderer.sprite.setNormalAnim(anim);
        return ret;
    }
    pub fn spawnExplodeHit(thing: *Thing, kind: Damage.Kind, amount: f32, room: *Room) void {
        const rfloat = room.rng.random().float(f32);
        const rdir = V2f.fromAngleRadians(rfloat * utl.tau);
        const center_pos = if (thing.selectable) |s| thing.pos.add(v2f(0, -s.height * 0.5)) else thing.pos;
        const radius = (if (thing.selectable) |s| s.radius else thing.coll_radius) * 0.75;
        const rpos = center_pos.add(rdir.scale(radius));
        const anim = kind.getHitAnim(amount);
        var sound = kind.getHitSound(amount);

        _ = App.get().sfx_player.playSound(&sound, .{});

        const p = proto(anim, 99, 0, false, .white, true);
        _ = room.queueSpawnThing(&p, rpos) catch {};
    }
};

pub const TextVFXController = struct {
    movement: enum {
        float_up,
        fall_down,
    } = .float_up,
    roffset: f32 = 0,
    timer: utl.TickCounter = utl.TickCounter.init(core.secsToTicks(1)),
    color: Colorf,
    initial_pos: V2f,

    pub fn update(self: *Thing, room: *Room) Error!void {
        assert(self.spawn_state == .spawned);
        const controller = &self.controller.text_vfx;

        if (controller.timer.tick(false)) {
            self.deferFree(room);
        } else switch (controller.movement) {
            .float_up => {
                const f = controller.timer.remapTo0_1();
                self.pos.y -= 1;
                self.pos.x = controller.initial_pos.x + ((@sin((f + controller.roffset) * utl.pi * 2) * 2) - 1) * 1.5;
                // fade doesn't look good with the borders...
                //self.renderer.shape.kind.text.opt.color = controller.color.fade(f);
                //self.renderer.shape.kind.text.opt.border.?.color = Colorf.black.fade(f);
            },
            .fall_down => {
                self.vel.y += 1;
                self.pos = self.pos.add(self.vel);
            },
        }
    }

    pub fn spawn(self: *Thing, str: []const u8, color: Colorf, scale: f32, room: *Room) Error!void {
        const rfloat = room.rng.random().float(f32);
        const rdir = V2f.fromAngleRadians(rfloat * utl.tau);
        const center_pos = if (self.selectable) |s| self.pos.add(v2f(0, -s.height * 0.5)) else self.pos;
        const radius = (if (self.selectable) |s| s.radius else self.coll_radius) * 0.75;
        const rpos = center_pos.add(rdir.scale(radius));

        var proto = Thing{
            .kind = .vfx,
            .controller = .{
                .text_vfx = .{
                    .initial_pos = rpos,
                    .roffset = rfloat,
                    .color = color,
                },
            },
            .renderer = .{
                .shape = .{
                    .draw_over = true,
                    .draw_normal = false,
                    .kind = .{
                        .text = .{
                            // arrggh lol
                            .text = ShapeRenderer.TextLabel.fromSlice(str[0..@min(str.len, (ShapeRenderer.TextLabel{}).buffer.len)]) catch unreachable,
                        },
                    },
                    .poly_opt = .{},
                },
            },
        };
        proto.renderer.shape.kind.text.opt.color = color;
        proto.renderer.shape.kind.text.opt.size *= utl.as(u32, scale);
        proto.renderer.shape.kind.text.opt.border.?.dist *= (scale);

        _ = try room.queueSpawnThing(&proto, rpos);
    }
};

pub const SoundPlayer = struct {
    pub const PlayParams = struct {
        loop: bool = false,
        volume: f32 = 1.0,
    };

    playing_sound: ?sounds.Id = null,

    pub fn play(sp: *SoundPlayer, sound_ref: *Data.Ref(Data.Sound), params: PlayParams) void {
        const sfx_player = &App.get().sfx_player;
        const sound_asset: *Data.Sound = sound_ref.tryGetOrDefault() orelse {
            Log.warn("Failed to get sound \"{s}\"", .{sound_ref.name.constSlice()});
            return;
        };
        if (sp.playing_sound) |id| {
            if (sfx_player.getById(id)) |ps| {
                if (sound_asset.data_ref.idx.? != ps.ref.idx.?) {
                    sp.playing_sound = sfx_player.playSound(&sound_asset.data_ref, .{ .loop = params.loop, .volume = params.volume });
                    return;
                }
                // it's already playing, just loop if needed
                ps.loop_once = params.loop;
                ps.setVolume(params.volume);
            }
        } else {
            sp.playing_sound = sfx_player.playSound(&sound_asset.data_ref, .{ .loop = params.loop, .volume = params.volume });
        }
    }

    pub fn stop(sp: *SoundPlayer) void {
        const sfx_player = &App.get().sfx_player;
        if (sp.playing_sound) |id| {
            if (sfx_player.getById(id)) |ps| {
                ps.stopAndFree();
            }
        }
        sp.playing_sound = null;
    }
};

pub const CastVFXController = struct {
    const AnimRefs = struct {
        var loop = Data.Ref(Data.SpriteAnim).init("spellcasting-basic_loop");
        var cast = Data.Ref(Data.SpriteAnim).init("spellcasting-basic_cast");
        var fizzle = Data.Ref(Data.SpriteAnim).init("spellcasting-basic_fizzle");
    };
    const SoundRefs = struct {
        var loop = Data.Ref(Data.Sound).init("casting");
        var cast = Data.Ref(Data.Sound).init("cast-end");
        var fizzle = Data.Ref(Data.Sound).init("crackle");
    };
    parent: Thing.Id,
    cast_end_sound: Data.Ref(Data.Sound),
    sound_fade_timer: utl.TickCounter = utl.TickCounter.init(30),
    state: enum {
        loop,
        fizzle,
        cast,
    } = .loop,

    pub fn cast(controller: *CastVFXController) void {
        controller.state = .cast;
        const sfx_player = &App.get().sfx_player;
        _ = sfx_player.playSound(&controller.cast_end_sound, .{ .volume = 0.6 });
    }

    pub fn fizzle(controller: *CastVFXController) void {
        controller.state = .fizzle;
        const sfx_player = &App.get().sfx_player;
        _ = sfx_player.playSound(&SoundRefs.fizzle, .{});
    }

    pub fn update(self: *Thing, room: *Room) Error!void {
        assert(self.spawn_state == .spawned);
        const controller = &self.controller.cast_vfx;

        switch (controller.state) {
            .loop => {
                _ = self.renderer.sprite.playNormal(AnimRefs.loop, .{ .loop = true });
                if (room.getThingById(controller.parent)) |parent| {
                    if (parent.isDeadCreature()) {
                        controller.fizzle();
                    }
                } else {
                    controller.fizzle();
                }
            },
            .fizzle => {
                _ = controller.sound_fade_timer.tick(false);
                if (self.renderer.sprite.playNormal(AnimRefs.fizzle, .{}).contains(.end)) {
                    self.deferFree(room);
                    self.sound_player.stop();
                    return;
                }
            },
            .cast => {
                _ = controller.sound_fade_timer.tick(false);
                if (self.renderer.sprite.playNormal(AnimRefs.cast, .{}).contains(.end)) {
                    self.deferFree(room);
                    self.sound_player.stop();
                    return;
                }
            },
        }
        const f = 1 - controller.sound_fade_timer.remapTo0_1();
        self.sound_player.play(&SoundRefs.loop, .{ .loop = true, .volume = 0.3 * f });
    }

    pub fn castingProto(caster: *Thing, spell: *Spell) Thing {
        var cast_offset = V2f{};
        if (App.getData().getCreatureDirAnim(caster.creature_kind.?, .cast)) |dir_anim| {
            const anim = dir_anim.dirToSpriteAnim(caster.dir).getConst();
            if (anim.points.get(.cast)) |pt| {
                cast_offset = pt;
                if (caster.dir.x < 0) {
                    cast_offset.x *= -1;
                }
            }
        }
        const cast_end_sound = spell.cast_sound.get().data_ref;
        const cast_pos = caster.pos.add(cast_offset);
        var ret = Thing{
            .kind = .vfx,
            .pos = cast_pos,
            .controller = .{
                .cast_vfx = .{
                    .parent = caster.id,
                    .cast_end_sound = cast_end_sound,
                },
            },
            .renderer = .{
                .sprite = .{
                    .draw_over = true,
                    .draw_normal = false,
                    .sprite_tint = spell.color,
                },
            },
        };
        _ = AnimRefs.loop.get();
        _ = AnimRefs.fizzle.get();
        _ = AnimRefs.cast.get();
        ret.renderer.sprite.setNormalAnim(AnimRefs.loop);
        return ret;
    }
};

pub const SpriteRenderer = struct {
    sprite_tint: Colorf = .white,
    draw_normal: bool = true,
    draw_over: bool = false,
    draw_under: bool = false,
    rotate_to_dir: bool = false,
    flip_x_to_dir: bool = false,
    rel_pos: V2f = .{},
    scale: f32 = core.game_sprite_scaling,
    animator: union(enum) {
        normal: sprites.SpriteAnimator,
        dir: sprites.DirectionalSpriteAnimator,
    } = .{ .normal = sprites.SpriteAnimator.init(Data.Ref(sprites.SpriteAnim).init("default")) },

    pub fn setNormalAnim(renderer: *SpriteRenderer, anim: Data.Ref(sprites.SpriteAnim)) void {
        switch (renderer.animator) {
            .normal => |*a| {
                a.anim = anim;
            },
            .dir => {
                renderer.animator = .{ .normal = sprites.SpriteAnimator.init(anim) };
            },
        }
    }

    pub fn setDirAnim(renderer: *SpriteRenderer, anim: Data.Ref(sprites.DirectionalSpriteAnim)) void {
        switch (renderer.animator) {
            .normal => {
                renderer.animator = .{ .dir = sprites.DirectionalSpriteAnimator.init(anim) };
            },
            .dir => |*da| {
                da.anim = anim;
            },
        }
    }

    pub fn playDir(renderer: *SpriteRenderer, anim: Data.Ref(sprites.DirectionalSpriteAnim), params: sprites.SpriteAnimator.PlayParams) sprites.AnimEvent.Set {
        if (std.meta.activeTag(renderer.animator) == .normal) {
            var params_adjusted = params;
            params_adjusted.reset = true;
            renderer.setDirAnim(anim);
        }
        return renderer.animator.dir.playAnim(anim, params);
    }

    pub fn playNormal(renderer: *SpriteRenderer, anim: Data.Ref(sprites.SpriteAnim), params: sprites.SpriteAnimator.PlayParams) sprites.AnimEvent.Set {
        if (std.meta.activeTag(renderer.animator) == .dir) {
            var params_adjusted = params;
            params_adjusted.reset = true;
            renderer.setNormalAnim(anim);
        }
        return renderer.animator.normal.playAnim(anim, params);
    }

    pub fn tickCurrAnim(renderer: *SpriteRenderer, params: sprites.SpriteAnimator.PlayParams) sprites.AnimEvent.Set {
        return switch (renderer.animator) {
            inline else => |*a| a.tickCurrAnim(params),
        };
    }

    pub fn getTicksUntilEvent(renderer: *const SpriteRenderer, event: sprites.AnimEvent.Kind) ?i64 {
        return switch (renderer.animator) {
            inline else => |*a| a.getTicksUntilEvent(event),
        };
    }

    pub fn playCreatureAnim(renderer: *SpriteRenderer, thing: *Thing, action_anim: Data.ActionAnimName, params: sprites.SpriteAnimator.PlayParams) sprites.AnimEvent.Set {
        assert(thing.creature_kind != null);
        const data = App.getData();
        if (data.getCreatureDirAnim(thing.creature_kind.?, action_anim) orelse data.getDefault(Data.DirectionalSpriteAnim)) |dir_anim| {
            var p = params;
            p.dir = thing.dir;
            return renderer.playDir(dir_anim.data_ref, p);
        } else {
            Log.warn("Failed to get any anim for creature {any} : {any} !", .{ thing.creature_kind.?, action_anim });
            return sprites.AnimEvent.Set.initOne(.end);
        }
    }

    pub fn _render(self: *const Thing, renderer: *const SpriteRenderer, _: *const Room) void {
        const plat = App.getPlat();
        const rf = switch (renderer.animator) {
            inline else => |a| a.getCurrRenderFrame(),
        };
        var opt = rf.toTextureOpt(renderer.scale);
        const status_tint = self.getStatusTint();
        const tint: Colorf = if (!renderer.sprite_tint.eql(.white)) renderer.sprite_tint else status_tint;

        opt.tint = tint;
        // TODO we'r defining flipped in a few places arggh, this only works because we use them in different cases
        opt.flip_x = (renderer.flip_x_to_dir and self.dir.x < 0) or opt.flip_x;
        opt.rot_rads = if (renderer.rotate_to_dir) self.dir.toAngleRadians() else 0;

        if (opt.flip_x and renderer.rotate_to_dir and self.dir.x < 0) {
            opt.rot_rads += utl.pi;
        }
        plat.texturef(self.pos.add(renderer.rel_pos), rf.texture, opt);
    }

    pub fn renderUnder(self: *const Thing, room: *const Room) Error!void {
        const renderer = &self.renderer.sprite;
        if (renderer.draw_under) {
            _render(self, renderer, room);
        }
    }

    pub fn render(self: *const Thing, room: *const Room) Error!void {
        const renderer = &self.renderer.sprite;
        if (renderer.draw_normal) {
            _render(self, renderer, room);
        }
    }

    pub fn renderOver(self: *const Thing, room: *const Room) Error!void {
        const renderer = &self.renderer.sprite;
        if (renderer.draw_over) {
            _render(self, renderer, room);
        }
    }
};

pub const SpawnerRenderer = struct {
    sprite_tint: Colorf = .blank,
    base_circle_color: Colorf = .blank,

    pub fn renderUnder(self: *const Thing, _: *const Room) Error!void {
        const renderer = &self.renderer.spawner;
        const plat = App.getPlat();
        plat.circlef(
            self.pos,
            self.draw_radius,
            .{
                .fill_color = renderer.base_circle_color,
                .smoothing = .none,
            },
        );
    }

    pub fn render(self: *const Thing, _: *const Room) Error!void {
        const controller = &self.controller.spawner;
        const renderer = &self.renderer.spawner;
        const plat = App.getPlat();
        const anim = App.get().data.getCreatureDirAnim(controller.creature_kind, .idle).?;
        const frame = anim.dirToSpriteAnim(self.dir).getConst().getRenderFrame(0);
        var opt = frame.toTextureOpt(core.game_sprite_scaling);
        opt.tint = renderer.sprite_tint;
        plat.texturef(self.pos, frame.texture, opt);
    }
};

pub const ChestController = struct {
    const Ref = struct {
        var spawn = Data.Ref(Data.SpriteAnim).init("reward-chest-spawn");
        var normal = Data.Ref(Data.SpriteAnim).init("reward-chest-normal");
    };
    const select_radius: f32 = 16;
    const radius: f32 = 8;

    state: enum {
        spawning,
        spawned,
    } = .spawning,

    pub fn update(self: *Thing, room: *Room) Error!void {
        _ = room;
        const controller = &self.controller.chest;
        switch (controller.state) {
            .spawning => {
                if (self.renderer.sprite.tickCurrAnim(.{ .loop = false }).contains(.end)) {
                    controller.state = .spawned;
                    self.rmb_interactable = .{
                        .kind = .reward_chest,
                        .interact_radius = radius + 15,
                    };
                    self.renderer.sprite.setNormalAnim(Ref.normal);
                }
            },
            .spawned => {
                //
            },
        }
    }

    pub fn proto() Thing {
        _ = Ref.spawn.get();
        _ = Ref.normal.get();
        var chest = Thing{
            .kind = .reward_chest,
            .coll_radius = radius,
            .coll_mask = Collision.Mask.initMany(&.{
                .wall,
                .creature,
                .spikes,
            }),
            .coll_layer = Collision.Mask.initOne(.creature),
            .coll_mass = std.math.inf(f32),
            .controller = .{
                .chest = .{},
            },
            .renderer = .{
                .sprite = .{},
            },
            .selectable = .{ .radius = 16, .height = 20 },
        };
        chest.renderer.sprite.setNormalAnim(Ref.spawn);
        return chest;
    }
};

pub const ManaPickupController = struct {
    const AnimRef = struct {
        var loop = Data.Ref(Data.SpriteAnim).init("mana_pickup-loop");
        var end = Data.Ref(Data.SpriteAnim).init("mana_pickup-end");
    };
    state: enum {
        loop,
        collected,
    } = .loop,
    fading: bool = false,
    timer: utl.TickCounter = utl.TickCounter.init(core.secsToTicks(12)),

    pub fn update(self: *Thing, room: *Room) Error!void {
        const controller = &self.controller.mana_pickup;
        const renderer = &self.renderer.sprite;
        if (controller.timer.tick(false)) {
            if (controller.fading) {
                self.deferFree(room);
                return;
            } else {
                controller.fading = true;
                controller.timer = utl.TickCounter.init(core.secsToTicks(2));
            }
        }
        if (controller.fading) {
            renderer.sprite_tint = Colorf.white.fade(1 - controller.timer.remapTo0_1());
        }
        switch (controller.state) {
            .loop => if (room.getPlayer()) |p| {
                _ = renderer.playNormal(AnimRef.loop, .{ .loop = true });
                if (p.mana) |*mana| {
                    if (mana.curr < mana.max) {
                        if (p.selectable) |s| {
                            const pickup_radius = @max(s.radius - 5, 5);
                            if (Collision.getCircleCircleCollision(self.pos, self.coll_radius, p.pos, pickup_radius)) |_| {
                                mana.curr += 1;
                                controller.state = .collected;
                            }
                        }
                    }
                }
            },
            .collected => {
                renderer.sprite_tint = Colorf.white; // it could be fading, brighten it back to full
                renderer.draw_normal = false;
                renderer.draw_over = true;
                if (renderer.playNormal(AnimRef.end, .{}).contains(.end)) {
                    self.deferFree(room);
                }
            },
        }
        if (self.last_coll) |c| {
            const d = self.vel.sub(c.normal.scale(self.vel.dot(c.normal) * 2));
            self.vel = d;
        }
        self.updateVel(.{}, .{ .friction = 0.005 });
    }
    pub fn spawnSome(num: usize, pos: V2f, room: *Room) void {
        const radius = 14;
        var proto = Thing{
            .kind = .pickup,
            .coll_radius = radius,
            .coll_mask = Collision.Mask.initMany(&.{ .wall, .spikes }),
            .controller = .{ .mana_pickup = .{} },
            .renderer = .{ .sprite = .{} },
            .shadow_radius_x = 6,
        };
        _ = AnimRef.end.get();
        _ = AnimRef.loop.get();
        proto.renderer.sprite.setNormalAnim(AnimRef.loop);
        var rnd = room.rng.random();
        for (0..num) |_| {
            const rdir = V2f.fromAngleRadians(rnd.float(f32) * utl.tau);
            const rdist = 5 + rnd.float(f32) * 15;
            proto.vel = rdir.scale(0.25 + rnd.float(f32) * 0.5);
            _ = room.queueSpawnThing(&proto, pos.add(rdir.scale(rdist))) catch {};
        }
    }
};

pub const SpawnerController = struct {
    const SoundRef = struct {
        var loop = Data.Ref(Data.Sound).init("spawning-loop");
        var activate = Data.Ref(Data.Sound).init("activate");
    };

    timer: utl.TickCounter = utl.TickCounter.init(1 * core.fups_per_sec / 2),
    sound_fade_timer: utl.TickCounter = utl.TickCounter.init(1 * core.fups_per_sec),
    state: enum {
        fade_in_circle,
        fade_in_creature,
        fade_out_circle,
    } = .fade_in_circle,
    creature_kind: CreatureKind,

    pub fn update(self: *Thing, room: *Room) Error!void {
        const spawner = &self.controller.spawner;
        switch (spawner.state) {
            .fade_in_circle => {
                self.renderer.spawner.base_circle_color = Colorf.white.fade(spawner.timer.remapTo0_1());
                if (spawner.timer.tick(true)) {
                    spawner.timer = utl.TickCounter.init(1 * core.fups_per_sec);
                    spawner.state = .fade_in_creature;
                }
            },
            .fade_in_creature => {
                self.renderer.spawner.sprite_tint = Colorf.black.fade(0).lerp(Colorf.white, spawner.timer.remapTo0_1());
                if (spawner.timer.tick(true)) {
                    var proto = App.get().data.creature_protos.get(spawner.creature_kind);
                    proto.faction = self.faction;
                    proto.is_summon = self.is_summon;
                    _ = try room.queueSpawnThing(&proto, self.pos);
                    spawner.state = .fade_out_circle;
                    _ = App.get().sfx_player.playSound(&SoundRef.activate, .{ .volume = 0.5 });
                }
            },
            .fade_out_circle => {
                self.renderer.spawner.sprite_tint = .blank;
                self.renderer.spawner.base_circle_color = Colorf.white.fade(1 - spawner.timer.remapTo0_1());
                _ = spawner.sound_fade_timer.tick(false);
                if (spawner.timer.tick(false)) {
                    self.deferFree(room);
                    self.sound_player.stop();
                    return;
                }
            },
        }
        const f = 1 - spawner.sound_fade_timer.remapTo0_1();
        self.sound_player.play(&SoundRef.loop, .{ .loop = true, .volume = 0.3 * f });
    }

    pub fn prototype(creature_kind: CreatureKind) Thing {
        const proto: Thing = App.get().data.creature_protos.get(creature_kind);
        return .{
            .kind = .spawner,
            .dir = proto.dir,
            .draw_radius = proto.draw_radius,
            .controller = .{
                .spawner = .{
                    .creature_kind = creature_kind,
                },
            },
            .renderer = .{
                .spawner = .{},
            },
            .faction = proto.faction, // to ensure num_enemies_alive > 0
        };
    }
    pub fn prototypeSummon(creature_kind: CreatureKind) Thing {
        var ret = prototype(creature_kind);
        ret.is_summon = true;
        return ret;
    }
};

pub const LightningRenderer = struct {
    pub const PointArray = std.BoundedArray(V2f, 32);
    points: PointArray = .{},
    points_start: usize = 0,
    draw_under: bool = false,
    draw_normal: bool = true,
    draw_over: bool = false,
    color: Colorf = .white,

    fn _render(_: *const Thing, renderer: *const LightningRenderer, room: *const Room) void {
        const plat = App.getPlat();
        const opt = draw.LineOpt{
            .color = renderer.color,
            .thickness = @max(0.66 * room.camera.zoom, 1),
        };
        if (renderer.points.len < 2) return;
        const points_start = renderer.points_start % renderer.points.len;
        for (0..(renderer.points.len - 1)) |i| {
            const idx = (points_start + i) % renderer.points.len;
            const idx_next = (idx + 1) % renderer.points.len;
            const p0, const p1 = .{ renderer.points.buffer[idx], renderer.points.buffer[idx_next] };
            plat.linef(p0, p1, opt);
        }
    }

    pub fn render(self: *const Thing, room: *const Room) Error!void {
        const renderer = &self.renderer.lightning;
        if (renderer.draw_normal) {
            _render(self, renderer, room);
        }
    }
};

pub const ShapeRenderer = struct {
    pub const PointArray = std.BoundedArray(V2f, 32);
    pub const TextLabel = utl.BoundedString(24);

    kind: union(enum) {
        circle: struct {
            radius: f32,
        },
        sector: struct {
            start_ang_rads: f32,
            end_ang_rads: f32,
            radius: f32,
        },
        arrow: struct {
            thickness: f32,
            length: f32,
        },
        poly: PointArray,
        text: struct {
            text: TextLabel,
            font: Data.FontName = .pixeloid,
            opt: draw.TextOpt = .{
                .center = true,
                .color = .white,
                .size = 11,
                .border = .{
                    .dist = 1,
                },
                .smoothing = .none,
            },
        },
    },
    poly_opt: draw.PolyOpt,
    draw_under: bool = false,
    draw_normal: bool = true,
    draw_over: bool = false,
    rel_pos: V2f = .{},

    fn _render(self: *const Thing, renderer: *const ShapeRenderer, _: *const Room) void {
        const plat = App.getPlat();
        const pos = self.pos.add(renderer.rel_pos);
        switch (renderer.kind) {
            .circle => |s| {
                plat.circlef(pos, s.radius, renderer.poly_opt);
            },
            .sector => |s| {
                plat.sectorf(pos, s.radius, s.start_ang_rads, s.end_ang_rads, renderer.poly_opt);
            },
            .arrow => |s| {
                const color: Colorf = if (renderer.poly_opt.fill_color) |c| c else .white;
                plat.arrowf(pos, pos.add(self.dir.scale(s.length)), .{ .thickness = s.thickness, .color = color });
            },
            .text => |s| {
                const data = App.get().data;
                const font = data.fonts.get(s.font);
                var opt = s.opt;
                opt.font = font;
                plat.textf(pos, "{s}", .{s.text.constSlice()}, opt) catch {};
            },
            else => @panic("unimplemented"),
        }
    }
    pub fn renderUnder(self: *const Thing, room: *const Room) Error!void {
        const renderer = &self.renderer.shape;
        if (renderer.draw_under) {
            _render(self, renderer, room);
        }
    }
    pub fn render(self: *const Thing, room: *const Room) Error!void {
        const renderer = &self.renderer.shape;
        if (renderer.draw_normal) {
            _render(self, renderer, room);
        }
    }
    pub fn renderOver(self: *const Thing, room: *const Room) Error!void {
        const renderer = &self.renderer.shape;
        if (renderer.draw_over) {
            _render(self, renderer, room);
        }
    }
};

pub fn renderShadow(self: *const Thing) void {
    const plat = getPlat();
    if (self.shadow_radius_x > 0) {
        plat.ellipsef(self.pos, v2f(self.shadow_radius_x, self.shadow_radius_x * 0.5), .{
            .fill_color = Colorf.black.fade(0.5),
            .smoothing = .none,
            .round_to_pixel = true,
        });
    }
}

pub fn renderBarWithLines(pos: V2f, dims: V2f, line_inc_amount: f32, bar_amount: f32, color: Colorf) void {
    const plat = getPlat();
    plat.rectf(pos, dims, .{ .fill_color = color });

    var i: f32 = line_inc_amount;
    var err: f32 = 0;
    while (i < bar_amount) {
        const raw_x = dims.x * (i / bar_amount);
        const line_x = @floor(raw_x + err);
        err += raw_x - line_x;
        const top = pos.add(v2f(line_x, 0));
        plat.rectf(top, v2f(1, dims.y), .{
            .fill_color = Colorf.black.fade(0.5),
        });
        i += line_inc_amount;
    }
}

pub fn getStatusTint(self: *const Thing) Colorf {
    var tint: Colorf = blk: {
        if (self.isAliveCreature()) {
            if (self.statuses.get(.frozen).stacks > 0) break :blk StatusEffect.proto_array.get(.frozen).color;
            if (self.statuses.get(.exposed).stacks > 0) break :blk StatusEffect.proto_array.get(.exposed).color.lerp(.white, 0.25);
        }
        break :blk .white;
    };
    if (self.isAliveCreature() and self.statuses.get(.unseeable).stacks > 0) tint.a = 0.5;
    return tint;
}

pub fn renderStatusBars(self: *const Thing, _: *const Room) Error!void {
    const plat = getPlat();
    var status_width: f32 = 20;
    var status_y_offset: f32 = 30;
    if (self.selectable) |s| {
        status_width = @round(s.radius * 2);
        status_y_offset = @round(s.height + 10);
    }
    const status_tl_offset = v2f(-status_width * 0.5, -status_y_offset);
    const status_topleft = self.pos.add(status_tl_offset); //.round();

    const hp_height = 3;
    const hp_topleft = status_topleft;
    const shields_height = 3;
    const shields_topleft = hp_topleft.add(v2f(0, hp_height));

    if (self.isAliveCreature()) {
        if (self.hp) |hp| {
            const curr_width = @round(utl.remapClampf(0, hp.max, 0, status_width, hp.curr));
            plat.rectf(
                hp_topleft,
                v2f(status_width, hp_height),
                .{
                    .fill_color = Colorf.black,
                    //.round_to_pixel = true,
                },
            );
            const line_inc: f32 = if (hp.max < 100) 10 else 50;
            renderBarWithLines(
                hp_topleft,
                v2f(curr_width, hp_height),
                line_inc,
                hp.curr,
                HP.faction_colors.get(self.faction),
            );
            var total_shield_amount: f32 = 0;
            var curr_shield_amount: f32 = 0;
            for (hp.shields.constSlice()) |shield| {
                total_shield_amount += shield.max;
                curr_shield_amount += shield.curr;
            }
            const shields_width = status_width * curr_shield_amount / total_shield_amount;
            if (total_shield_amount > 0) {
                const shield_color = Colorf.rgb(0.7, 0.7, 0.4);
                const line_shield_inc: f32 = if (total_shield_amount < 100) 10 else 50;
                renderBarWithLines(
                    shields_topleft,
                    v2f(shields_width, hp_height),
                    line_shield_inc,
                    curr_shield_amount,
                    shield_color,
                );
            }
            if (self.mana) |mana| {
                // regen bar
                if (mana.regen) |*mrgn| {
                    const f = mrgn.timer.remapTo0_1();
                    const mana_color = draw.Coloru.rgb(161, 133, 238).toColorf();
                    const bar_dims = v2f(status_width * f, 2).round();
                    const bar_topleft = hp_topleft.sub(v2f(0, bar_dims.y));
                    plat.rectf(bar_topleft, bar_dims, .{
                        .fill_color = mana_color,
                    });
                }
                // crystals
                blk: {
                    const data = App.getData();
                    const full_rf = data.text_icons.getRenderFrame(.mana_crystal_smol) orelse break :blk;
                    const empty_rf = data.text_icons.getRenderFrame(.mana_empty) orelse break :blk;
                    const flame_rf = data.text_icons.getRenderFrame(.mana_flame) orelse break :blk;
                    const cropped_dims = data.text_icons.sprite_dims_cropped.?.get(.mana_crystal_smol);
                    const mana_topleft = hp_topleft.sub(v2f(0, cropped_dims.y + 2)); //.round();
                    var curr_pos = mana_topleft;
                    for (0..utl.as(usize, mana.max)) |i_sz| {
                        const i = utl.as(i32, i_sz);
                        const is_full = i < mana.curr;
                        const is_crystal = if (mana.regen) |regen| i < regen.max_threshold else true;
                        const rf = if (is_crystal)
                            (if (is_full) full_rf else empty_rf)
                        else if (is_full)
                            flame_rf
                        else
                            break;
                        var opt = rf.toTextureOpt(1);
                        opt.smoothing = .none;
                        opt.origin = .topleft;
                        opt.src_dims = cropped_dims;
                        opt.round_to_pixel = true;
                        plat.texturef(curr_pos, rf.texture, opt);
                        curr_pos.x += cropped_dims.x - 1;
                    }
                }
            }
        }
        // debug draw statuses
        const font = App.get().data.fonts.get(.seven_x_five);
        const status_height: f32 = utl.as(f32, font.base_size);
        var status_pos = shields_topleft.add(v2f(0, shields_height));
        for (self.statuses.values) |status| {
            if (status.stacks == 0) continue;
            const text = try utl.bufPrintLocal("{}", .{status.stacks});
            const text_dims = try plat.measureText(text, .{ .size = font.base_size });
            const status_box_width = text_dims.x + 2;
            const text_color = Colorf.getContrasting(status.getColor());
            plat.rectf(status_pos, v2f(status_box_width, status_height), .{
                .fill_color = status.getColor(),
            });

            try plat.textf(status_pos.add(V2f.splat(1)), "{s}", .{text}, .{
                .size = font.base_size,
                .color = text_color,
                .font = font,
                .smoothing = .none,
            });
            status_pos.x += status_box_width;
        }
    }
}

pub const DefaultController = struct {
    pub fn update(self: *Thing, _: *Room) Error!void {
        assert(self.spawn_state == .spawned);
        self.updateVel(.{}, self.accel_params);
    }
};

fn updateController(self: *Thing, room: *Room) Error!void {
    switch (self.controller) {
        inline else => |c| {
            const C = @TypeOf(c);
            if (std.meta.hasMethod(C, "update")) {
                try C.update(self, room);
            }
        },
    }
}

pub inline fn canAct(self: *const Thing) bool {
    if (self.creature_kind != null) {
        return self.isAliveCreature() and self.statuses.get(.frozen).stacks == 0 and self.statuses.get(.stunned).stacks == 0 and self.hit_airborne == null;
    }
    return self.isActive();
}

pub fn update(self: *Thing, room: *Room) Error!void {
    _ = self.find_path_timer.tick(false);
    const is_prompt = self.statuses.get(.promptitude).stacks > 0;
    if (self.canAct()) {
        const old_max_speed = self.accel_params.max_speed;
        if (is_prompt) {
            self.accel_params.max_speed = old_max_speed * 2;
        }
        try updateController(self, room);
        if (is_prompt) {
            try updateController(self, room);
            self.accel_params.max_speed = old_max_speed;
        }
    } else if (self.isDeadCreature()) {
        if (self.renderer.sprite.playCreatureAnim(self, .die, .{}).contains(.end)) {
            switch (self.on_die) {
                inline else => |s| {
                    const S = @TypeOf(s);
                    if (@hasDecl(S, "onDie")) {
                        try S.onDie(self, room);
                    }
                },
            }
            self.deferFree(room);
        }
        return;
    } else if (self.hit_airborne) |*s| {
        s.z_vel += s.z_accel;
        var done = false;
        switch (self.renderer) {
            inline else => |*r| if (@hasField(@TypeOf(r.*), "rel_pos")) {
                r.rel_pos.y += -s.z_vel;
                if (r.rel_pos.y >= 0) {
                    done = true;
                    r.rel_pos.y = 0;
                }
            },
        }
        done = done or self.pos.dist(s.landing_pos) < self.vel.length() * 1.5;
        if (done) {
            self.hit_airborne = null;
        }
    } else {
        self.updateVel(.{}, .{});
    }
    self.moveAndCollide(room);
    if (self.hurtbox) |*hurtbox| {
        if (self.pathing_layer == .normal and self.hit_airborne == null and self.dashing == false) {
            const tile_coord = TileMap.posToTileCoord(self.pos);
            if (room.tilemap.gameTileCoordToConstGameTile(tile_coord)) |tile| {
                if (tile.coll_layers.contains(.spikes)) {
                    hurtbox.hit(self, room, .{ .damage = 8 }, null);
                    const flight_ticks = core.secsToTicks(0.5);
                    const max_y: f32 = 40;
                    const v0: f32 = 2 * max_y / utl.as(f32, flight_ticks);
                    const g = -2 * v0 / utl.as(f32, flight_ticks);
                    const landing_pos = try room.tilemap.getClosestPathablePos(self.pathing_layer, null, self.pos, self.coll_radius) orelse self.pos;
                    self.hit_airborne = .{
                        .landing_pos = landing_pos,
                        .z_accel = g,
                        .z_vel = v0,
                    };
                    const speed = landing_pos.dist(self.pos) / utl.as(f32, flight_ticks);
                    self.vel = landing_pos.sub(self.pos).normalizedOrZero().scale(speed);
                }
            }
        }
    }
    if (self.hitbox) |*hitbox| {
        hitbox.update(self, room);
    }
    for (&self.statuses.values) |*status| {
        try status.update(self, room);
    }
    if (self.hp) |*hp| {
        hp.update();
    }
    if (self.rmb_interactable) |*inter| {
        if (self.selectable) |sel| {
            if (room.getPlayer()) |p| {
                const plat = getPlat();
                const mouse_on_ui = room.parent_run_this_frame.ui_hovered;

                inter.hovered = false;
                if (sel.pointIsIn(room.mouse_pos_world, self)) {
                    inter.hovered = true;
                }
                inter.in_range = false;
                if (p.pos.dist(self.pos) <= inter.interact_radius) {
                    inter.in_range = true;
                }
                if (!mouse_on_ui and plat.input_buffer.mouseBtnIsDown(.right)) {
                    inter.selected = inter.hovered;
                }

                if (inter.selected) {
                    if (inter.in_range) {
                        p.path.clear();
                        room.thingInteract(self);
                        inter.selected = false;
                    } else if (p.path.len > 0) {
                        const last_path_pos = &p.path.buffer[p.path.len - 1];
                        last_path_pos.* = self.pos;
                    } else {
                        inter.selected = false;
                    }
                } else if (inter.in_range and !mouse_on_ui and plat.input_buffer.mouseBtnIsJustPressed(.left)) {
                    room.thingInteract(self);
                }
            }
        }
    }
}

pub fn renderUnder(self: *const Thing, room: *const Room) Error!void {
    switch (self.renderer) {
        inline else => |r| {
            const R = @TypeOf(r);
            if (std.meta.hasMethod(R, "renderUnder")) {
                try R.renderUnder(self, room);
            }
        },
    }
    const plat = getPlat();
    self.renderShadow();
    if (room.paused) {
        if (self.isAliveCreature() and self.draw_radius > 0) {
            plat.circlef(self.pos, self.draw_radius, .{
                .fill_color = null,
                .smoothing = .none,
                .round_to_pixel = true,
                .outline = .{ .color = .yellow },
            });
            const arrow_start = self.pos.add(self.dir.scale(self.draw_radius));
            const arrow_end = self.pos.add(self.dir.scale(self.draw_radius + 2.5));
            plat.arrowf(arrow_start, arrow_end, .{ .thickness = 2.5, .color = .yellow });
        }
    }

    if (debug.show_selectable) {
        if (self.selectable) |s| {
            if (@constCast(room).getMousedOverThing(Faction.Mask.initFull())) |thing| {
                if (thing.id.eql(self.id)) {
                    const opt = draw.PolyOpt{ .fill_color = Colorf.cyan };
                    plat.circlef(self.pos, s.radius, opt);
                    plat.rectf(self.pos.sub(v2f(s.radius, s.height)), v2f(s.radius * 2, s.height), opt);
                }
            }
        }
    }
    if (self.selectable) |_| {
        if (self.rmb_interactable) |inter| {
            if ((inter.hovered or inter.selected) and inter.in_range) {
                const opt = draw.PolyOpt{
                    .fill_color = null,
                    .outline = .{
                        .color = Colorf.green.fade(0.5),
                    },
                };
                plat.circlef(self.pos, inter.interact_radius, opt);
            }
        }
    }
}

pub fn render(self: *const Thing, room: *const Room) Error!void {
    switch (self.renderer) {
        inline else => |r| {
            const R = @TypeOf(r);
            if (std.meta.hasMethod(R, "render")) {
                try R.render(self, room);
            }
        },
    }
    const plat = App.getPlat();
    // protected bubble
    const protected = self.statuses.get(.protected);
    if (self.isAliveCreature() and protected.stacks > 0) {
        // TODO dont use select radius
        const h = if (self.selectable) |s| s.height else self.coll_radius * 2.5;
        const shield_center = self.pos.sub(v2f(0, h * 0.5));
        const popt = draw.PolyOpt{
            .fill_color = null,
            .outline = .{ .color = StatusEffect.proto_array.get(.protected).color },
        };
        const r = h * 0.68 + 2;
        plat.circlef(shield_center, r, popt);
        const ticks_in_loop: i32 = 30;
        const ticks_in_loop_2: i32 = ticks_in_loop / 2;
        const tick_inc = @max(@divTrunc(ticks_in_loop, protected.stacks), 1);
        const angle_inc = @max(utl.pi / utl.as(f32, protected.stacks), utl.tau / 18);
        for (0..utl.as(usize, protected.stacks)) |i| {
            var eopt = popt;
            eopt.rot_rads = utl.as(f32, i) * angle_inc;
            const tick = room.curr_tick + utl.as(i64, i * tick_inc);
            const mod_tick = @mod(tick, ticks_in_loop) - ticks_in_loop_2;
            const f = utl.as(f32, mod_tick) / ticks_in_loop_2;
            const r2 = r * f;
            plat.ellipsef(shield_center, v2f(r2, r), eopt);
            plat.circlef(shield_center, r, popt);
        }
    }
}

pub fn renderOver(self: *const Thing, room: *const Room) Error!void {
    switch (self.renderer) {
        inline else => |r| {
            const R = @TypeOf(r);
            if (std.meta.hasMethod(R, "renderOver")) {
                try R.renderOver(self, room);
            }
        },
    }

    const plat = App.getPlat();
    if (debug.show_thing_collisions) {
        plat.circlef(self.pos, self.coll_radius, .{ .outline = .{ .color = .red }, .fill_color = null });
        if (self.last_coll) |coll| {
            plat.arrowf(coll.pos, coll.pos.add(coll.normal.scale(self.coll_radius * 0.75)), .{ .thickness = 2, .color = Colorf.red });
        }
    }
    if (debug.show_thing_coords_searched) {
        if (self.path.len > 0) {
            for (self.dbg.coords_searched.constSlice()) |coord| {
                plat.circlef(TileMap.tileCoordToCenterPos(coord), 10, .{ .outline = .{ .color = Colorf.white }, .fill_color = null });
            }
        }
    }
    if (debug.show_ai_decision) {
        if (std.meta.activeTag(self.controller) == .ai_actor) {
            const controller = self.controller.ai_actor;
            const str = switch (controller.decision) {
                .idle => "idle",
                .pursue_to_attack => |p| blk: {
                    if (room.getConstThingById(p.target_id)) |target| {
                        plat.arrowf(self.pos, target.pos, .{ .color = .red, .thickness = 1 });
                    }
                    break :blk "pursue";
                },
                .flee => "flee",
                .action => |doing| blk: {
                    break :blk utl.bufPrintLocal("action: {s}", .{utl.enumToString(Action.Slot, doing.slot)}) catch "";
                },
            };
            try plat.textf(self.pos, "{s}", .{str}, .{ .center = true, .color = .white, .size = 14 });
        }
    }
    if (debug.show_hiding_places) {
        if (std.meta.activeTag(self.controller) == .ai_actor) {
            const controller = self.controller.ai_actor;
            if (std.meta.activeTag(controller.decision) == .flee) {
                for (controller.hiding_places.constSlice()) |h| {
                    const self_to_pos = h.pos.sub(self.pos).normalizedOrZero();
                    const len = @max(controller.to_enemy.length() - controller.flee_range, 0);
                    const to_enemy_n = controller.to_enemy.setLengthOrZero(len);
                    const dir_f = self_to_pos.dot(to_enemy_n.neg());
                    const f = h.flee_from_dist + dir_f; // - h.fleer_dist;
                    try plat.textf(h.pos, "{d:.2}", .{f}, .{ .center = true, .color = .white, .size = 14 });
                    //plat.circlef(h.pos, 10, .{ .outline = .{ .color = Colorf.white }, .fill_color = null });
                }
            }
        }
    }
    if (debug.show_thing_paths) {
        if (self.path.len > 0) {
            try self.debugDrawPath(room);
        }
    }
    if (debug.show_hitboxes) {
        if (self.hitbox) |hitbox| {
            if (self.dbg.hitbox_active_timer.running) {
                const f = self.dbg.hitbox_active_timer.remapTo0_1();
                const color = Colorf.red.fade(1 - f);
                const pos: V2f = self.pos.add(hitbox.rel_pos);
                plat.circlef(pos, hitbox.radius, .{ .fill_color = color });
                if (hitbox.sweep_to_rel_pos) |rel_end| {
                    const end_pos = self.pos.add(rel_end);
                    plat.linef(pos, end_pos, .{ .thickness = hitbox.radius * 2, .color = color });
                    plat.circlef(end_pos, hitbox.radius, .{ .fill_color = color });
                }
            }
        }
        if (self.hurtbox) |hurtbox| {
            const color = Colorf.yellow.fade(0.5);
            plat.circlef(self.pos.add(hurtbox.rel_pos), hurtbox.radius, .{ .fill_color = color });
        }
    }
    // hitbox indicator
    if (self.hitbox) |hitbox| {
        if (hitbox.indicator) |indicator| {
            const timer_f = indicator.timer.remapTo0_1();
            const f = if (indicator.state == .fade_in) timer_f else 1 - timer_f;
            const color = Colorf.red.fade(f);
            const circle_opt = draw.PolyOpt{
                .fill_color = null,
                .outline = .{
                    .color = color,
                    .smoothing = .bilinear,
                },
            };
            const pos: V2f = self.pos.add(hitbox.rel_pos);

            plat.circlef(pos, hitbox.radius, circle_opt);
            if (hitbox.sweep_to_rel_pos) |rel_end| {
                const end_pos = self.pos.add(rel_end);
                const len = end_pos.dist(pos);
                const divisions = @ceil(len / (hitbox.radius * 1.2));
                const dist = len / divisions;
                const num = utl.as(usize, divisions) + 1;
                const v = rel_end.normalizedChecked() orelse V2f.right;
                for (1..num) |i| {
                    const p = pos.add(v.scale(dist * utl.as(f32, i)));
                    plat.circlef(p, hitbox.radius, circle_opt);
                }
            }
        }
    }
    try self.renderStatusBars(room);
    if (self.selectable) |s| {
        if (self.rmb_interactable) |inter| {
            if (inter.hovered or inter.selected) {
                const bottom_pt = self.pos.add(v2f(0, -s.height - 10));
                const points = [_]V2f{
                    bottom_pt,
                    bottom_pt.add(v2f(5, -10)),
                    bottom_pt.add(v2f(-5, -10)),
                };
                var opt = draw.PolyOpt{
                    .fill_color = .green,
                };
                if (!inter.selected) {
                    opt.fill_color = null;
                    opt.outline = .{ .color = .green, .thickness = 2 };
                }
                plat.trianglef(points, opt);
            }
        }
    }
}

pub fn deferFree(self: *Thing, room: *Room) void {
    assert(self.spawn_state == .spawned);
    self.spawn_state = .freeable;
    room.free_queue.append(self.id) catch @panic("out of free_queue space!");
}

// copy retaining original id, alloc state and spawn_state
pub fn copyTo(self: *const Thing, other: *Thing) Error!void {
    const id = other.id;
    const alloc_state = other.alloc_state;
    const spawn_state = other.spawn_state;
    other.* = self.*;
    other.id = id;
    other.alloc_state = alloc_state;
    other.spawn_state = spawn_state;
}

pub fn isActive(self: *const Thing) bool {
    return self.alloc_state == .allocated and self.spawn_state == .spawned;
}

pub fn moveAndCollide(self: *Thing, room: *Room) void {
    var num_iters: i32 = 0;

    self.last_coll = null;
    self.pos = self.pos.add(self.vel);

    while (num_iters < 5) {
        var _coll: ?Collision = null;

        if (self.coll_mask.contains(.creature)) {
            _coll = Collision.getNextCircleCollisionWithThings(self.pos, self.coll_radius, self.coll_mask, &.{self.id}, room);
        }
        if (_coll == null) {
            _coll = Collision.getCircleCollisionWithTiles(self.coll_mask, self.pos, self.coll_radius, &room.tilemap);
        }

        if (_coll) |coll| {
            self.last_coll = coll;
            // push out
            var push_self_out = false;
            switch (coll.kind) {
                .thing => |id| {
                    if (room.getThingById(id)) |thing| {
                        if (thing.coll_mass < std.math.inf(f32)) {
                            thing.updateVel(coll.normal.neg(), .{ .accel = self.vel.length() * 0.5, .max_speed = self.accel_params.max_speed * 0.5 });
                        }
                    }
                    push_self_out = self.coll_mass < std.math.inf(f32);
                },
                .tile => {
                    push_self_out = true;
                },
                .none => {},
            }
            if (push_self_out) {
                if (coll.pen_dist > 0) {
                    self.pos = coll.pos.add(coll.normal.scale(self.coll_radius + 0.1));
                }
            }
            // remove -normal component from vel, isn't necessary with current implementation
            //const d = coll_normal.dot(self.vel);
            //self.vel = self.vel.sub(coll_normal.scale(d + 0.1));
        }

        num_iters += 1;
    }
}

pub fn followPathGetNextPoint(self: *Thing, dist: f32) V2f {
    var ret: V2f = self.pos;

    if (self.path.len > 0) {
        assert(self.path.len >= 2);
        const curr_coord = TileMap.posToTileCoord(self.pos);
        const next_pos = self.path.buffer[1];
        const next_coord = TileMap.posToTileCoord(next_pos);
        const curr_to_next = next_pos.sub(self.pos);
        var remove_next = false;

        ret = next_pos;

        // for last square, only care about radius. for others, enter the square
        if ((self.path.len == 2 and curr_to_next.length() <= dist) or (self.path.len > 2 and curr_coord.eql(next_coord))) {
            remove_next = true;
        }

        if (remove_next) {
            _ = self.path.orderedRemove(0);
            if (self.path.len == 1) {
                _ = self.path.orderedRemove(0);
                ret = self.pos;
            }
        }
    }

    return ret;
}

pub fn findPath(self: *Thing, room: *Room, goal: V2f) Error!void {
    if (self.player_input == null and self.find_path_timer.running) {
        return;
    }
    self.path = try room.tilemap.findPathThetaStar(
        getPlat().heap,
        self.pathing_layer,
        self.pos,
        goal,
        self.coll_radius,
        &self.dbg.coords_searched,
    );
    self.find_path_timer.restart();
    if (self.path.len == 0) {
        self.path.append(self.pos) catch unreachable;
        self.path.append(goal) catch unreachable;
    }
}

pub const DirAccelParams = struct {
    ang_accel: f32 = utl.pi * 0.002,
    max_ang_vel: f32 = utl.pi * 0.03,
};

pub fn updateDir(self: *Thing, desired_dir: V2f, params: DirAccelParams) void {
    const n = desired_dir.normalizedOrZero();
    if (!n.isZero()) {
        const a_dir: f32 = if (self.dir.cross(n) > 0) 1 else -1;
        const cos = self.dir.dot(n);
        const ang = std.math.acos(cos);

        self.dirv += a_dir * params.ang_accel;
        const abs_dirv = @abs(self.dirv);
        if (@abs(ang) <= abs_dirv * 2) {
            self.dir = n;
            self.dirv = 0;
        } else {
            if (abs_dirv > params.max_ang_vel) self.dirv = a_dir * params.max_ang_vel;
            self.dir = self.dir.rotRadians(self.dirv);
        }
    }
}

pub const AccelParams = struct {
    accel: f32 = 0.0019 * TileMap.tile_sz_f,
    friction: f32 = 0.0014 * TileMap.tile_sz_f,
    max_speed: f32 = 0.0125 * TileMap.tile_sz_f,
};

pub fn updateVel(self: *Thing, accel_dir: V2f, params: AccelParams) void {
    const speed_limit: f32 = 10;
    const min_speed_threshold = 0.001;

    const accel = accel_dir.scale(params.accel);
    const len = self.vel.length();
    var new_vel = self.vel;
    var len_after_accel: f32 = len;

    // max speed isn't a hard limit - we just can't accelerate past it
    // this allows being over max speed if it changed over time, or something else accelerated us
    if (len <= params.max_speed) {
        new_vel = self.vel.add(accel);
        len_after_accel = new_vel.length();
        if (len_after_accel > params.max_speed) {
            len_after_accel = params.max_speed;
            new_vel = new_vel.clampLength(params.max_speed);
        }
    }

    if (len_after_accel - params.friction > min_speed_threshold) {
        var n = new_vel.scale(1 / len_after_accel);
        new_vel = new_vel.sub(n.scale(params.friction));
        // speed limit is a hard limit. don't go past it
        new_vel = new_vel.clampLength(speed_limit);
    } else {
        new_vel = .{};
    }

    self.vel = new_vel;
}

pub fn getEffectiveAccelParams(self: *Thing) AccelParams {
    var accel_params = self.accel_params;
    if (self.pathing_layer == .normal) {
        if (self.statuses.get(.trailblaze).stacks > 0) {
            accel_params.accel = 0.3;
            accel_params.friction = 0.15;
            accel_params.max_speed *= 2;
        }
        if (self.statuses.get(.slimed).stacks > 0) {
            accel_params.max_speed *= 0.5;
        }
    }
    return accel_params;
}

// self-locomotion using regular movement (self.accel_params)
pub fn move(self: *Thing, dir: V2f) void {
    // probably a redundant check
    if (!self.canAct()) {
        return;
    }
    self.updateVel(dir, self.getEffectiveAccelParams());
}

pub fn debugDrawPath(self: *const Thing, room: *const Room) Error!void {
    const plat = getPlat();
    const inv_zoom = 1 / room.camera.zoom;
    const line_thickness = inv_zoom;
    for (0..self.path.len - 1) |i| {
        plat.arrowf(self.path.buffer[i], self.path.buffer[i + 1], .{ .thickness = line_thickness, .color = Colorf.green });
        //p.linef(self.path.buffer[i], self.path.buffer[i + 1], .{ .thickness = line_thickness, .color = Colorf.green });
    }
}

pub fn isEnemy(self: *const Thing) bool {
    if (self.faction == .enemy) return true;
    if (self.statuses.get(.blackmailed).stacks > 0) return true;

    return false;
}

pub fn isInvisible(self: *const Thing) bool {
    return self.statuses.get(.unseeable).stacks > 0;
}

pub fn isCreature(self: *const Thing) bool {
    return self.creature_kind != null;
}

pub inline fn isDeadCreature(self: *const Thing) bool {
    // if no hp, can still be alive creature - dead creatures have no hurtbox, but still have hp == 0
    return self.isActive() and self.isCreature() and (if (self.hp) |hp| hp.curr == 0 else false);
}

pub inline fn isAliveCreature(self: *const Thing) bool {
    return self.isActive() and self.isCreature() and (if (self.hp) |hp| hp.curr > 0 else true);
}

pub inline fn isAttackableCreature(self: *const Thing) bool {
    return self.isActive() and self.isCreature() and self.hurtbox != null;
}

pub const VisibleCircle = struct { pos: V2f, radius: f32 };
pub fn getApproxVisibleCircle(self: *const Thing) VisibleCircle {
    switch (self.controller) {
        .spawner => |s| {
            // TODO very hack for spawners - this leaves no frame gap where visible circle is different to spawning creature's
            if (s.state != .fade_out_circle or s.timer.curr_tick == 0) {
                var proto = App.get().data.creature_protos.get(s.creature_kind);
                proto.pos = self.pos;
                return proto.getApproxVisibleCircle();
            }
        },
        else => {},
    }
    var ret: VisibleCircle = .{
        .pos = self.pos,
        .radius = self.coll_radius,
    };
    if (self.selectable) |s| {
        ret.pos = self.pos.add(v2f(0, -(s.height - s.radius) * 0.5));
        ret.radius = (s.height) * 0.7;
    } else if (self.hitbox) |h| {
        ret.pos = self.pos.add(h.rel_pos);
        ret.radius = @max(h.radius, self.coll_radius);
    }
    return ret;
}

pub fn getRangeToHurtBox(self: *const Thing, pos: V2f) f32 {
    if (self.hurtbox) |hurtbox| {
        const hurtbox_pos = self.pos.add(hurtbox.rel_pos);
        const dist = hurtbox_pos.dist(pos);
        return @max(dist - hurtbox.radius, 0);
    }
    // default to coll_radius
    const dist = self.pos.dist(pos);
    return @max(dist - self.coll_radius, 0);
}
