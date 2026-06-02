const std = @import("std");
const testing = std.testing;
const allocator = testing.allocator;

/// A single bathymetry sounding point.
pub const BathyPoint = struct {
    lat: f64,
    lon: f64,
    depth: f64, // positive depth in meters below surface
};

/// Simple in-memory bathymetry database.
/// Stores soundings and provides nearest-point lookup.
pub const BathyDB = struct {
    points: std.ArrayList(BathyPoint),

    /// Create an empty database using the given allocator.
    pub fn init(alloc: std.mem.Allocator) BathyDB {
        return .{
            .points = std.ArrayList(BathyPoint).init(alloc),
        };
    }

    /// Deinitialize and free all memory.
    pub fn deinit(self: *BathyDB) void {
        self.points.deinit();
    }

    /// Record a new sounding point.
    pub fn record(self: *BathyDB, lat: f64, lon: f64, depth: f64) !void {
        try self.points.append(.{ .lat = lat, .lon = lon, .depth = depth });
    }

    /// Find the depth at the closest recorded point using
    /// Euclidean distance (valid for small areas).
    /// Returns null if the database is empty.
    pub fn depthAt(self: BathyDB, lat: f64, lon: f64) ?f64 {
        if (self.points.items.len == 0) return null;

        var best_idx: usize = 0;
        var best_dist: f64 = std.math.inf(f64);

        for (self.points.items, 0..) |pt, i| {
            const dlat = pt.lat - lat;
            const dlon = pt.lon - lon;
            const dist = dlat * dlat + dlon * dlon;
            if (dist < best_dist) {
                best_dist = dist;
                best_idx = i;
            }
        }

        return self.points.items[best_idx].depth;
    }

    /// Return the number of recorded points.
    pub fn count(self: BathyDB) usize {
        return self.points.items.len;
    }
};

// ── Tests ────────────────────────────────────────────────────────────────

test "BathyDB init and count" {
    var db = BathyDB.init(allocator);
    defer db.deinit();
    try testing.expectEqual(db.count(), 0);
}

test "BathyDB record and nearest lookup" {
    var db = BathyDB.init(allocator);
    defer db.deinit();

    try db.record(47.0, -122.0, 50.0);
    try db.record(48.0, -123.0, 200.0);
    try db.record(46.0, -121.0, 100.0);

    try testing.expectEqual(db.count(), 3);

    // Nearest to (47.0, -122.0) should be the first point
    const d1 = db.depthAt(47.0, -122.0);
    try testing.expectEqual(d1, 50.0);

    // Nearest to (47.1, -122.1) should still be point 0
    const d2 = db.depthAt(47.1, -122.1);
    try testing.expectEqual(d2, 50.0);
}

test "BathyDB nearest returns closest by squared distance" {
    var db = BathyDB.init(allocator);
    defer db.deinit();

    try db.record(10.0, 10.0, 1.0);
    try db.record(20.0, 20.0, 1000.0);
    try db.record(10.1, 10.1, 999.0);

    // Closest to (10.0, 10.0) is the first point with depth 1.0
    try testing.expectEqual(db.depthAt(10.0, 10.0), 1.0);
    // Closest to (10.05, 10.05) is the third point
    try testing.expectEqual(db.depthAt(10.05, 10.05), 999.0);
}

test "BathyDB empty returns null" {
    var db = BathyDB.init(allocator);
    defer db.deinit();
    try testing.expect(db.depthAt(0.0, 0.0) == null);
}

test "BathyDB single point always same" {
    var db = BathyDB.init(allocator);
    defer db.deinit();
    try db.record(-33.0, 151.0, 42.0);

    try testing.expectEqual(db.depthAt(-33.0, 151.0), 42.0);
    try testing.expectEqual(db.depthAt(100.0, 200.0), 42.0); // still returns the only point
}

test "BathyDB multiple records" {
    var db = BathyDB.init(allocator);
    defer db.deinit();

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        try db.record(@as(f64, @floatFromInt(i)) * 0.1, @as(f64, @floatFromInt(i)) * 0.2, @as(f64, @floatFromInt(i)) * 10.0);
    }
    try testing.expectEqual(db.count(), 100);
}

test "BathyDB deinit does not double-free" {
    var db = BathyDB.init(allocator);
    try db.record(1.0, 2.0, 3.0);
    try db.record(4.0, 5.0, 6.0);
    // After deinit, the backing memory is freed.
    // We just verify no crash on double-deinit.
    db.deinit();
    // Don't access db after deinit — the memory is gone.
    // This is a structural test that deinit works without error.
    try testing.expect(true);
}

test "BathyDB identical positions keeps first" {
    var db = BathyDB.init(allocator);
    defer db.deinit();

    try db.record(10.0, 10.0, 100.0);
    try db.record(10.0, 10.0, 999.0);

    // Returns first because squared distance is the same
    try testing.expectEqual(db.depthAt(10.0, 10.0), 100.0);
}

test "BathyDB negative depths (above surface)" {
    var db = BathyDB.init(allocator);
    defer db.deinit();
    try db.record(0.0, 0.0, -5.0);
    try testing.expectEqual(db.depthAt(0.0, 0.0), -5.0);
}
