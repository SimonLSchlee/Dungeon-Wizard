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

pub const Kind = enum {
    creature,
    projectile,
    shield,
    spawner,
    vfx,
    pickup,
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
        .smol = @round(0.2 * TileMap.tile_sz_f),
        .medium = @round(0.3 * TileMap.tile_sz_f),
        .big = @round(0.4 * TileMap.tile_sz_f),
    });
    pub const hurtbox_radii = std.EnumArray(SizeCategory, f32).init(.{
        .none = 0,
        .smol = @round(0.2 * TileMap.tile_sz_f),
        .medium = @round(0.3 * TileMap.tile_sz_f),
        .big = @round(0.4 * TileMap.tile_sz_f),
    });
    pub const select_radii = std.EnumArray(SizeCategory, f32).init(.{
        .none = 0,
        .smol = @round(0.25 * TileMap.tile_sz_f),
        .medium = @round(0.35 * TileMap.tile_sz_f),
        .big = @round(0.45 * TileMap.tile_sz_f),
    });
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
coll_radius: f32 = 0,
coll_mask: Collision.Mask = .{},
coll_layer: Collision.Mask = .{},
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
} = .default,
renderer: union(enum) {
    none: void,
    creature: CreatureRenderer,
    shape: ShapeRenderer,
    spawner: SpawnerRenderer,
    vfx: VFXRenderer,
} = .none,
animator: ?sprites.Animator = null,
path: std.BoundedArray(V2f, 32) = .{},
hitbox: ?HitBox = null,
hurtbox: ?HurtBox = null,
hp: ?HP = null,
mana: ?struct {
    curr: i32,
    max: i32,
} = null,
faction: Faction = .object,
selectable: ?struct {
    // its a half capsule shape
    radius: f32 = 20,
    height: f32 = 50,
} = null,
statuses: StatusEffect.StatusArray = StatusEffect.proto_array,
enemy_difficulty: f32 = 0,
find_path_timer: utl.TickCounter = utl.TickCounter.init(6),

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

    pub fn healNoVFX(hp: *HP, amount: f32) f32 {
        const amount_healed = @min(amount, hp.max - hp.curr);
        hp.curr += amount_healed;
        return amount_healed;
    }

    pub fn heal(hp: *HP, amount: f32, self: *Thing, room: *Room) void {
        const amount_healed = hp.healNoVFX(amount);
        const proto = Thing.LoopVFXController.proto(
            .swirlies,
            .loop,
            0.8,
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

    pub fn doDamage(self: *HP, amount: f32, thing: *Thing, room: *Room) void {
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
                hp.doDamage(damage, self, room);
                const post_damage_done = hp.total_damage_done;
                if (room.init_params.mode == .crispin_picker and self.isEnemy()) {
                    const total_manas = @max(@ceil(self.enemy_difficulty * 2.5), 1);
                    const damage_per_mana = hp.max / total_manas;
                    const post_manas = @floor(post_damage_done / damage_per_mana);
                    const pre_manas = @floor(pre_damage_done / damage_per_mana);
                    const num_manas = utl.as(usize, post_manas - pre_manas);
                    ManaPickupController.spawnSome(num_manas, self.pos, room);
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
    anim_to_loop: sprites.AnimName = .loop,
    tint: Colorf = .white,
    timer: utl.TickCounter = utl.TickCounter.init(core.secsToTicks(2)),
    state: enum {
        loop,
        fade,
    } = .loop,

    pub fn update(self: *Thing, room: *Room) Error!void {
        assert(self.spawn_state == .spawned);
        const controller = &self.controller.loop_vfx;

        _ = self.animator.?.play(controller.anim_to_loop, .{ .loop = true });

        switch (controller.state) {
            .loop => {
                if (controller.timer.tick(false)) {
                    controller.timer = utl.TickCounter.init(core.secsToTicks(1));
                    controller.state = .fade;
                }
            },
            .fade => {
                self.renderer.vfx.sprite_tint = controller.tint.fade(1 - controller.timer.remapTo0_1());
                if (controller.timer.tick(false)) {
                    self.deferFree(room);
                }
            },
        }
    }
    pub fn proto(spritesheet: sprites.VFXAnim.SheetName, anim: sprites.AnimName, lifetime_secs: f32, tint: Colorf, draw_over: bool) Thing {
        return Thing{
            .kind = .vfx,
            .controller = .{ .loop_vfx = .{
                .anim_to_loop = anim,
                .timer = utl.TickCounter.init(core.secsToTicks(@max(lifetime_secs - 1, 0))),
                .tint = tint,
            } },
            .renderer = .{
                .vfx = .{
                    .draw_normal = !draw_over,
                    .draw_over = draw_over,
                },
            },
            .animator = .{
                .kind = .{
                    .vfx = .{
                        .sheet_name = spritesheet,
                    },
                },
                .curr_anim = anim,
            },
        };
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
                self.pos.y -= 2;
                self.pos.x = controller.initial_pos.x + ((@sin((f + controller.roffset) * utl.pi * 2) * 2) - 1) * 3;
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
        proto.renderer.shape.kind.text.opt.size *= utl.as(u32, scale + 1);
        proto.renderer.shape.kind.text.opt.border.?.dist *= (scale + 1);

        _ = try room.queueSpawnThing(&proto, rpos);
    }
};

pub const CastVFXController = struct {
    parent: Thing.Id,
    anim_to_play: sprites.AnimName = .basic_loop,

    pub fn update(self: *Thing, room: *Room) Error!void {
        assert(self.spawn_state == .spawned);
        const controller = &self.controller.cast_vfx;

        if (room.getThingById(controller.parent)) |parent| {
            if (parent.isDeadCreature()) {
                controller.anim_to_play = .basic_fizzle;
            }
        } else {
            controller.anim_to_play = .basic_fizzle;
        }

        switch (controller.anim_to_play) {
            .basic_loop => {
                _ = self.animator.?.play(controller.anim_to_play, .{ .loop = true });
            },
            else => |anim_name| {
                if (self.animator.?.play(anim_name, .{}).contains(.end)) {
                    self.deferFree(room);
                }
            },
        }
    }

    pub fn castingProto(caster: *Thing) Thing {
        var cast_offset = V2f{};
        if (App.get().data.getCreatureAnimOrDefault(caster.animator.?.kind.creature.kind, .cast)) |anim| {
            cast_offset = anim.cast_offset.scale(core.game_sprite_scaling);
            if (caster.dir.x < 0) {
                cast_offset.x *= -1;
            }
        }
        const cast_pos = caster.pos.add(cast_offset);
        return .{
            .kind = .vfx,
            .pos = cast_pos,
            .controller = .{
                .cast_vfx = .{
                    .parent = caster.id,
                },
            },
            .renderer = .{ .vfx = .{
                .draw_over = true,
                .draw_normal = false,
            } },
            .animator = .{
                .kind = .{
                    .vfx = .{
                        .sheet_name = .spellcasting,
                    },
                },
                .curr_anim = .basic_loop,
            },
        };
    }
};

pub const VFXRenderer = struct {
    sprite_tint: Colorf = .white,
    draw_normal: bool = true,
    draw_over: bool = false,
    rotate_to_dir: bool = false,
    flip_x_to_dir: bool = false,

    pub fn _render(self: *const Thing, renderer: *const VFXRenderer, _: *const Room) void {
        const plat = App.getPlat();
        const frame = self.animator.?.getCurrRenderFrame();
        const tint: Colorf = renderer.sprite_tint;
        var opt = draw.TextureOpt{
            .origin = frame.origin,
            .src_pos = frame.pos.toV2f(),
            .src_dims = frame.size.toV2f(),
            .uniform_scaling = core.game_sprite_scaling,
            .tint = tint,
            .flip_x = renderer.flip_x_to_dir and self.dir.x < 0,
            .rot_rads = if (renderer.rotate_to_dir) self.dir.toAngleRadians() else 0,
        };
        if (opt.flip_x and renderer.rotate_to_dir and self.dir.x < 0) {
            opt.rot_rads += utl.pi;
        }
        plat.texturef(self.pos, frame.texture, opt);
    }

    pub fn render(self: *const Thing, room: *const Room) Error!void {
        const renderer = &self.renderer.vfx;
        if (renderer.draw_normal) {
            _render(self, renderer, room);
        }
    }

    pub fn renderOver(self: *const Thing, room: *const Room) Error!void {
        const renderer = &self.renderer.vfx;
        if (renderer.draw_over) {
            _render(self, renderer, room);
        }
    }
};

pub const SpawnerRenderer = struct {
    creature_kind: sprites.CreatureAnim.Kind,
    base_circle_radius: f32,
    sprite_tint: Colorf = .blank,
    base_circle_color: Colorf = .blank,

    pub fn renderUnder(self: *const Thing, _: *const Room) Error!void {
        const renderer = &self.renderer.spawner;
        const plat = App.getPlat();
        plat.circlef(self.pos, renderer.base_circle_radius, .{ .fill_color = renderer.base_circle_color, .smoothing = .bilinear });
    }

    pub fn render(self: *const Thing, _: *const Room) Error!void {
        const renderer = &self.renderer.spawner;
        const plat = App.getPlat();
        const anim = App.get().data.getCreatureAnim(renderer.creature_kind, .idle).?;
        const frame = anim.getRenderFrame(V2f.right, 0);
        const tint: Colorf = renderer.sprite_tint;
        const opt = draw.TextureOpt{
            .origin = frame.origin,
            .src_pos = frame.pos.toV2f(),
            .src_dims = frame.size.toV2f(),
            .uniform_scaling = core.game_sprite_scaling,
            .tint = tint,
        };
        plat.texturef(self.pos, frame.texture, opt);
    }
};

pub const ManaPickupController = struct {
    state: enum {
        loop,
        collected,
    } = .loop,
    fading: bool = false,
    timer: utl.TickCounter = utl.TickCounter.init(core.secsToTicks(8)),

    pub fn update(self: *Thing, room: *Room) Error!void {
        const controller = &self.controller.mana_pickup;
        const animator = &self.animator.?;
        const renderer = &self.renderer.vfx;
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
                _ = animator.play(.loop, .{ .loop = true });
                if (p.mana) |*mana| {
                    if (mana.curr < mana.max) {
                        if (Collision.getCircleCircleCollision(self.pos, self.coll_radius, p.pos, p.renderer.creature.draw_radius)) |_| {
                            mana.curr += 1;
                            controller.state = .collected;
                        }
                    }
                }
            },
            .collected => {
                renderer.draw_normal = false;
                renderer.draw_over = true;
                if (animator.play(.end, .{}).contains(.end)) {
                    self.deferFree(room);
                }
            },
        }
        if (self.last_coll) |c| {
            const d = self.vel.sub(c.normal.scale(self.vel.dot(c.normal) * 2));
            self.vel = d;
        }
        self.updateVel(.{}, .{ .friction = 0.01 });
    }
    pub fn spawnSome(num: usize, pos: V2f, room: *Room) void {
        const radius = 14;
        var proto = Thing{
            .kind = .pickup,
            .coll_radius = radius,
            .coll_mask = Collision.Mask.initOne(.tile),
            .controller = .{ .mana_pickup = .{} },
            .renderer = .{
                .vfx = .{},
            },
            .animator = .{
                .kind = .{
                    .vfx = .{
                        .sheet_name = .mana_pickup,
                    },
                },
                .curr_anim = .loop,
            },
        };
        var rnd = room.rng.random();
        for (0..num) |_| {
            const rdir = V2f.fromAngleRadians(rnd.float(f32) * utl.tau);
            const rdist = 10 + rnd.float(f32) * 30;
            proto.vel = rdir.scale(0.5 + rnd.float(f32) * 1);
            _ = room.queueSpawnThing(&proto, pos.add(rdir.scale(rdist))) catch {};
        }
    }
};

pub const SpawnerController = struct {
    timer: utl.TickCounter = utl.TickCounter.init(1 * core.fups_per_sec / 2),
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
                    _ = try room.queueSpawnThing(&proto, self.pos);
                    spawner.state = .fade_out_circle;
                }
            },
            .fade_out_circle => {
                self.renderer.spawner.sprite_tint = .blank;
                self.renderer.spawner.base_circle_color = Colorf.white.fade(1 - spawner.timer.remapTo0_1());
                if (spawner.timer.tick(false)) {
                    self.deferFree(room);
                }
            },
        }
    }

    pub fn prototype(creature_kind: CreatureKind) Thing {
        const proto: Thing = App.get().data.creature_protos.get(creature_kind);
        return .{
            .kind = .spawner,
            .controller = .{
                .spawner = .{
                    .creature_kind = creature_kind,
                },
            },
            .renderer = .{
                .spawner = .{
                    .creature_kind = proto.animator.?.kind.creature.kind,
                    .base_circle_radius = proto.renderer.creature.draw_radius,
                },
            },
            .faction = proto.faction, // to ensure num_enemies_alive > 0
        };
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

pub const CreatureRenderer = struct {
    draw_radius: f32 = 20,
    draw_color: Colorf = Colorf.red,

    pub fn renderUnder(self: *const Thing, _: *const Room) Error!void {
        assert(self.spawn_state == .spawned);
        const plat = getPlat();
        const renderer = &self.renderer.creature;

        if (self.isAliveCreature()) {
            plat.circlef(self.pos, renderer.draw_radius, .{
                .fill_color = null,
                .outline = .{ .color = renderer.draw_color },
            });
            const arrow_start = self.pos.add(self.dir.scale(renderer.draw_radius));
            const arrow_end = self.pos.add(self.dir.scale(renderer.draw_radius + 5));
            plat.arrowf(arrow_start, arrow_end, .{ .thickness = 5, .color = renderer.draw_color });
        }
    }

    pub fn render(self: *const Thing, room: *const Room) Error!void {
        assert(self.spawn_state == .spawned);
        const plat = getPlat();

        if (debug.show_selectable) {
            if (self.selectable) |s| {
                if (room.moused_over_thing) |m| {
                    if (m.thing.eql(self.id)) {
                        const opt = draw.PolyOpt{ .fill_color = Colorf.cyan };
                        plat.circlef(self.pos, s.radius, opt);
                        plat.rectf(self.pos.sub(v2f(s.radius, s.height)), v2f(s.radius * 2, s.height), opt);
                    }
                }
            }
        }

        const animator = self.animator.?;
        const frame = animator.getCurrRenderFrameDir(self.dir);
        var tint: Colorf = blk: {
            if (self.isAliveCreature()) {
                if (self.statuses.get(.frozen).stacks > 0) break :blk StatusEffect.proto_array.get(.frozen).color;
                if (self.statuses.get(.exposed).stacks > 0) break :blk StatusEffect.proto_array.get(.exposed).color.lerp(.white, 0.25);
            }
            break :blk .white;
        };
        if (self.isAliveCreature() and self.statuses.get(.unseeable).stacks > 0) tint.a = 0.5;
        const opt = draw.TextureOpt{
            .origin = frame.origin,
            .src_pos = frame.pos.toV2f(),
            .src_dims = frame.size.toV2f(),
            .uniform_scaling = core.game_sprite_scaling,
            .tint = tint,
        };
        plat.texturef(self.pos, frame.texture, opt);

        const protected = self.statuses.get(.protected);
        if (self.isAliveCreature() and protected.stacks > 0) {
            // TODO dont use select radius
            const r = if (self.selectable) |s| s.height * 0.5 else self.coll_radius;
            const shield_center = self.pos.sub(v2f(0, r));
            const popt = draw.PolyOpt{
                .fill_color = null,
                .outline = .{ .color = StatusEffect.proto_array.get(.protected).color },
            };
            for (0..utl.as(usize, protected.stacks)) |i| {
                plat.circlef(shield_center, r * 2 + 2 + utl.as(f32, i) * 2, popt);
            }
        }
    }

    pub fn renderOver(self: *const Thing, _: *const Room) Error!void {
        assert(self.spawn_state == .spawned);
        const plat = getPlat();
        const renderer = &self.renderer.creature;

        const hp_height = 6;
        const hp_width = renderer.draw_radius * 2;
        const hp_y_offset = if (self.selectable) |s| s.height + 20 else renderer.draw_radius * 3.5;
        const hp_offset = v2f(-hp_width * 0.5, -hp_y_offset);
        const shields_y_offset = hp_y_offset - hp_height;
        const shields_height = 6;
        const shields_offset = v2f(-hp_width * 0.5, -shields_y_offset);

        if (self.isAliveCreature()) {
            if (self.hp) |hp| {
                const curr_width = utl.remapClampf(0, hp.max, 0, hp_width, hp.curr);
                const hp_topleft = self.pos.add(hp_offset);
                plat.rectf(hp_topleft, v2f(hp_width, hp_height), .{ .fill_color = Colorf.black });
                plat.rectf(hp_topleft, v2f(curr_width, hp_height), .{ .fill_color = HP.faction_colors.get(self.faction) });
                { // lines
                    const line_hp_inc: f32 = if (hp.max < 100) 10 else 50;
                    var i: f32 = line_hp_inc;
                    while (i < hp.curr) {
                        const line_x = curr_width * (i / hp.curr);
                        const top = hp_topleft.add(v2f(line_x, 0));
                        const bot = hp_topleft.add(v2f(line_x, hp_height));
                        plat.linef(top, bot, .{
                            .thickness = 1,
                            .color = Colorf.black.fade(0.5),
                            .round_to_pixel = true,
                        });
                        i += line_hp_inc;
                    }
                }
                var total_shield_amount: f32 = 0;
                var curr_shield_amount: f32 = 0;
                for (hp.shields.constSlice()) |shield| {
                    total_shield_amount += shield.max;
                    curr_shield_amount += shield.curr;
                }
                if (total_shield_amount > 0) {
                    const shield_color = Colorf.rgb(0.7, 0.7, 0.4);
                    const shields_topleft = self.pos.add(shields_offset);
                    var curr_pos = shields_topleft;
                    for (hp.shields.constSlice()) |shield| {
                        const shield_width = hp_width * shield.curr / total_shield_amount;
                        plat.rectf(curr_pos, v2f(shield_width, shields_height), .{
                            .fill_color = shield_color,
                            .smoothing = .bilinear,
                            .round_to_pixel = true,
                        });
                        curr_pos.x += shield_width;
                    }
                    { // lines
                        const curr_shield_width = utl.remapClampf(0, total_shield_amount, 0, hp_width, curr_shield_amount);
                        const line_shield_inc: f32 = if (total_shield_amount < 100) 10 else 50;
                        var i: f32 = 0;
                        while (i <= curr_shield_amount) {
                            const line_x = curr_shield_width * (i / curr_shield_amount);
                            const top = shields_topleft.add(v2f(line_x, 0));
                            const bot = shields_topleft.add(v2f(line_x, shields_height));
                            plat.linef(top, bot, .{
                                .thickness = 1,
                                .color = Colorf.black.fade(0.5),
                                .smoothing = .bilinear,
                                .round_to_pixel = true,
                            });
                            i += line_shield_inc;
                        }
                    }
                }
                if (self.mana) |mana| {
                    const mana_bar_width = hp_width;
                    const mana_bar_height = 15;
                    const mana_topleft = hp_topleft.sub(v2f(0, mana_bar_height));
                    const mana_inc_px = mana_bar_width / utl.as(f32, mana.max);
                    // restrict radius to keep 4 pixels around it even when only 1-2 mana
                    const mana_diam = @min(mana_inc_px * 0.8, mana_bar_height - 4);
                    const mana_radius = mana_diam * 0.5;
                    const mana_spacing = (mana_inc_px - mana_diam) * 0.666666; // this makes sense cos of reasons
                    var curr_pos = mana_topleft.add(v2f(mana_spacing + mana_radius, mana_bar_height * 0.5));
                    for (0..utl.as(usize, mana.curr)) |_| {
                        plat.circlef(curr_pos, mana_radius, .{
                            .fill_color = Colorf.rgb(0, 0.5, 1),
                            .outline = .{ .color = .black },
                        });
                        curr_pos.x += mana_spacing + mana_diam;
                    }
                }
            }
            // debug draw statuses
            const status_height = 14;
            const status_y_offset = shields_y_offset - (shields_height + 3);
            var status_pos = self.pos.add(v2f(-hp_width * 0.5, -status_y_offset));
            for (self.statuses.values) |status| {
                if (status.stacks == 0) continue;
                const text = try utl.bufPrintLocal("{}", .{status.stacks});
                const text_dims = try plat.measureText(text, .{ .size = status_height - 1 });
                const status_box_width = text_dims.x;
                const text_color = Colorf.getContrasting(status.color);
                plat.rectf(status_pos, v2f(status_box_width, status_height), .{ .fill_color = status.color });
                try plat.textf(status_pos, "{s}", .{text}, .{ .size = status_height - 1, .color = text_color });
                status_pos.x += status_box_width;
            }
        }
    }
};

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

inline fn canAct(self: *const Thing) bool {
    if (self.creature_kind != null) {
        return self.isAliveCreature() and self.statuses.get(.frozen).stacks == 0 and self.statuses.get(.stunned).stacks == 0;
    }
    return self.isActive();
}

pub fn update(self: *Thing, room: *Room) Error!void {
    _ = self.find_path_timer.tick(false);
    if (self.canAct()) {
        try updateController(self, room);
        if (self.statuses.get(.promptitude).stacks > 0) {
            try updateController(self, room);
        }
    } else if (self.isDeadCreature()) {
        if (self.animator.?.play(.die, .{}).contains(.end)) {
            self.deferFree(room);
        }
        return;
    } else {
        self.updateVel(.{}, .{});
    }
    self.moveAndCollide(room);
    if (self.statuses.get(.promptitude).stacks > 0) {
        self.moveAndCollide(room);
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
            plat.arrowf(coll.pos, coll.pos.add(coll.normal.scale(self.coll_radius * 0.75)), 3, Colorf.red);
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
                        plat.arrowf(self.pos, target.pos, .{ .color = .red, .thickness = 2 });
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
        if (_coll == null and self.coll_mask.contains(.tile)) {
            _coll = Collision.getCircleCollisionWithTiles(self.pos, self.coll_radius, &room.tilemap);
        }

        if (_coll) |coll| {
            self.last_coll = coll;
            // push out
            if (coll.pen_dist > 0) {
                self.pos = coll.pos.add(coll.normal.scale(self.coll_radius + 1));
            }
            switch (coll.kind) {
                .thing => |id| {
                    if (room.getThingById(id)) |thing| {
                        thing.updateVel(coll.normal.neg(), .{ .accel = self.vel.length() * 0.5, .max_speed = self.accel_params.max_speed * 0.5 });
                    }
                },
                else => {},
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
    self.path = try room.tilemap.findPathThetaStar(getPlat().heap, self.pos, goal, self.coll_radius, &self.dbg.coords_searched);
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
    accel: f32 = 0.125,
    friction: f32 = 0.09,
    max_speed: f32 = 0.8,
};

pub fn updateVel(self: *Thing, accel_dir: V2f, params: AccelParams) void {
    const speed_limit: f32 = 20;
    const min_speed_threshold = 0.001;

    const accel = accel_dir.scale(params.accel);
    const len = self.vel.length();
    var new_vel = self.vel;
    var len_after_accel: f32 = len;

    // max speed isn't a hard limit - we just can't accelerate past it
    // this allows being over max speed if it changed over time, or something else accelerated us
    if (len < params.max_speed) {
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

pub fn debugDrawPath(self: *const Thing, room: *const Room) Error!void {
    const plat = getPlat();
    const inv_zoom = 1 / room.camera.zoom;
    const line_thickness = inv_zoom;
    for (0..self.path.len - 1) |i| {
        plat.arrowf(self.path.buffer[i], self.path.buffer[i + 1], line_thickness, Colorf.green);
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
    return self.isActive() and self.isCreature() and (if (self.hp) |hp| hp.curr == 0 else true);
}

pub inline fn isAliveCreature(self: *const Thing) bool {
    return self.isActive() and self.isCreature() and (if (self.hp) |hp| hp.curr > 0 else true);
}

pub inline fn isAttackableCreature(self: *const Thing) bool {
    return self.isActive() and self.isCreature() and self.hurtbox != null;
}

pub fn getApproxVisibleCircle(self: *const Thing) struct { pos: V2f, radius: f32 } {
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
    var ret = .{
        .pos = self.pos,
        .radius = self.coll_radius,
    };
    if (self.selectable) |s| {
        ret.pos = self.pos.add(v2f(0, -(s.height - s.radius) * 0.5));
        ret.radius = (s.height) * 0.5;
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
