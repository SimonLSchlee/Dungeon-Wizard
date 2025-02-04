const std = @import("std");
const core = @import("core.zig");
const utl = @import("util.zig");

const Error = core.Error;
const V2f = @import("V2f.zig");
const v2f = V2f.v2f;
const V2i = @import("V2i.zig");
const v2i = V2i.v2i;
const iToV2f = V2f.iToV2f;
const iToV2i = V2i.iToV2i;

pub const Rectf = struct {
    pos: V2f = .{},
    dims: V2f = .{},
};

pub fn pointIsInRectf(p: V2f, rect: Rectf) bool {
    const botright = rect.pos.add(rect.dims);
    return p.x >= rect.pos.x and p.x <= botright.x and p.y >= rect.pos.y and p.y <= botright.y;
}

pub fn rectsAreIntersecting(rect_a: Rectf, rect_b: Rectf) bool {
    const botright_a = rect_a.pos.add(rect_a.dims);
    const botright_b = rect_b.pos.add(rect_b.dims);
    return botright_a.x >= rect_b.pos.x and rect_a.pos.x <= botright_b.x and botright_a.y >= rect_b.pos.y and rect_a.pos.y <= botright_b.y;
}

pub fn pointIsInSector(pos_a: V2f, pos_seg: V2f, radius_seg: f32, start_rads: f32, end_rads: f32) bool {
    const seg_to_a = pos_a.sub(pos_seg);
    const dist = seg_to_a.length();
    if (dist > radius_seg) return false;

    const a_rads = utl.normalizeRadians0_Tau(seg_to_a.toAngleRadians());
    const start_n = utl.normalizeRadians0_Tau(start_rads);
    const end_n = utl.normalizeRadians0_Tau(end_rads);

    if (start_n <= end_n) {
        return a_rads >= start_n and a_rads <= end_n;
    } else {
        return a_rads < end_n or a_rads > start_n;
    }
}

pub const LineSegIntersection = union(enum) {
    none, // no intersection
    colinear: ?[2]V2f, // colinear; either disjoint (null) or overlapping on 2 points
    intersection: V2f, // intersection point
};

// lineA = p + tr
// lineB = q + us
pub fn lineSegsIntersect(p: V2f, r: V2f, q: V2f, s: V2f) LineSegIntersection {
    const rxs = r.cross(s);
    const p_to_q = q.sub(p);
    const p_to_q_x_r = p_to_q.cross(r);
    const p_to_q_x_s = p_to_q.cross(s);

    if (@abs(rxs) < 0.0001) {
        if (@abs(p_to_q_x_r) < 0.0001) {
            // colinear
            const rr = r.dot(r);
            const _t0 = p_to_q.dot(r) / rr;
            const _t1 = p_to_q.add(s).dot(r) / rr;
            var t0 = _t0;
            var t1 = _t1;
            if (r.dot(s) < 0) {
                utl.swap(f32, &t0, &t1);
            }
            // outside of [0,1] means outside of p + tr, so colinear but not intersecting
            if (t1 < 0 or t0 > 1) {
                return .{ .colinear = null };
            }
            // sort the t's (all relative to p + tr), also sort the points that will be the intersections
            const same_dir = r.dot(s) >= 0;
            var points_sorted = [4]V2f{ p, p.add(r), q, q.add(s) };
            //std.debug.print("{any}\n", .{points_sorted});
            if (!same_dir) utl.swap(V2f, &points_sorted[2], &points_sorted[3]);
            var ts_sorted = [4]f32{ 0, 1, t0, t1 };
            for (0..4) |i| {
                for (i + 1..4) |j| {
                    if (ts_sorted[i] > ts_sorted[j]) {
                        utl.swap(f32, &ts_sorted[i], &ts_sorted[j]);
                        utl.swap(V2f, &points_sorted[i], &points_sorted[j]);
                    }
                }
            }
            // with the t's sorted, the middle points are the intersection!
            // use original numbers so there's no fp error
            return .{ .colinear = .{ points_sorted[1], points_sorted[2] } };
        } else {
            // parallel
            return .none;
        }
    }

    const t = p_to_q_x_s / rxs;
    const u = p_to_q_x_r / rxs;
    // Note: point is at p + tr = q + us
    if (t >= 0 and t <= 1 and u >= 0 and u <= 1) {
        return .{ .intersection = p.add(r.scale(t)) };
    }

    // lines intersect, but segments don't
    return .none;
}

test "lineSegsIntersect() - intersect 1" {
    const p = v2f(0, 0);
    const r = v2f(2, 2);
    const q = v2f(2, 0);
    const s = v2f(-2, 2);
    const expected: LineSegIntersection = .{ .intersection = v2f(1, 1) };
    try std.testing.expectEqual(expected, lineSegsIntersect(p, r, q, s));
}

test "lineSegsIntersect() - intersect 2" {
    const p = v2f(-1, 0);
    const r = v2f(2, 0);
    const q = v2f(0, 1);
    const s = v2f(0, -2);
    const expected: LineSegIntersection = .{ .intersection = v2f(0, 0) };
    try std.testing.expectEqual(expected, lineSegsIntersect(p, r, q, s));
}

test "lineSegsIntersect() - intersect 3" {
    const p = v2f(-32, 32);
    const r = v2f(164, 35).sub(p);
    const q = v2f(128, 64);
    const s = v2f(128, 0).sub(q);
    const expected = std.meta.activeTag(LineSegIntersection{ .intersection = .{} });
    try std.testing.expectEqual(expected, std.meta.activeTag(lineSegsIntersect(p, r, q, s)));
}

test "lineSegsIntersect() - would intersect but miss" {
    const p = v2f(0, 0);
    const r = v2f(2, 2);
    const q = v2f(-1, 0);
    const s = v2f(-2, 2);
    const expected: LineSegIntersection = .none;
    try std.testing.expectEqual(expected, lineSegsIntersect(p, r, q, s));
}

test "lineSegsIntersect() - parallel" {
    const p = v2f(0, 0);
    const r = v2f(2, 2);
    const q = v2f(1, 0);
    const s = v2f(2, 2);
    const expected: LineSegIntersection = .none;
    try std.testing.expectEqual(expected, lineSegsIntersect(p, r, q, s));
}

test "lineSegsIntersect() - colinear same direction, t0 > 1" {
    const p = v2f(0, 0);
    const r = v2f(2, 2);
    const q = v2f(3, 3);
    const s = v2f(2, 2);
    const expected: LineSegIntersection = .{ .colinear = null };
    try std.testing.expectEqual(expected, lineSegsIntersect(p, r, q, s));
}

test "lineSegsIntersect() - colinear same direction, t1 < 0" {
    const p = v2f(0, 0);
    const r = v2f(2, 2);
    const q = v2f(-3, -3);
    const s = v2f(2, 2);
    const expected: LineSegIntersection = .{ .colinear = null };
    try std.testing.expectEqual(expected, lineSegsIntersect(p, r, q, s));
}

test "lineSegsIntersect() - colinear same direction, t0 >= 0" {
    const p = v2f(0, 0);
    const r = v2f(2, 2);
    const q = v2f(1, 1);
    const s = v2f(2, 2);
    const expected: LineSegIntersection = .{ .colinear = .{ q, p.add(r) } };
    try std.testing.expectEqual(expected, lineSegsIntersect(p, r, q, s));
}

test "lineSegsIntersect() - colinear same direction, t0 < 0" {
    const p = v2f(1, 1);
    const r = v2f(2, 2);
    const q = v2f(0, 0);
    const s = v2f(2, 2);
    const expected: LineSegIntersection = .{ .colinear = .{ p, q.add(s) } };
    try std.testing.expectEqual(expected, lineSegsIntersect(p, r, q, s));
}

test "lineSegsIntersect() - colinear opp direction, t0 >= 0" {
    const p = v2f(0, 0);
    const r = v2f(2, 2);
    const q = v2f(3, 3);
    const s = v2f(-2, -2);
    const expected: LineSegIntersection = .{ .colinear = .{ q.add(s), p.add(r) } };
    try std.testing.expectEqual(expected, lineSegsIntersect(p, r, q, s));
}

test "lineSegsIntersect() - colinear opp direction, t0 < 0" {
    const p = v2f(1, 1);
    const r = v2f(2, 2);
    const q = v2f(1, 1);
    const s = v2f(-2, -2);
    const expected: LineSegIntersection = .{ .colinear = .{ p, q } };
    try std.testing.expectEqual(expected, lineSegsIntersect(p, r, q, s));
}

test "lineSegsIntersect() - colinear opp direction, t0 > 1" {
    const p = v2f(0, 0);
    const r = v2f(2, 2);
    const q = v2f(5, 5);
    const s = v2f(-2, -2);
    const expected: LineSegIntersection = .{ .colinear = null };
    try std.testing.expectEqual(expected, lineSegsIntersect(p, r, q, s));
}

test "lineSegsIntersect() - colinear opp direction, t1 < 0" {
    const p = v2f(0, 0);
    const r = v2f(2, 2);
    const q = v2f(-1, -1);
    const s = v2f(-2, -2);
    const expected: LineSegIntersection = .{ .colinear = null };
    try std.testing.expectEqual(expected, lineSegsIntersect(p, r, q, s));
}

pub fn clampPointToRect(point: V2f, rect: Rectf) V2f {
    return v2f(
        utl.clampf(point.x, rect.pos.x, rect.pos.x + rect.dims.x),
        utl.clampf(point.y, rect.pos.y, rect.pos.y + rect.dims.y),
    );
}
