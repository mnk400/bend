// Main zig file that contains CLI and execution related configuration
// Created by Manik on March 26th 2026

const std = @import("std");
const Sensor = @import("sensor.zig").Sensor;

const version = "0.1.0";

const exit_ok = 0;
const exit_sensor_error = 1;
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
    help: bool = false,
    show_version: bool = false,
};

fn parseArgs(alloc: std.mem.Allocator) error{ MissingArgValue, InvalidArgValue, UnknownArg }!Args {
    var iter = std.process.argsWithAllocator(alloc) catch return error.InvalidArgValue;
    defer iter.deinit();
    _ = iter.next(); // skip argv[0]

    var args = Args{};

    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            args.help = true;
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            args.show_version = true;
        } else if (std.mem.eql(u8, arg, "--watch") or std.mem.eql(u8, arg, "-w")) {
            args.mode = .watch;
        } else if (std.mem.eql(u8, arg, "--interval") or std.mem.eql(u8, arg, "-i")) {
            const val = iter.next() orelse return error.MissingArgValue;
            args.interval_ms = parseSecsToMs(val) catch return error.InvalidArgValue;
        } else if (std.mem.eql(u8, arg, "--wait-until")) {
            args.mode = .wait_until;
            const val = iter.next() orelse return error.MissingArgValue;
            args.threshold = parseThreshold(val) orelse return error.InvalidArgValue;
        } else if (std.mem.eql(u8, arg, "--timeout")) {
            const val = iter.next() orelse return error.MissingArgValue;
            args.timeout_ms = parseSecsToMs(val) catch return error.InvalidArgValue;
        } else {
            return error.UnknownArg;
        }
    }

    return args;
}

fn parseSecsToMs(val: []const u8) error{InvalidArgValue}!u64 {
    const secs = std.fmt.parseFloat(f64, val) catch return error.InvalidArgValue;
    return @intFromFloat(secs * 1000);
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

fn writeTo(file: std.fs.File, comptime fmt: []const u8, fmtargs: anytype) void {
    var buf: [256]u8 = undefined;
    const slice = std.fmt.bufPrint(&buf, fmt, fmtargs) catch return;
    file.writeAll(slice) catch {};
}

fn out(comptime fmt: []const u8, fmtargs: anytype) void {
    writeTo(std.fs.File.stdout(), fmt, fmtargs);
}

fn err(comptime fmt: []const u8, fmtargs: anytype) void {
    writeTo(std.fs.File.stderr(), fmt, fmtargs);
}

fn printUsage() void {
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
        \\  -i, --interval <secs>  Interval between readings (default: 0.5)
        \\  --timeout <secs>       Timeout for --wait-until (exit code 3)
        \\  -h, --help             Show this help
        \\  -v, --version          Show version
        \\
        \\Exit codes:
        \\  0  Success
        \\  1  Sensor not found or unsupported hardware
        \\  3  Timeout (--wait-until with --timeout)
        \\
    ;
    std.fs.File.stdout().writeAll(usage) catch {};
}

fn outputAngle(angle: u16, format: Format) void {
    switch (format) {
        .plain => out("{d}\n", .{angle}),
    }
}

pub fn main() u8 {
    const args = parseArgs(std.heap.page_allocator) catch |e| {
        const msg: []const u8 = switch (e) {
            error.MissingArgValue => "missing argument value",
            error.InvalidArgValue => "invalid argument value",
            error.UnknownArg => "unknown argument (see --help)",
        };
        err("Error: {s}\n", .{msg});
        return exit_sensor_error;
    };

    if (args.help) {
        printUsage();
        return exit_ok;
    }
    if (args.show_version) {
        out("bend {s}\n", .{version});
        return exit_ok;
    }

    const sensor = Sensor.open() catch {
        err("Error: could not open lid angle sensor\n", .{});
        err("Make sure you're on a MacBook and your terminal has Input Monitoring permission.\n", .{});
        return exit_sensor_error;
    };
    defer sensor.close();

    return switch (args.mode) {
        .oneshot => modeOneshot(sensor, args.format),
        .watch => modeWatch(sensor, args.format, args.interval_ms),
        .wait_until => modeWaitUntil(sensor, args.format, args.threshold.?, args.interval_ms, args.timeout_ms),
    };
}

fn modeOneshot(sensor: Sensor, format: Format) u8 {
    const angle = sensor.read() catch return exit_sensor_error;
    outputAngle(angle, format);
    return exit_ok;
}

fn modeWatch(sensor: Sensor, format: Format, interval_ms: u64) u8 {
    var last_angle: ?u16 = null;
    while (true) {
        const angle = sensor.read() catch {
            std.Thread.sleep(interval_ms * std.time.ns_per_ms);
            continue;
        };
        // Only print when the angle changes to keep output clean for piping
        if (last_angle == null or last_angle.? != angle) {
            outputAngle(angle, format);
            last_angle = angle;
        }
        std.Thread.sleep(interval_ms * std.time.ns_per_ms);
    }
}

fn modeWaitUntil(sensor: Sensor, format: Format, threshold: Threshold, interval_ms: u64, timeout_ms: ?u64) u8 {
    const start_ms = std.time.milliTimestamp();
    var wait_above: ?bool = switch (threshold.direction) {
        .above => true,
        .below => false,
        .auto => null,
    };

    while (true) {
        if (timeout_ms) |t| {
            const elapsed: u64 = @intCast(@max(0, std.time.milliTimestamp() - start_ms));
            if (elapsed >= t) return exit_timeout;
        }

        const angle = sensor.read() catch {
            std.Thread.sleep(interval_ms * std.time.ns_per_ms);
            continue;
        };

        // Auto-direction: infer wait direction from where the lid is now
        // (e.g. current=90, target=140 → wait for above)
        if (wait_above == null) {
            if (angle == threshold.value) {
                outputAngle(angle, format);
                return exit_ok;
            }
            wait_above = angle < threshold.value;
        }

        const reached = if (wait_above.?) angle >= threshold.value else angle <= threshold.value;
        if (reached) {
            outputAngle(angle, format);
            return exit_ok;
        }

        std.Thread.sleep(interval_ms * std.time.ns_per_ms);
    }
}
