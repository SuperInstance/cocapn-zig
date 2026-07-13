# CoCapn-Zig

**Comptime safety for bare metal marine autopilots.**

CoCapn is a marine control system for autonomous vessels. This is the Zig core library providing deadband validation, PID heading-hold autopilot, device management, NMEA parsing, bathymetry lookup, and tier-based escalation.

## Why Zig?

### Comptime means you can verify deadband configs at compile time

```zig
// This compiles fine — heading 180° with 5% tolerance
const hdg_db = Deadband.init(180.0, 0.05, .both);
hdg_db.comptimeValidate();

// This is caught at COMPILE TIME — heading outside [0, 360]
const bad_db = Deadband.init(999.0, 0.05, .both);
validateHeadingDeadband(bad_db);
// → error: Heading deadband center must be in [0, 360]
```

The Zig compiler catches impossible values *before the binary is flashed to the vessel*. No runtime checks needed. No defensive code. Just correct by construction.

### No hidden allocations

Every allocation requires an explicit allocator parameter:

```zig
var db = BathyDB.init(allocator);  // ← you choose the allocator
```

No hidden mallocs. No garbage collector. No surprises on bare metal.

### Cross-compile to any target

```bash
# Build for an ARM Cortex-M microcontroller
zig build -Dtarget=arm-freestanding-eabihf

# Build for a RISC-V autopilot board
zig build -Dtarget=riscv64-freestanding

# Native x86-64 development
zig build
```

One toolchain. No cross-compiler toolchain hell. `zig build` just works.

### No hidden control flow

Zig has no exceptions, no operator overloading, no hidden allocations, no implicit control flow. Every function call is explicit. Every allocation is visible. When the boat is 50 miles offshore and the CPU is a single-core ARM chip, this predictability matters.

### Polyglot by design

```zig
// Import C libraries directly
const c = @cImport({
    @cInclude("libcocapn_c.h");
});

// Embed the Forth interpreter at compile time
const forth_rom = @embedFile("cocapn_forth.4th");

// Include binary assets like bootloader images
const bootloader = @embedFile("bootloader.bin");
```

`@cImport` lets you call existing C code without wrappers. `@embedFile` includes binary assets at compile time with zero runtime overhead. Zig doesn't replace your existing codebase — it integrates with it.

## What Zig teaches

### Explicit allocation

In Zig, you pass the allocator *in*:

```zig
pub const BathyDB = struct {
    points: std.ArrayList(BathyPoint),
    pub fn init(alloc: std.mem.Allocator) BathyDB { ... }
};
```

No global allocators. No hidden `new`. You always know who owns what.

### Comptime evaluation

Deadband config verified *before the boat leaves the dock*:

```zig
pub fn validateHeadingDeadband(comptime db: Deadband) void {
    db.comptimeValidate();
    if (db.center < 0.0 or db.center > 360.0) {
        @compileError("Heading deadband center must be in [0, 360]");
    }
}
```

The Zig compiler becomes a domain-specific validation tool for marine parameters:
- Heading ranges: 0–360°
- Speed limits: 0–50 knots
- Depth ranges: 0–12000m
- Rudder limits: -45° to +45°
- All verified at compile time

### No hidden control flow

What you see is what you get. No exceptions unwinding your stack. No RAII destructors firing at unexpected times. No operator overloading making `a + b` do something surprising. Just explicit, predictable code.

## Architecture

```
CoCapn Zig Core
├── device.zig      — Device tiers (reflex → cloud), capability bitfields
├── deadband.zig    — Configurable deadband with compile-time validation
├── autopilot.zig   — PID heading-hold controller with anti-windup
├── escalation.zig  — Tier-based fault escalation chain with cooldown
├── nmea.zig        — NMEA 0183 sentence parsing (GGA), checksum verification
├── bathy.zig       — In-memory bathymetry sounding DB
└── root.zig        — Public API root
```

### Status & known limitations

- CI is now a real workflow (`zig fmt --check`, `zig build`, `zig build test`, and cross-compiles for ARM/RISC-V).
- NMEA 0183 parsing accepts sentences terminated with `\r`, `\n`, or `\r\n`.
- `escalation.zig` cooldown uses the host monotonic clock (`std.time.Instant`). Pure freestanding/bare-metal targets will need to wire in their own clock source before using tier escalation.

### Tests

66 tests covering all modules. Run with:

```bash
zig build test
```

Or test individual modules:

```bash
zig test src/device.zig
zig test src/deadband.zig
zig test src/autopilot.zig
zig test src/escalation.zig
zig test src/nmea.zig
zig test src/bathy.zig
```

## Build

```bash
# Library
zig build

# Tests
zig build test

# Cross-compile for RISC-V
zig build -Dtarget=riscv64-freestanding

# Cross-compile for ARM bare metal
zig build -Dtarget=arm-freestanding-eabihf

# Optimised release
zig build -Doptimize=ReleaseSafe
```

## Usage

```zig
const cocapn = @import("cocapn");

// Create a device
var thruster = cocapn.device.Device{
    .id = 1,
    .name = "port-thruster",
    .tier = .backbone,
    .capabilities = .{ .sense = true, .act = true },
};

// Validate a heading deadband at COMPILE TIME
const hdg_db = cocapn.deadband.Deadband.init(180.0, 0.05, .both);
cocapn.deadband.validateHeadingDeadband(hdg_db);

// Start a PID autopilot
var pid = cocapn.autopilot.PID.init(1.5, 0.1, 0.05, 30.0, 1.0);

// Parse NMEA from GPS
const gga = try cocapn.nmea.parseGga("$GPGGA,...*47");
std.debug.print("Position: {d}, {d}\n", .{ gga.lat, gga.lon });

// Record bathymetry
var bathy = cocapn.bathy.BathyDB.init(allocator);
defer bathy.deinit();
try bathy.record(48.0, -123.0, 200.0);
```

## License

MIT — use it on your boat, your submarine, or your underwater drone.
