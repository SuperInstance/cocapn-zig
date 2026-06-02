const std = @import("std");
const testing = std.testing;

/// Parsed GGA (Global Positioning System Fix Data) sentence.
pub const GgaData = struct {
    lat: f64,
    lon: f64,
    fix_quality: u8,
    satellites: u8,
    hdop: f64,
    altitude: f64,

    /// Human-readable fix quality description.
    pub fn fixDescription(self: GgaData) []const u8 {
        return switch (self.fix_quality) {
            0 => "invalid",
            1 => "GPS fix (SPS)",
            2 => "DGPS fix",
            3 => "PPS fix",
            4 => "RTK fixed",
            5 => "RTK float",
            6 => "estimated",
            7 => "manual input mode",
            8 => "simulation mode",
            else => "unknown",
        };
    }
};

/// Verify the NMEA 0183 checksum of a sentence (without the leading '$').
/// The sentence must include the '*' and 2-digit hex checksum at the end.
pub fn verifyChecksum(sentence: []const u8) bool {
    // Find the asterisk separating data from checksum
    const asterisk = std.mem.lastIndexOfScalar(u8, sentence, '*') orelse return false;
    if (asterisk + 3 != sentence.len) return false;

    // Extract the checksum hex digits
    const checksum_hex = sentence[asterisk + 1 ..];
    const expected = std.fmt.parseInt(u8, checksum_hex, 16) catch return false;

    // XOR all bytes between start (skip '$') and the asterisk
    const data = if (sentence[0] == '$') sentence[1..asterisk] else sentence[0..asterisk];
    var computed: u8 = 0;
    for (data) |c| {
        computed ^= c;
    }

    return computed == expected;
}

/// Parse a GGA sentence (with or without leading '$').
/// Returns error.InvalidChecksum, error.InvalidSentence, or error.Overflow on failure.
pub fn parseGga(sentence: []const u8) !GgaData {
    // Strip leading '$' if present
    const s = if (sentence.len > 0 and sentence[0] == '$') sentence[1..] else sentence;

    if (!verifyChecksum(sentence))
        return error.InvalidChecksum;

    // Split on commas
    var it = std.mem.splitScalar(u8, s, ',');
    // Field 0: talker + sentence type (should be "GPGGA" or "GNGGA" etc.)
    const talker_id = it.next() orelse return error.InvalidSentence;
    if (talker_id.len < 5 or !std.mem.eql(u8, talker_id[talker_id.len - 3 ..], "GGA"))
        return error.InvalidSentence;

    // Field 1: UTC time (skip for now)
    _ = it.next() orelse return error.InvalidSentence;

    // Field 2: Latitude (DDMM.MMMM)
    const lat_raw = it.next() orelse return error.InvalidSentence;
    // Field 3: N/S
    const lat_dir = it.next() orelse return error.InvalidSentence;
    // Field 4: Longitude (DDDMM.MMMM)
    const lon_raw = it.next() orelse return error.InvalidSentence;
    // Field 5: E/W
    const lon_dir = it.next() orelse return error.InvalidSentence;
    // Field 6: Fix quality
    const fix_q_str = it.next() orelse return error.InvalidSentence;
    // Field 7: Satellites
    const sats_str = it.next() orelse return error.InvalidSentence;
    // Field 8: HDOP
    const hdop_str = it.next() orelse return error.InvalidSentence;
    // Field 9: Altitude
    const alt_str = it.next() orelse return error.InvalidSentence;

    const lat = try parseCoordinate(lat_raw, true);
    const lat_signed = if (lat_dir.len > 0 and lat_dir[0] == 'S') -lat else lat;

    const lon = try parseCoordinate(lon_raw, false);
    const lon_signed = if (lon_dir.len > 0 and lon_dir[0] == 'W') -lon else lon;

    const fix_quality = try std.fmt.parseInt(u8, fix_q_str, 10);
    const satellites = try std.fmt.parseInt(u8, sats_str, 10);
    const hdop = try std.fmt.parseFloat(f64, hdop_str);
    const altitude = try std.fmt.parseFloat(f64, alt_str);

    return GgaData{
        .lat = lat_signed,
        .lon = lon_signed,
        .fix_quality = fix_quality,
        .satellites = satellites,
        .hdop = hdop,
        .altitude = altitude,
    };
}

/// Parse an NMEA coordinate string to decimal degrees.
/// `is_latitude`: true for latitude (DDMM.MMMM), false for longitude (DDDMM.MMMM).
pub fn parseCoordinate(raw: []const u8, is_latitude: bool) !f64 {
    if (raw.len == 0) return error.InvalidCoordinate;

    const dot = std.mem.indexOfScalar(u8, raw, '.') orelse return error.InvalidCoordinate;
    const int_part_len = dot;
    const degrees_len: usize = if (is_latitude) 2 else 3;

    if (int_part_len < degrees_len) return error.InvalidCoordinate;

    const degrees_str = raw[0..degrees_len];
    const minutes_str = raw[degrees_len..];

    const degrees = try std.fmt.parseFloat(f64, degrees_str);
    const minutes = try std.fmt.parseFloat(f64, minutes_str);

    return degrees + minutes / 60.0;
}

// ── Tests ────────────────────────────────────────────────────────────────

test "verifyChecksum valid" {
    const sentence = "$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47";
    try testing.expect(verifyChecksum(sentence));
}

test "verifyChecksum tampered" {
    const sentence = "$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*FF";
    try testing.expect(!verifyChecksum(sentence));
}

test "verifyChecksum no asterisk" {
    try testing.expect(!verifyChecksum("GPGGA,123519"));
}

test "verifyChecksum bad hex" {
    try testing.expect(!verifyChecksum("$GPGGA,123519*ZZ"));
}

test "parseCoordinate latitude" {
    const lat = try parseCoordinate("4807.038", true);
    // 48° 07.038' = 48 + 7.038/60 = 48.1173
    try testing.expectApproxEqAbs(lat, 48.1173, 0.0001);
}

test "parseCoordinate longitude" {
    const lon = try parseCoordinate("01131.000", false);
    // 011° 31.000' = 11 + 31/60 = 11.5167
    try testing.expectApproxEqAbs(lon, 11.5167, 0.0001);
}

test "parseGga valid sentence" {
    const data = try parseGga("$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47");
    try testing.expectApproxEqAbs(data.lat, 48.1173, 0.0001);
    try testing.expectApproxEqAbs(data.lon, 11.5167, 0.0001);
    try testing.expectEqual(data.fix_quality, 1);
    try testing.expectEqual(data.satellites, 8);
    try testing.expectApproxEqAbs(data.hdop, 0.9, 0.01);
    try testing.expectApproxEqAbs(data.altitude, 545.4, 0.01);
}

test "parseGga checksum error" {
    const result = parseGga("$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*FF");
    try testing.expectError(error.InvalidChecksum, result);
}

test "parseGga southern hemisphere" {
    const data = try parseGga("$GPGGA,123519,3343.000,S,15117.000,E,1,08,0.9,10.0,M,,,*19");
    // 33° 43.000' S = -33.7167
    try testing.expectApproxEqAbs(data.lat, -33.7167, 0.0001);
    try testing.expectApproxEqAbs(data.lon, 151.2833, 0.0001);
}

test "parseGga western hemisphere" {
    const data = try parseGga("$GPGGA,123519,2545.000,N,08015.000,W,1,05,1.5,2.0,M,,,*2B");
    try testing.expectApproxEqAbs(data.lat, 25.75, 0.0001);
    try testing.expectApproxEqAbs(data.lon, -80.25, 0.0001);
}

test "GgaData fixDescription" {
    var gga = GgaData{ .lat = 0, .lon = 0, .fix_quality = 1, .satellites = 0, .hdop = 0, .altitude = 0 };
    try testing.expectEqualStrings(gga.fixDescription(), "GPS fix (SPS)");
    gga.fix_quality = 4;
    try testing.expectEqualStrings(gga.fixDescription(), "RTK fixed");
    gga.fix_quality = 99;
    try testing.expectEqualStrings(gga.fixDescription(), "unknown");
}

test "parseCoordinate empty" {
    try testing.expectError(error.InvalidCoordinate, parseCoordinate("", true));
}

test "parseCoordinate no decimal" {
    try testing.expectError(error.InvalidCoordinate, parseCoordinate("4807", true));
}
