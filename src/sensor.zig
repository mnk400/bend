// Sensor abstraction: device discovery, probing, angle reading
// Created by Manik on March 26th 2026

const io = @import("iokit.zig");

pub const Error = error{
    ManagerCreateFailed,
    ManagerOpenFailed,
    DictCreateFailed,
    NoDevicesFound,
    DeviceOpenFailed,
    ReportReadFailed,
    ReportTooShort,
};

const vendor_id: c_int = 0x05AC;
const product_id: c_int = 0x8104;
const usage_page: c_int = 0x0020;
const usage: c_int = 0x008A;

const report_len = 8;
const max_devices = 16;

fn readReport(device: *anyopaque) Error!u16 {
    var report: [report_len]u8 = .{0} ** report_len;
    var length: io.CFIndex = report_len;

    const result = io.IOHIDDeviceGetReport(
        device,
        io.kIOHIDReportTypeFeature,
        1,
        &report,
        &length,
    );

    if (result != io.kIOReturnSuccess) return error.ReportReadFailed;
    if (length < 3) return error.ReportTooShort;

    return @as(u16, report[2]) << 8 | @as(u16, report[1]);
}

pub const Sensor = struct {
    device: *anyopaque,
    manager: *anyopaque,

    pub fn open() Error!Sensor {
        const manager = io.IOHIDManagerCreate(null, io.kIOHIDOptionsTypeNone) orelse
            return error.ManagerCreateFailed;
        errdefer {
            _ = io.IOHIDManagerClose(manager, io.kIOHIDOptionsTypeNone);
            io.CFRelease(manager);
        }

        if (io.IOHIDManagerOpen(manager, io.kIOHIDOptionsTypeNone) != io.kIOReturnSuccess)
            return error.ManagerOpenFailed;

        const dict = io.createDict(4) orelse return error.DictCreateFailed;
        defer io.CFRelease(dict);

        const vid = vendor_id;
        const pid = product_id;
        const up = usage_page;
        const u = usage;
        io.setDictInt(dict, "VendorID", &vid);
        io.setDictInt(dict, "ProductID", &pid);
        io.setDictInt(dict, "UsagePage", &up);
        io.setDictInt(dict, "Usage", &u);

        io.IOHIDManagerSetDeviceMatching(manager, dict);

        const device_set = io.IOHIDManagerCopyDevices(manager) orelse
            return error.NoDevicesFound;
        defer io.CFRelease(device_set);

        const count: usize = @intCast(io.CFSetGetCount(device_set));
        if (count == 0) return error.NoDevicesFound;

        var ptrs: [max_devices]?*anyopaque = .{null} ** max_devices;
        io.CFSetGetValues(device_set, &ptrs);

        const n = @min(count, max_devices);
        for (0..n) |i| {
            const dev = ptrs[i] orelse continue;

            if (io.IOHIDDeviceOpen(dev, io.kIOHIDOptionsTypeNone) != io.kIOReturnSuccess)
                continue;

            // Probe: only keep devices that respond with a valid feature report
            if (readReport(dev)) |_| {
                return .{ .device = dev, .manager = manager };
            } else |_| {
                _ = io.IOHIDDeviceClose(dev, io.kIOHIDOptionsTypeNone);
            }
        }

        return error.NoDevicesFound;
    }

    pub fn read(self: Sensor) Error!u16 {
        return readReport(self.device);
    }

    pub fn close(self: Sensor) void {
        _ = io.IOHIDDeviceClose(self.device, io.kIOHIDOptionsTypeNone);
        _ = io.IOHIDManagerClose(self.manager, io.kIOHIDOptionsTypeNone);
        io.CFRelease(self.manager);
    }
};
