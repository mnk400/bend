// Main zig file that contains CLI and execution related configuration
// Created by Manik on March 26th 2026

const std = @import("std");
const Sensor = @import("sensor.zig").Sensor;
const build_options = @import("build_options");

const Io = std.Io;
const File = std.Io.File;

const version = build_options.version;

const exit_ok = 0;
const exit_sensor_error = 1;
const exit_usage = 2;
const exit_timeout = 3;

const Mode = enum { oneshot, watch, wait_until };
const Format = enum { plain };
const Direction = enum { above, below, auto };
const Threshold = struct {
    value: u16,
    direction: Direction,
};

const Args = struct {
    mode: Mode = .oneshot,
    format: Format = .plain,
    interval_ms: u64 = 500,
    threshold: ?Threshold = null,
    timeout_ms: ?u64 = null,
    delta: bool = false,
    help: bool = false,
    show_version: bool = false,
};

fn parseArgs(argv: std.process.Args) error{ MissingArgValue, InvalidArgValue, UnknownArg, ConflictingMode, TimeoutRequiresWaitUntil, DeltaRequiresWatch }!Args {
    var iter = argv.iterate();
    defer iter.deinit();
    _ = iter.skip(); // skip argv[0]

    var args = Args{};
    var has_watch = false;
    var has_wait_until = false;
    var has_timeout = false;
    var has_delta = false;

    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            args.help = true;
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            args.show_version = true;
        } else if (std.mem.eql(u8, arg, "--watch") or std.mem.eql(u8, arg, "-w")) {
            args.mode = .watch;
            has_watch = true;
        } else if (std.mem.eql(u8, arg, "--interval") or std.mem.eql(u8, arg, "-i")) {
            const val = iter.next() orelse return error.MissingArgValue;
            args.interval_ms = parseSecsToMs(val) catch return error.InvalidArgValue;
        } else if (std.mem.eql(u8, arg, "--wait-until")) {
            args.mode = .wait_until;
            has_wait_until = true;
            const val = iter.next() orelse return error.MissingArgValue;
            args.threshold = parseThreshold(val) orelse return error.InvalidArgValue;
        } else if (std.mem.eql(u8, arg, "--timeout")) {
            has_timeout = true;
            const val = iter.next() orelse return error.MissingArgValue;
            args.timeout_ms = parseSecsToMs(val) catch return error.InvalidArgValue;
        } else if (std.mem.eql(u8, arg, "--delta") or std.mem.eql(u8, arg, "-d")) {
            args.delta = true;
            has_delta = true;
        } else if (std.mem.eql(u8, arg, "--")) {
            break;
        } else {
            return error.UnknownArg;
        }
    }

    if (has_watch and has_wait_until) return error.ConflictingMode;
    if (has_timeout and !has_wait_until) return error.TimeoutRequiresWaitUntil;
    if (has_delta and !has_watch) return error.DeltaRequiresWatch;

    return args;
}

fn parseSecsToMs(val: []const u8) error{InvalidArgValue}!u64 {
    const secs = std.fmt.parseFloat(f64, val) catch return error.InvalidArgValue;
    // Reject negative / NaN / inf / out-of-range before @intFromFloat, which is
    // illegal behavior (panic in safe builds) for values that don't fit the target.
    // Bound to i64 so downstream Duration/Timestamp math (which is signed) is safe.
    if (!std.math.isFinite(secs) or secs < 0) return error.InvalidArgValue;
    const ms = secs * 1000.0;
    if (ms > @as(f64, @floatFromInt(std.math.maxInt(i64)))) return error.InvalidArgValue;
    return @intFromFloat(ms);
}

fn parseThreshold(s: []const u8) ?Threshold {
    if (s.len == 0) return null;

    if (s[s.len - 1] == '+') {
        const val = std.fmt.parseInt(u16, s[0 .. s.len - 1], 10) catch return null;
        return .{ .value = val, .direction = .above };
    } else if (s[s.len - 1] == '-') {
        const val = std.fmt.parseInt(u16, s[0 .. s.len - 1], 10) catch return null;
        return .{ .value = val, .direction = .below };
    } else {
        const val = std.fmt.parseInt(u16, s, 10) catch return null;
        return .{ .value = val, .direction = .auto };
    }
}

fn writeTo(file: File, io: Io, comptime fmt: []const u8, fmtargs: anytype) bool {
    var buf: [256]u8 = undefined;
    const slice = std.fmt.bufPrint(&buf, fmt, fmtargs) catch return true;
    file.writeStreamingAll(io, slice) catch return false;
    return true;
}

fn out(io: Io, comptime fmt: []const u8, fmtargs: anytype) bool {
    return writeTo(File.stdout(), io, fmt, fmtargs);
}

fn err(io: Io, comptime fmt: []const u8, fmtargs: anytype) void {
    _ = writeTo(File.stderr(), io, fmt, fmtargs);
}

// Sleep helper. interval/timeout values are bounded to i64 in parseSecsToMs,
// so the cast to the signed Duration is always safe.
fn sleepMs(io: Io, ms: u64) void {
    io.sleep(Io.Duration.fromMilliseconds(@intCast(ms)), .awake) catch {};
}

fn printUsage(io: Io) void {
    const usage =
        \\Usage: bend [options]
        \\
        \\Read the MacBook lid angle sensor.
        \\
        \\Modes:
        \\  (default)              Print angle once and exit
        \\  -w, --watch            Print angle continuously, one line per reading
        \\  --wait-until <N[+/-]>  Block until angle reaches threshold, then exit
        \\                         e.g. 120 (auto-detect direction from current angle)
        \\                         140+ (force wait for >=140), 30- (force wait for <=30)
        \\
        \\Options:
        \\  -d, --delta            Show change since last reading (use with --watch)
        \\  -i, --interval <secs>  Interval between readings (default: 0.5)
        \\  --timeout <secs>       Timeout for --wait-until (exit code 3)
        \\  -h, --help             Show this help
        \\  -v, --version          Show version
        \\
        \\Exit codes:
        \\  0  Success
        \\  1  Sensor not found or unsupported hardware
        \\  2  Invalid usage
        \\  3  Timeout (--wait-until with --timeout)
        \\
    ;
    File.stdout().writeStreamingAll(io, usage) catch {};
}

fn outputAngle(io: Io, angle: u16, format: Format) bool {
    return switch (format) {
        .plain => out(io, "{d}\n", .{angle}),
    };
}

fn outputDelta(io: Io, delta: i32, format: Format) bool {
    return switch (format) {
        .plain => if (delta > 0)
            out(io, "+{d}\n", .{delta})
        else
            out(io, "{d}\n", .{delta}),
    };
}

pub fn main(init: std.process.Init) u8 {
    const io = init.io;

    const args = parseArgs(init.minimal.args) catch |e| {
        const msg: []const u8 = switch (e) {
            error.MissingArgValue => "missing argument value",
            error.InvalidArgValue => "invalid argument value",
            error.UnknownArg => "unknown argument (see --help)",
            error.ConflictingMode => "--watch and --wait-until cannot be used together",
            error.TimeoutRequiresWaitUntil => "--timeout can only be used with --wait-until",
            error.DeltaRequiresWatch => "--delta can only be used with --watch",
        };
        err(io, "bend: {s}\n", .{msg});
        return exit_usage;
    };

    if (args.help) {
        printUsage(io);
        return exit_ok;
    }
    if (args.show_version) {
        _ = out(io, "bend {s}\n", .{version});
        return exit_ok;
    }

    const sensor = Sensor.open() catch {
        err(io, "Error: could not open lid angle sensor\n", .{});
        err(io, "Make sure you're on a MacBook and your terminal has Input Monitoring permission.\n", .{});
        return exit_sensor_error;
    };
    defer sensor.close();

    return switch (args.mode) {
        .oneshot => modeOneshot(io, sensor, args.format),
        .watch => modeWatch(io, sensor, args.format, args.interval_ms, args.delta),
        .wait_until => modeWaitUntil(io, sensor, args.format, args.threshold.?, args.interval_ms, args.timeout_ms),
    };
}

fn modeOneshot(io: Io, sensor: Sensor, format: Format) u8 {
    const angle = sensor.read() catch return exit_sensor_error;
    _ = outputAngle(io, angle, format);
    return exit_ok;
}

fn modeWatch(io: Io, sensor: Sensor, format: Format, interval_ms: u64, delta: bool) u8 {
    var prev_angle: ?u16 = null;
    while (true) {
        const angle = sensor.read() catch {
            sleepMs(io, interval_ms);
            continue;
        };
        const ok = if (delta) blk: {
            const d: i32 = if (prev_angle) |prev|
                @as(i32, angle) - @as(i32, prev)
            else
                0;
            prev_angle = angle;
            break :blk outputDelta(io, d, format);
        } else outputAngle(io, angle, format);
        if (!ok) return exit_ok;
        sleepMs(io, interval_ms);
    }
}

fn modeWaitUntil(io: Io, sensor: Sensor, format: Format, threshold: Threshold, interval_ms: u64, timeout_ms: ?u64) u8 {
    const start = Io.Timestamp.now(io, .awake);
    var wait_above: ?bool = switch (threshold.direction) {
        .above => true,
        .below => false,
        .auto => null,
    };

    while (true) {
        if (timeout_ms) |t| {
            const elapsed_ms = start.durationTo(Io.Timestamp.now(io, .awake)).toMilliseconds();
            if (elapsed_ms >= @as(i64, @intCast(t))) return exit_timeout;
        }

        const angle = sensor.read() catch {
            sleepMs(io, interval_ms);
            continue;
        };

        // Auto-direction: infer wait direction from where the lid is now
        // (e.g. current=90, target=140 → wait for above)
        if (wait_above == null) {
            if (angle == threshold.value) {
                _ = outputAngle(io, angle, format);
                return exit_ok;
            }
            wait_above = angle < threshold.value;
        }

        const reached = if (wait_above.?) angle >= threshold.value else angle <= threshold.value;
        if (reached) {
            _ = outputAngle(io, angle, format);
            return exit_ok;
        }

        sleepMs(io, interval_ms);
    }
}
