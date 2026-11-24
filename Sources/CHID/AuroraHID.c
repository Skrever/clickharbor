#include "AuroraHID.h"
#include "CHID.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hid/IOHIDLib.h>
#include <stdlib.h>
#include <string.h>

enum {
    report_id = 8,
    report_size = 17,
    payload_offset = 6,
    max_payload = 10,
    command_read = 0x08,
    command_write = 0x07,
};

struct AuroraHID {
    IOHIDManagerRef manager;
    IOHIDDeviceRef device;
    CFRunLoopRef loop;
    AuroraHIDRoute route;
    uint8_t input[report_size];
    uint8_t request[report_size];
    uint8_t reply[report_size];
    size_t reply_prefix_length;
    bool received;
};

static IOHIDManagerRef matching_manager(AuroraHIDRoute route) {
    if (route != AuroraHIDCable && route != AuroraHIDReceiver) return NULL;
    IOHIDManagerRef manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (!manager) return NULL;

    CFMutableDictionaryRef match = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 5, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks
    );
    if (!match) {
        CFRelease(manager);
        return NULL;
    }
    const CFStringRef keys[] = {
        CFSTR(kIOHIDVendorIDKey), CFSTR(kIOHIDProductIDKey),
        CFSTR(kIOHIDPrimaryUsagePageKey), CFSTR(kIOHIDPrimaryUsageKey),
    };
    const int values[] = {0x3554, (int)route, 0xff05, 0};
    for (unsigned i = 0; i < sizeof(values) / sizeof(values[0]); ++i) {
        CFNumberRef value = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &values[i]);
        if (!value) {
            CFRelease(match);
            CFRelease(manager);
            return NULL;
        }
        CFDictionarySetValue(match, keys[i], value);
        CFRelease(value);
    }
    CFDictionarySetValue(match, CFSTR(kIOHIDTransportKey), CFSTR("USB"));
    IOHIDManagerSetDeviceMatching(manager, match);
    CFRelease(match);
    return manager;
}

bool aurora_hid_present(AuroraHIDRoute route) {
    IOHIDManagerRef manager = matching_manager(route);
    if (!manager) return false;
    CFSetRef devices = IOHIDManagerCopyDevices(manager);
    bool present = devices && CFSetGetCount(devices) > 0;
    if (devices) CFRelease(devices);
    CFRelease(manager);
    return present;
}

static uint8_t checksum(const uint8_t *packet) {
    uint8_t sum = 0;
    for (size_t i = 0; i < report_size - 1; ++i) sum += packet[i];
    return (uint8_t)(0x55 - sum);
}

static void on_input(void *context, IOReturn status, void *sender, IOHIDReportType type,
                     uint32_t id, uint8_t *data, CFIndex length) {
    (void)sender;
    AuroraHID *hid = context;
    if (status != kIOReturnSuccess || type != kIOHIDReportTypeInput || id != report_id ||
        (length != report_size && length != report_size - 1)) return;

    uint8_t packet[report_size] = {report_id};
    memcpy(packet + (length == report_size ? 0 : 1), data, (size_t)length);
    if (hid->reply_prefix_length == 0 || memcmp(packet, hid->request, hid->reply_prefix_length) != 0 ||
        packet[report_size - 1] != checksum(packet)) return;
    memcpy(hid->reply, packet, sizeof(packet));
    hid->received = true;
}

AuroraHID *aurora_hid_open(AuroraHIDRoute route, int32_t *status) {
    if (!status) return NULL;
    *status = AiroxHIDUnavailable;
    AuroraHID *hid = calloc(1, sizeof(*hid));
    if (!hid) return NULL;
    hid->route = route;
    hid->manager = matching_manager(route);
    if (!hid->manager) {
        free(hid);
        return NULL;
    }

    CFSetRef devices = IOHIDManagerCopyDevices(hid->manager);
    CFIndex count = devices ? CFSetGetCount(devices) : 0;
    if (count != 1) {
        *status = count == 0 ? AiroxHIDNotFound : AiroxHIDAmbiguous;
        if (devices) CFRelease(devices);
        CFRelease(hid->manager);
        free(hid);
        return NULL;
    }

    const void *device = NULL;
    CFSetGetValues(devices, &device);
    hid->device = (IOHIDDeviceRef)CFRetain(device);
    CFRelease(devices);
    *status = IOHIDDeviceOpen(hid->device, kIOHIDOptionsTypeNone);
    if (*status != kIOReturnSuccess) {
        CFRelease(hid->device);
        CFRelease(hid->manager);
        free(hid);
        return NULL;
    }

    hid->loop = CFRunLoopGetCurrent();
    IOHIDDeviceScheduleWithRunLoop(hid->device, hid->loop, kCFRunLoopDefaultMode);
    IOHIDDeviceRegisterInputReportCallback(hid->device, hid->input, sizeof(hid->input), on_input, hid);
    return hid;
}

bool aurora_hid_is_aurora_product(AuroraHID *hid) {
    if (!hid) return false;
    CFTypeRef product = IOHIDDeviceGetProperty(hid->device, CFSTR(kIOHIDProductKey));
    CFStringRef expected = hid->route == AuroraHIDReceiver ? CFSTR("IO Aurora Receiver") : CFSTR("IO Aurora");
    return product && CFGetTypeID(product) == CFStringGetTypeID() &&
           CFStringCompare(product, expected, kCFCompareCaseInsensitive) == kCFCompareEqualTo;
}

bool aurora_hid_is_pairable_receiver(AuroraHID *hid) {
    return hid && hid->route == AuroraHIDReceiver && aurora_hid_is_aurora_product(hid);
}

static void prepare(AuroraHID *hid, uint8_t command, uint16_t address, uint8_t count) {
    memset(hid->request, 0, sizeof(hid->request));
    hid->request[0] = report_id;
    hid->request[1] = command;
    hid->request[3] = (uint8_t)(address >> 8);
    hid->request[4] = (uint8_t)address;
    hid->request[5] = count;
    hid->reply_prefix_length = payload_offset;
}

static IOReturn exchange(AuroraHID *hid, double timeout) {
    hid->request[report_size - 1] = checksum(hid->request);
    hid->received = false;
    IOReturn status = IOHIDDeviceSetReport(
        hid->device, kIOHIDReportTypeOutput, report_id, hid->request, sizeof(hid->request)
    );
    if (status != kIOReturnSuccess) return status;

    const CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + timeout;
    while (!hid->received && CFAbsoluteTimeGetCurrent() < deadline) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.020, true);
    }
    return kIOReturnSuccess;
}

static bool valid_range(uint16_t address, uint8_t count) {
    return count > 0 && count <= max_payload && (unsigned)address + count - 1 <= UINT16_MAX;
}

int32_t aurora_hid_read(AuroraHID *hid, uint16_t address, uint8_t count, uint8_t *output) {
    if (!hid || !output || !valid_range(address, count)) return kIOReturnBadArgument;
    prepare(hid, command_read, address, count);
    const unsigned attempts = hid->route == AuroraHIDReceiver ? 3 : 2;
    for (unsigned attempt = 0; attempt < attempts; ++attempt) {
        IOReturn status = exchange(hid, 0.35);
        if (status != kIOReturnSuccess) return status;
        if (hid->received) {
            memcpy(output, hid->reply + payload_offset, count);
            return kIOReturnSuccess;
        }
    }
    return AiroxHIDNoReply;
}

int32_t aurora_hid_write(AuroraHID *hid, uint16_t address, uint8_t count, const uint8_t *data) {
    if (!hid || !data || !valid_range(address, count)) return kIOReturnBadArgument;
    prepare(hid, command_write, address, count);
    memcpy(hid->request + payload_offset, data, count);
    // Read-back is authoritative even when the device does not echo the write.
    return exchange(hid, 0.16);
}

int32_t aurora_hid_command(AuroraHID *hid, uint8_t command, uint8_t argument_count,
                           const uint8_t *arguments, uint32_t timeout_ms, uint8_t *reply) {
    const size_t argument_offset = 3;
    if (!hid || !reply || timeout_ms == 0 || (argument_count && !arguments) ||
        argument_count > report_size - 1 - argument_offset) return kIOReturnBadArgument;

    prepare(hid, command, 0, 0);
    if (argument_count) memcpy(hid->request + argument_offset, arguments, argument_count);
    hid->reply_prefix_length = 2;
    IOReturn status = exchange(hid, timeout_ms / 1000.0);
    if (status != kIOReturnSuccess) return status;
    if (!hid->received) return AiroxHIDNoReply;

    memcpy(reply, hid->reply, sizeof(hid->reply));
    return kIOReturnSuccess;
}

void aurora_hid_close(AuroraHID *hid) {
    if (!hid) return;
    IOHIDDeviceRegisterInputReportCallback(hid->device, hid->input, sizeof(hid->input), NULL, NULL);
    IOHIDDeviceUnscheduleFromRunLoop(hid->device, hid->loop, kCFRunLoopDefaultMode);
    IOHIDDeviceClose(hid->device, kIOHIDOptionsTypeNone);
    CFRelease(hid->device);
    CFRelease(hid->manager);
    free(hid);
}
