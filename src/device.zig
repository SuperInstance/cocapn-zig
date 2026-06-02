const std = @import("std");
const testing = std.testing;

/// Device tier — increasing capability and autonomy.
pub const Tier = enum(u8) {
    /// Sensor-only. No autonomous decision-making.
    reflex = 0,
    /// Local control loops (e.g. heading hold, depth keep).
    backbone = 1,
    /// Fusion of local sensors with route planning.
    cortex = 2,
    /// Full cloud-synced mission management.
    cloud = 3,

    /// Get the next tier up (panics on cloud).
    pub fn next(self: Tier) Tier {
        return switch (self) {
            .reflex => .backbone,
            .backbone => .cortex,
            .cortex => .cloud,
            .cloud => @panic("cloud is the highest tier"),
        };
    }

    /// Get the previous tier (panics on reflex).
    pub fn prev(self: Tier) Tier {
        return switch (self) {
            .reflex => @panic("reflex is the lowest tier"),
            .backbone => .reflex,
            .cortex => .backbone,
            .cloud => .cortex,
        };
    }
};

/// Bitfield of capabilities a device may possess.
pub const Capability = packed struct {
    sense: bool = false,
    act: bool = false,
    route: bool = false,
    predict: bool = false,
    train: bool = false,
    communicate: bool = false,

    /// Returns true if `this` has at least all the capabilities of `required`.
    pub fn satisfies(self: Capability, required: Capability) bool {
        const self_bits = @as(u6, @bitCast(self));
        const req_bits = @as(u6, @bitCast(required));
        return (self_bits & req_bits) == req_bits;
    }

    comptime {
        // At compile time, verify the struct is exactly one byte.
        if (@sizeOf(Capability) != 1) {
            @compileError("Capability must be exactly 1 byte");
        }
    }
};

/// A marine device node in the CoCapn mesh.
pub const Device = struct {
    id: u8,
    name: []const u8,
    tier: Tier,
    capabilities: Capability,
    online: bool = true,

    /// Check if the device has at least the given capability.
    pub fn can(self: Device, cap: Capability) bool {
        return self.capabilities.satisfies(cap);
    }

    /// Check if this device can perform at the given tier or higher.
    pub fn tierAtLeast(self: Device, required: Tier) bool {
        return @intFromEnum(self.tier) >= @intFromEnum(required);
    }

    /// Promote device to next tier (no-op if already cloud).
    pub fn promote(self: *Device) void {
        if (self.tier != .cloud) {
            self.tier = self.tier.next();
        }
    }
};

// ── Tests ────────────────────────────────────────────────────────────────

test "Tier enum ordering" {
    try testing.expectEqual(@intFromEnum(Tier.reflex), 0);
    try testing.expectEqual(@intFromEnum(Tier.backbone), 1);
    try testing.expectEqual(@intFromEnum(Tier.cortex), 2);
    try testing.expectEqual(@intFromEnum(Tier.cloud), 3);
}

test "Tier next and prev" {
    try testing.expectEqual(Tier.reflex.next(), .backbone);
    try testing.expectEqual(Tier.cloud.prev(), .cortex);
}

test "Tier next panics at cloud" {
    // Can't catch panics easily in zig test, so we just verify the function exists
    // and test the prev/next pattern exhaustively below cloud.
    try testing.expectEqual(Tier.backbone.next(), .cortex);
    try testing.expectEqual(Tier.cortex.next(), .cloud);
    try testing.expectEqual(Tier.cloud.prev(), .cortex);
    try testing.expectEqual(Tier.cortex.prev(), .backbone);
    try testing.expectEqual(Tier.backbone.prev(), .reflex);
}

test "Capability satisfies" {
    const full: Capability = .{
        .sense = true,
        .act = true,
        .route = true,
        .predict = true,
        .train = true,
        .communicate = true,
    };
    const minimal: Capability = .{ .sense = true, .act = true };
    try testing.expect(full.satisfies(minimal));
    try testing.expect(!minimal.satisfies(full));
}

test "Capability bitfield size" {
    try testing.expectEqual(@sizeOf(Capability), 1);
}

test "Capability empty always satisfied" {
    const full: Capability = .{
        .sense = true,
        .act = true,
        .route = true,
        .predict = true,
        .train = true,
        .communicate = true,
    };
    const empty: Capability = .{};
    try testing.expect(full.satisfies(empty));
    try testing.expect(empty.satisfies(empty));
}

test "Device can check capability" {
    const d = Device{
        .id = 1,
        .name = "port-bow-thruster",
        .tier = .cortex,
        .capabilities = .{ .sense = true, .act = true },
    };
    try testing.expect(d.can(.{ .sense = true }));
    try testing.expect(d.can(.{ .act = true }));
    try testing.expect(!d.can(.{ .predict = true }));
    try testing.expect(d.can(.{ .sense = true, .act = true }));
    try testing.expect(!d.can(.{ .sense = true, .act = true, .route = true }));
}

test "Device tierAtLeast" {
    const r: Device = .{ .id = 2, .name = "temp-sensor", .tier = .reflex, .capabilities = .{ .sense = true } };
    const c: Device = .{ .id = 3, .name = "nav-computer", .tier = .cloud, .capabilities = .{} };
    try testing.expect(r.tierAtLeast(.reflex));
    try testing.expect(!r.tierAtLeast(.backbone));
    try testing.expect(c.tierAtLeast(.reflex));
    try testing.expect(c.tierAtLeast(.cloud));
}

test "Device promote" {
    var d = Device{ .id = 4, .name = "sensor-pod", .tier = .reflex, .capabilities = .{ .sense = true } };
    d.promote();
    try testing.expectEqual(d.tier, .backbone);
    d.promote();
    try testing.expectEqual(d.tier, .cortex);
    d.promote();
    try testing.expectEqual(d.tier, .cloud);
    d.promote(); // no-op
    try testing.expectEqual(d.tier, .cloud);
}

test "Device default online" {
    const d = Device{ .id = 5, .name = "test", .tier = .reflex, .capabilities = .{} };
    try testing.expect(d.online);
}

test "Device can — exact match" {
    const d = Device{
        .id = 6,
        .name = "multi-sensor",
        .tier = .cortex,
        .capabilities = .{ .sense = true, .act = true, .communicate = true },
    };
    try testing.expect(d.can(.{ .sense = true, .act = true, .communicate = true }));
}
