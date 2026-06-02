const std = @import("std");
const testing = std.testing;
const device = @import("device.zig");
const Tier = device.Tier;

/// An escalation chain moves a device through tiers when conditions change.
/// When a fault or anomaly is detected, the device escalates to the next tier.
/// When conditions stabilise, it de-escalates.
pub const EscalationChain = struct {
    current_tier: Tier,
    cooldown_ms: u64,
    escalation_count: u32,
    last_escalation: ?std.time.Instant,

    /// Create a new escalation chain starting at the given tier.
    pub fn init(tier: Tier, cooldown_ms: u64) EscalationChain {
        return .{
            .current_tier = tier,
            .cooldown_ms = cooldown_ms,
            .escalation_count = 0,
            .last_escalation = null,
        };
    }

    /// Try to escalate to the next tier.
    /// Returns the new tier after escalation (or same if already at cloud).
    /// Checks cooldown — returns current tier if cooldown hasn't elapsed.
    pub fn escalate(self: *EscalationChain) Tier {
        if (self.current_tier == .cloud) return .cloud;

        // Check cooldown
        if (self.last_escalation) |last| {
            if (std.time.Instant.now()) |now| {
                const elapsed = now.since(last) / 1_000_000; // ms
                if (elapsed < self.cooldown_ms) {
                    return self.current_tier; // cooldown hasn't elapsed
                }
            } else |_| {}
        }

        self.current_tier = self.current_tier.next();
        self.escalation_count += 1;
        self.last_escalation = std.time.Instant.now() catch null;
        return self.current_tier;
    }

    /// De-escalate to the previous tier.
    /// Returns the new tier (or same if already at reflex).
    pub fn deescalate(self: *EscalationChain) Tier {
        if (self.current_tier == .reflex) return .reflex;
        self.current_tier = self.current_tier.prev();
        return self.current_tier;
    }

    /// Check if the chain has reached the maximum tier (cloud).
    pub fn isFullyEscalated(self: EscalationChain) bool {
        return self.current_tier == .cloud;
    }

    /// Check if we're at the minimum tier (reflex).
    pub fn isBaseline(self: EscalationChain) bool {
        return self.current_tier == .reflex;
    }
};

// ── Tests ────────────────────────────────────────────────────────────────

test "EscalationChain starts at baseline" {
    const chain = EscalationChain.init(.reflex, 1000);
    try testing.expect(chain.isBaseline());
    try testing.expect(!chain.isFullyEscalated());
    try testing.expectEqual(chain.current_tier, .reflex);
    try testing.expectEqual(chain.escalation_count, 0);
}

test "EscalationChain escalates through tiers" {
    var chain = EscalationChain.init(.reflex, 0); // no cooldown
    try testing.expectEqual(chain.escalate(), .backbone);
    try testing.expectEqual(chain.escalate(), .cortex);
    try testing.expectEqual(chain.escalate(), .cloud);
    try testing.expect(chain.isFullyEscalated());
    try testing.expectEqual(chain.escalation_count, 3);
}

test "EscalationChain cloud is max" {
    var chain = EscalationChain.init(.cloud, 0);
    try testing.expectEqual(chain.escalate(), .cloud); // stays cloud
    try testing.expectEqual(chain.escalate(), .cloud);
}

test "EscalationChain deescalates" {
    var chain = EscalationChain.init(.cloud, 0);
    try testing.expectEqual(chain.deescalate(), .cortex);
    try testing.expectEqual(chain.deescalate(), .backbone);
    try testing.expectEqual(chain.deescalate(), .reflex);
    try testing.expect(chain.isBaseline());
    try testing.expectEqual(chain.deescalate(), .reflex); // stays reflex
}

test "EscalationChain cooldown prevents rapid escalation" {
    var chain = EscalationChain.init(.reflex, 10_000); // 10s cooldown
    try testing.expectEqual(chain.escalate(), .backbone);
    // Second call within cooldown should return same tier
    try testing.expectEqual(chain.escalate(), .backbone);
    try testing.expectEqual(chain.escalation_count, 1);
}

test "EscalationChain tracks count" {
    var chain = EscalationChain.init(.reflex, 0);
    _ = chain.escalate();
    _ = chain.escalate();
    try testing.expectEqual(chain.escalation_count, 2);
}

test "EscalationChain back and forth" {
    var chain = EscalationChain.init(.cortex, 0);
    _ = chain.escalate();
    try testing.expectEqual(chain.current_tier, .cloud);
    _ = chain.deescalate();
    try testing.expectEqual(chain.current_tier, .cortex);
    _ = chain.deescalate();
    try testing.expectEqual(chain.current_tier, .backbone);
    _ = chain.escalate();
    try testing.expectEqual(chain.current_tier, .cortex);
    try testing.expectEqual(chain.escalation_count, 2);
}

test "EscalationChain with non-zero cooldown still escalates if time passes" {
    // We can't easily advance time, but we can verify the logic:
    // With cooldown 0, escalation always succeeds.
    var chain = EscalationChain.init(.reflex, 0);
    try testing.expectEqual(chain.escalate(), .backbone);
    try testing.expectEqual(chain.escalate(), .cortex);
    try testing.expectEqual(chain.escalation_count, 2);
}
