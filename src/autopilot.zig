const std = @import("std");
const testing = std.testing;

/// Result from a PID autopilot update.
pub const PIDResult = struct {
    /// Rudder command in degrees (-max_rudder .. +max_rudder).
    rudder_command: f64,
    /// Signed heading error in degrees.
    heading_error: f64,
    /// True when the heading error is within the configured tolerance.
    on_course: bool,
};

/// A discrete-time PID controller for heading-hold autopilot.
///
/// Uses the standard form:
/// output = Kp * e + Ki * ∫e dt + Kd * de/dt
/// with integral windup protection via clamping.
pub const PID = struct {
    kp: f64,
    ki: f64,
    kd: f64,
    integral: f64 = 0,
    last_error: f64 = 0,
    max_rudder: f64,
    heading_tol: f64,

    /// Create a new PID controller.
    /// `max_rudder`: maximum absolute rudder angle in degrees.
    /// `tol`: heading tolerance in degrees — within this the craft is "on course".
    pub fn init(kp: f64, ki: f64, kd: f64, max_rudder: f64, tol: f64) PID {
        return .{
            .kp = kp,
            .ki = ki,
            .kd = kd,
            .max_rudder = max_rudder,
            .heading_tol = tol,
        };
    }

    /// Update the PID loop with a new measurement.
    /// `current`: current heading in degrees.
    /// `target`: desired heading in degrees.
    /// `dt`: time step in seconds.
    pub fn update(self: *PID, current: f64, target: f64, dt: f64) PIDResult {
        // Normalize heading error to [-180, 180]
        var raw_error = target - current;
        while (raw_error > 180.0) raw_error -= 360.0;
        while (raw_error < -180.0) raw_error += 360.0;

        const err_val = raw_error;

        // Integral term with anti-windup (skip when Ki is zero to avoid
        // division by zero and meaningless integral growth).
        if (self.ki != 0.0) {
            self.integral += err_val * dt;
            const max_integral = self.max_rudder / self.ki;
            const min_integral = -self.max_rudder / self.ki;
            if (self.integral > max_integral) self.integral = max_integral;
            if (self.integral < min_integral) self.integral = min_integral;
        } else {
            self.integral = 0;
        }

        // Derivative term
        const derivative = if (dt > 0.0) (err_val - self.last_error) / dt else 0.0;
        self.last_error = err_val;

        // PID output
        var output = self.kp * err_val + self.ki * self.integral + self.kd * derivative;

        // Clamp to rudder limits
        if (output > self.max_rudder) output = self.max_rudder;
        if (output < -self.max_rudder) output = -self.max_rudder;

        return .{
            .rudder_command = output,
            .heading_error = err_val,
            .on_course = @abs(err_val) <= self.heading_tol,
        };
    }

    /// Reset the integral accumulator and last error.
    pub fn reset(self: *PID) void {
        self.integral = 0;
        self.last_error = 0;
    }
};

// ── Tests ────────────────────────────────────────────────────────────────

test "PID on course zero error" {
    var pid = PID.init(1.0, 0.1, 0.05, 30.0, 1.0);
    const result = pid.update(180.0, 180.0, 0.1);
    try testing.expect(result.on_course);
    try testing.expectEqual(result.heading_error, 0.0);
    try testing.expectEqual(result.rudder_command, 0.0);
}

test "PID proportional response" {
    var pid = PID.init(1.0, 0.0, 0.0, 30.0, 1.0);
    const result = pid.update(170.0, 180.0, 0.1);
    try testing.expectApproxEqAbs(result.rudder_command, 10.0, 0.001);
    try testing.expectApproxEqAbs(result.heading_error, 10.0, 0.001);
    try testing.expect(!result.on_course);
}

test "PID negative error" {
    var pid = PID.init(1.0, 0.0, 0.0, 30.0, 1.0);
    const result = pid.update(190.0, 180.0, 0.1);
    try testing.expectApproxEqAbs(result.rudder_command, -10.0, 0.001);
    try testing.expectApproxEqAbs(result.heading_error, -10.0, 0.001);
}

test "PID heading wrap 350->10" {
    var pid = PID.init(1.0, 0.0, 0.0, 30.0, 1.0);
    const result = pid.update(350.0, 10.0, 0.1);
    // Shortest path: 10 - 350 = -340 → +20°
    try testing.expectApproxEqAbs(result.heading_error, 20.0, 0.001);
    try testing.expectApproxEqAbs(result.rudder_command, 20.0, 0.001);
}

test "PID heading wrap 10->350" {
    var pid = PID.init(1.0, 0.0, 0.0, 30.0, 1.0);
    const result = pid.update(10.0, 350.0, 0.1);
    // Shortest path: 350 - 10 = 340 → -20°
    try testing.expectApproxEqAbs(result.heading_error, -20.0, 0.001);
    try testing.expectApproxEqAbs(result.rudder_command, -20.0, 0.001);
}

test "PID rudder clamping" {
    var pid = PID.init(10.0, 0.0, 0.0, 30.0, 1.0);
    const result = pid.update(0.0, 180.0, 0.1);
    // error = 180, P term = 1800, clamped to max_rudder
    try testing.expectApproxEqAbs(result.rudder_command, 30.0, 0.001);
}

test "PID integral builds up" {
    var pid = PID.init(1.0, 1.0, 0.0, 30.0, 1.0);
    // Persistent 5° error should accumulate integral
    var result = pid.update(175.0, 180.0, 1.0);
    try testing.expectApproxEqAbs(result.rudder_command, 5.0 + 5.0, 0.001); // P + I
    result = pid.update(175.0, 180.0, 1.0);
    try testing.expectApproxEqAbs(result.rudder_command, 5.0 + 10.0, 0.001);
}

test "PID reset clears integrator" {
    var pid = PID.init(1.0, 1.0, 0.0, 30.0, 1.0);
    _ = pid.update(175.0, 180.0, 1.0);
    _ = pid.update(175.0, 180.0, 1.0);
    pid.reset();
    const result = pid.update(180.0, 180.0, 1.0);
    // After reset, integral should be 0, error is 0
    try testing.expectApproxEqAbs(result.rudder_command, 0.0, 0.001);
    try testing.expect(result.on_course);
}

test "PID ki zero avoids division by zero" {
    var pid = PID.init(1.0, 0.0, 0.0, 30.0, 1.0);
    const result = pid.update(175.0, 180.0, 1.0);
    // With Ki=0 there is no integral term and no FPE from max_integral.
    try testing.expectApproxEqAbs(result.rudder_command, 5.0, 0.001);
    try testing.expectApproxEqAbs(result.heading_error, 5.0, 0.001);
    // Integral must remain clamped at zero.
    try testing.expectApproxEqAbs(pid.integral, 0.0, 0.001);
}

test "PID integral anti-windup" {
    var pid = PID.init(1.0, 100.0, 0.0, 30.0, 1.0);
    // Large sustained error will integrate up, but should clamp
    const result = pid.update(0.0, 180.0, 1.0);
    // integral = 180 * 1 = 180, but max_integral = 30/100 = 0.3
    // P term: 180*1 = 180 (clamped to 30), I term: 100 * 0.3 = 30
    // Total clamped to 30
    try testing.expectApproxEqAbs(result.rudder_command, 30.0, 0.001);
}

test "PID derivative action with clamping" {
    var pid = PID.init(0.0, 0.0, 1.0, 30.0, 1.0);
    // Change from 180 to 175 = error 5
    // derivative = (5 - 0) / 0.1 = 50, clamped to max_rudder=30
    _ = pid.update(180.0, 180.0, 0.1);
    const result = pid.update(175.0, 180.0, 0.1);
    try testing.expectApproxEqAbs(result.rudder_command, 30.0, 0.001);
    try testing.expectApproxEqAbs(result.heading_error, 5.0, 0.001);
    try testing.expect(!result.on_course);
}

test "PID on_course detection" {
    var pid = PID.init(1.0, 0.0, 0.0, 30.0, 5.0);
    try testing.expect(pid.update(178.0, 180.0, 0.1).on_course);
    try testing.expect(pid.update(175.0, 180.0, 0.1).on_course);
    try testing.expect(!pid.update(174.0, 180.0, 0.1).on_course);
}
