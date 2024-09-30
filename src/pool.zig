const std = @import("std");
const assert = std.debug.assert;
const u = @import("util.zig");

// NOTE: this won't work with hot reload. To use, use initWithGlobalId
var global_pool_id: u32 = 0;

pub const Id = struct {
    const Self = @This();

    pool: u32 = 0,
    idx: u32 = 0,
    gen: u64 = 0,

    pub fn eql(self: Self, other: Self) bool {
        return self.pool == other.pool and self.idx == other.idx and self.gen == other.gen;
    }
};

pub const AllocState = union(enum) {
    free: ?usize,
    allocated,
};

pub const ExamplePoolType = struct {
    id: Id, // must be named id
    foo: u32,
    alloc_state: AllocState, // must be named alloc_state
    bar: f64,
};

fn checkPoolMemberType(MemberType: type) void {
    const info = @typeInfo(MemberType);
    switch (info) {
        .@"struct" => |s| {
            var found_alloc_state = false;
            var found_id = false;
            for (s.fields) |field| {
                if (std.mem.eql(u8, field.name, "id")) {
                    if (field.type == Id) {
                        found_id = true;
                    }
                }
                if (std.mem.eql(u8, field.name, "alloc_state")) {
                    if (field.type == AllocState) {
                        found_alloc_state = true;
                    }
                }
            }
            if (!found_alloc_state) {
                @compileError("Pool MemberType must contain a field named 'alloc_state' of type " ++ @typeName(AllocState));
            }
            if (!found_id) {
                @compileError("Pool MemberType must contain a field named 'id' of type " ++ @typeName(Id));
            }
        },
        else => @compileError("Pool MemberType must be a struct"),
    }
}

pub fn BoundedPool(MemberType: type, size: usize) type {
    checkPoolMemberType(MemberType);

    return struct {
        const Self = @This();

        id: u32 = undefined,
        items: [size]MemberType = undefined,
        num_allocated: usize = 0,
        next_free: ?usize = null,

        pub fn init(id: u32) Self {
            var ret = Self{
                .id = id,
                .next_free = 0,
            };
            for (&ret.items, 0..) |*item, i| {
                item.id.pool = ret.id;
                item.id.idx = u.as(u32, i);
                item.id.gen = 0;
                item.alloc_state = .{ .free = i + 1 };
            }
            ret.items[ret.items.len - 1].alloc_state.free = null;

            return ret;
        }

        pub fn initWithGlobalId() Self {
            const ret = init(global_pool_id);
            global_pool_id += 1;
            return ret;
        }

        pub fn alloc(self: *Self) ?*MemberType {
            if (self.next_free) |next_free| {
                var item = &self.items[next_free];
                assert(item.alloc_state == .free);
                self.next_free = item.alloc_state.free;
                if (self.next_free) |new_next_free| {
                    assert(new_next_free < self.items.len);
                }
                item.alloc_state = .allocated;
                assert(self.num_allocated < self.items.len);
                self.num_allocated += 1;
                return item;
            }
            return null;
        }

        pub fn free(self: *Self, id: Id) void {
            const index = u.as(usize, id.idx);
            if (index >= self.items.len) {
                std.log.warn("{s}: Attempt to free invalid index\n", .{@typeName(Self)});
                return;
            }
            var item = &self.items[index];
            if (item.alloc_state == .free) {
                std.log.warn("{s}: Attempt to double free\n", .{@typeName(Self)});
                return;
            }
            if (!item.id.eql(id)) {
                if (item.id.pool != id.pool) {
                    std.log.warn("{s}: Attempt to free with invalid pool id\n", .{@typeName(Self)});
                }
                return;
            }
            assert(self.num_allocated > 0);
            self.num_allocated -= 1;
            item.id.gen += 1;
            item.alloc_state = .{ .free = self.next_free };
            self.next_free = index;
        }

        pub fn get(self: *Self, id: Id) ?*MemberType {
            const index = u.as(usize, id.idx);
            if (index >= self.items.len) {
                std.log.warn("{s}: Attempt to get invalid index\n", .{@typeName(Self)});
                return null;
            }
            const item = &self.items[index];
            if (item.alloc_state != .free and item.id.eql(id)) {
                return item;
            }
            return null;
        }

        pub fn getConst(self: *const Self, id: Id) ?*const MemberType {
            const index = u.as(usize, id.idx);
            if (index >= self.items.len) {
                std.log.warn("{s}: Attempt to get invalid index\n", .{@typeName(Self)});
                return null;
            }
            const item = &self.items[index];
            if (item.alloc_state != .free and item.id.eql(id)) {
                return item;
            }
            return null;
        }
    };
}
