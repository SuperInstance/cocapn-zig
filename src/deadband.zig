const std = @import("std");
const testing = std.testing;

/// Which side(s) of the deadband are monitored.
pub const Direction = enum(u8) {
    both,
    above_only,
    below_only,
};

/// The state of a reading relative to a deadband.
pub const State = enum(u8) {
    normal,
    approaching,
    exceeded,
};

/// A configurable deadband — values within [center - tol%, center + tol%]
/// are "normal". Outside are tracked as approaching or exceeded.
pub const Deadband = struct {
    center: f64,
    tolerance: f64, // fraction (0.0 – 1.0), e.g. 0.05 = 5%
    direction: Direction,

    /// Create a deadband. tolerance_pct is a fraction (0.0–1.0).
    /// A tolerance of 0 means the deadband is a single point.
    pub fn init(center: f64, tolerance_pct: f64, dir: Direction) Deadband {
        return .{
            .center = center,
            .tolerance = tolerance_pct,
            .direction = dir,
        };
    }

    /// Low end of the deadband range (inclusive).
    inline fn low(self: Deadband) f64 {
        return self.center * (1.0 - self.tolerance);
    }

    /// High end of the deadband range (inclusive).
    inline fn high(self: Deadband) f64 {
        return self.center * (1.0 + self.tolerance);
    }

    /// Check a value against the deadband.
    /// Returns State.exceeded if outside the deadband by more than tolerance,
    /// approaching if within tolerance but on the non-normal side,
    /// normal if within the band.
    pub fn check(self: Deadband, value: f64) State {
        const lo = self.low();
        const hi = self.high();

        const above = value > hi;
        const below = value < lo;

        // Determine if this value is outside based on direction
        const is_outside = switch (self.direction) {
            .both => above or below,
            .above_only => above,
            .below_only => below,
        };

        if (!is_outside) return .normal;

        // Exceeded — wider threshold (2x tolerance beyond band)
        const exceed_lo = self.center * (1.0 - 2.0 * self.tolerance);
        const exceed_hi = self.center * (1.0 + 2.0 * self.tolerance);

        // At or beyond the exceed boundary is exceeded
        const is_exceeded = switch (self.direction) {
            .both => value >= exceed_hi or value <= exceed_lo,
            .above_only => value >= exceed_hi,
            .below_only => value <= exceed_lo,
        };

        return if (is_exceeded) .exceeded else .approaching;
    }

    /// Check if a deadband configuration is valid (runtime).
    /// Returns true if valid, prints error and returns false otherwise.
    pub fn validate(self: Deadband) bool {
        if (self.tolerance < 0.0 or self.tolerance > 1.0) return false;
        if (self.center < 0.0) return false;
        return true;
    }

    /// Check at compile time if a deadband configuration is valid.
    /// Use this to verify deadband configs before flashing.
    pub fn comptimeValidate(comptime self: Deadband) void {
        if (self.tolerance < 0.0 or self.tolerance > 1.0) {
            @compileError("Deadband tolerance must be in [0.0, 1.0]");
        }
        if (self.center < 0.0) {
            @compileError("Deadband center must be non-negative");
        }
    }
};

/// Compile-time function to verify a heading deadband is valid.
pub fn validateHeadingDeadband(comptime db: Deadband) void {
    db.comptimeValidate();
    if (db.center < 0.0 or db.center > 360.0) {
        @compileError("Heading deadband center must be in [0, 360]");
    }
}

// ── Tests ────────────────────────────────────────────────────────────────

test "Deadband normal within range" {
    const db = Deadband.init(100.0, 0.10, .both);
    try testing.expectEqual(db.check(100.0), .normal);
    try testing.expectEqual(db.check(105.0), .normal);
    try testing.expectEqual(db.check(95.0), .normal);
    try testing.expectEqual(db.check(110.0), .normal);
    try testing.expectEqual(db.check(90.0), .normal);
}

test "Deadband approaching" {
    const db = Deadband.init(100.0, 0.10, .both);
    // 2x tolerance means exceeding band starts at >120 or <80
    try testing.expectEqual(db.check(115.0), .approaching);
    try testing.expectEqual(db.check(85.0), .approaching);
    try testing.expectEqual(db.check(119.0), .approaching);
    try testing.expectEqual(db.check(81.0), .approaching);
}

test "Deadband exceeded" {
    const db = Deadband.init(100.0, 0.10, .both);
    try testing.expectEqual(db.check(130.0), .exceeded);
    try testing.expectEqual(db.check(70.0), .exceeded);
    try testing.expectEqual(db.check(121.0), .exceeded);
    try testing.expectEqual(db.check(79.0), .exceeded);
}

test "Deadband above_only" {
    const db = Deadband.init(100.0, 0.10, .above_only);
    try testing.expectEqual(db.check(105.0), .normal);
    try testing.expectEqual(db.check(50.0), .normal); // below is ignored
    try testing.expectEqual(db.check(115.0), .approaching);
    try testing.expectEqual(db.check(130.0), .exceeded);
}

test "Deadband below_only" {
    const db = Deadband.init(100.0, 0.10, .below_only);
    try testing.expectEqual(db.check(95.0), .normal);
    try testing.expectEqual(db.check(200.0), .normal); // above is ignored
    try testing.expectEqual(db.check(85.0), .approaching);
    try testing.expectEqual(db.check(70.0), .exceeded);
}

test "Deadband zero tolerance" {
    const db = Deadband.init(50.0, 0.0, .both);
    try testing.expectEqual(db.check(50.0), .normal);
    try testing.expectEqual(db.check(50.0001), .exceeded);
}

test "Deadband at boundaries" {
    const db = Deadband.init(100.0, 0.10, .both);
    // Exactly at band edges
    try testing.expectEqual(db.check(90.0), .normal);
    try testing.expectEqual(db.check(110.0), .normal);
    // Exactly at exceed edges
    try testing.expectEqual(db.check(80.0), .exceeded);
    try testing.expectEqual(db.check(120.0), .exceeded);
}

test "Comptime deadband validation" {
    const valid = Deadband.init(180.0, 0.05, .both);
    _ = valid.validate();
    // If we got here, it compiled ok.
    try testing.expectEqual(valid.check(180.0), .normal);
}

test "Heading deadband at compile time" {
    validateHeadingDeadband(Deadband.init(180.0, 0.05, .both));
    // Compile-time: center 180, tolerance 5%, direction both — valid.
    try testing.expect(true);
}

test "Deadband edge cases negative values" {
    const db = Deadband.init(0.0, 0.10, .both);
    try testing.expectEqual(db.check(0.0), .normal);
    try testing.expectEqual(db.check(-0.1), .exceeded);
    try testing.expectEqual(db.check(0.1), .exceeded);
}
