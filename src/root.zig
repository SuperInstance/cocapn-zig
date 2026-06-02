pub const device = @import("device.zig");
pub const deadband = @import("deadband.zig");
pub const autopilot = @import("autopilot.zig");
pub const escalation = @import("escalation.zig");
pub const nmea = @import("nmea.zig");
pub const bathy = @import("bathy.zig");

test {
    @import("std").testing.refAllDecls(@This());
    _ = @import("device.zig");
    _ = @import("deadband.zig");
    _ = @import("autopilot.zig");
    _ = @import("escalation.zig");
    _ = @import("nmea.zig");
    _ = @import("bathy.zig");
}
