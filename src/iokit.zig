// Raw IOKit / CoreFoundation C bindings and helpers.
// Created by Manik on March 26th 2026

pub const CFIndex = i64;
pub const IOOptionBits = u32;
pub const IOReturn = i32;
pub const CFStringEncoding = u32;
pub const CFNumberType = CFIndex;

pub const kIOHIDOptionsTypeNone: IOOptionBits = 0;
pub const kIOReturnSuccess: IOReturn = 0;
pub const kIOHIDReportTypeFeature: u32 = 2;
pub const kCFStringEncodingUTF8: CFStringEncoding = 0x08000100;
pub const kCFNumberIntType: CFNumberType = 9;

// IOKit HID
pub extern "c" fn IOHIDManagerCreate(allocator: ?*anyopaque, options: IOOptionBits) ?*anyopaque;
pub extern "c" fn IOHIDManagerOpen(manager: *anyopaque, options: IOOptionBits) IOReturn;
pub extern "c" fn IOHIDManagerClose(manager: *anyopaque, options: IOOptionBits) IOReturn;
pub extern "c" fn IOHIDManagerSetDeviceMatching(manager: *anyopaque, matching: ?*anyopaque) void;
pub extern "c" fn IOHIDManagerCopyDevices(manager: *anyopaque) ?*anyopaque;

pub extern "c" fn IOHIDDeviceOpen(device: *anyopaque, options: IOOptionBits) IOReturn;
pub extern "c" fn IOHIDDeviceClose(device: *anyopaque, options: IOOptionBits) IOReturn;
pub extern "c" fn IOHIDDeviceGetReport(device: *anyopaque, report_type: u32, report_id: CFIndex, report: [*]u8, report_length: *CFIndex) IOReturn;

// CoreFoundation
pub extern "c" fn CFSetGetCount(set: *anyopaque) CFIndex;
pub extern "c" fn CFSetGetValues(set: *anyopaque, values: [*]?*anyopaque) void;
pub extern "c" fn CFRelease(cf: *anyopaque) void;

pub extern "c" fn CFStringCreateWithCString(alloc: ?*anyopaque, cstr: [*:0]const u8, encoding: CFStringEncoding) ?*anyopaque;
pub extern "c" fn CFNumberCreate(allocator: ?*anyopaque, the_type: CFNumberType, value_ptr: *const anyopaque) ?*anyopaque;
pub extern "c" fn CFDictionaryCreateMutable(allocator: ?*anyopaque, capacity: CFIndex, key_callbacks: ?*const anyopaque, value_callbacks: ?*const anyopaque) ?*anyopaque;
pub extern "c" fn CFDictionarySetValue(dict: *anyopaque, key: *const anyopaque, value: *const anyopaque) void;

pub extern "c" const kCFTypeDictionaryKeyCallBacks: anyopaque;
pub extern "c" const kCFTypeDictionaryValueCallBacks: anyopaque;

// -- Helpers --

pub fn cfstr(s: [*:0]const u8) ?*anyopaque {
    return CFStringCreateWithCString(null, s, kCFStringEncodingUTF8);
}

pub fn cfint(val: *const c_int) ?*anyopaque {
    return CFNumberCreate(null, kCFNumberIntType, @ptrCast(val));
}

pub fn createDict(capacity: CFIndex) ?*anyopaque {
    return CFDictionaryCreateMutable(null, capacity, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
}

pub fn setDictInt(dict: *anyopaque, key: [*:0]const u8, val: *const c_int) void {
    const k = cfstr(key) orelse return;
    defer CFRelease(k);
    const v = cfint(val) orelse return;
    defer CFRelease(v);
    CFDictionarySetValue(dict, @ptrCast(k), @ptrCast(v));
}
