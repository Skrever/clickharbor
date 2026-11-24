#include "CHID.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hid/IOHIDLib.h>
#include <stdlib.h>
#include <string.h>

enum { report_size = 32 };

struct AiroxHID {
    IOHIDManagerRef manager;
    IOHIDDeviceRef device;
    CFRunLoopRef loop;
    uint8_t input[report_size];
    uint8_t reply[report_size];
    uint8_t expected_code;
    bool received;
};

static IOHIDManagerRef matching_manager(void) {
    IOHIDManagerRef manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (!manager) return NULL;
    const CFStringRef keys[] = {
        CFSTR(kIOHIDVendorIDKey), CFSTR(kIOHIDProductIDKey),
        CFSTR(kIOHIDPrimaryUsagePageKey), CFSTR(kIOHIDPrimaryUsageKey),
    };
    const int values[] = {0x248a, 0x5e2e, 0xff01, 0x10};
    CFMutableDictionaryRef match = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 5, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks
    );
    for (unsigned i = 0; i < sizeof(values) / sizeof(values[0]); ++i) {
        CFNumberRef number = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &values[i]);
        CFDictionarySetValue(match, keys[i], number);
        CFRelease(number);
    }
    CFDictionarySetValue(match, CFSTR(kIOHIDTransportKey), CFSTR("USB"));
    IOHIDManagerSetDeviceMatching(manager, match);
    CFRelease(match);
    return manager;
}

bool airox_hid_present(void) {
    IOHIDManagerRef manager = matching_manager();
    if (!manager) return false;
    CFSetRef devices = IOHIDManagerCopyDevices(manager);
    bool present = devices && CFSetGetCount(devices) > 0;
    if (devices) CFRelease(devices);
    CFRelease(manager);
    return present;
}

static void on_input(void *context, IOReturn status, void *sender, IOHIDReportType type,
                     uint32_t report_id, uint8_t *report, CFIndex length) {
    (void)sender;
    AiroxHID *hid = context;
    if (status != kIOReturnSuccess || type != kIOHIDReportTypeInput || report_id != 0 ||
        length != report_size || report[0] != hid->expected_code || report[1] != 0) return;
    memcpy(hid->reply, report, report_size);
    hid->received = true;
}

AiroxHID *airox_hid_open(int32_t *status) {
    *status = AiroxHIDUnavailable;
    AiroxHID *hid = calloc(1, sizeof(*hid));
    if (!hid) return NULL;
    hid->manager = matching_manager();
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

static void pump(AiroxHID *hid, double seconds) {
    const CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + seconds;
    while (!hid->received && CFAbsoluteTimeGetCurrent() < deadline) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.025, true);
    }
}

int32_t airox_hid_query(AiroxHID *hid, uint8_t code, uint8_t *response) {
    uint8_t packet[report_size] = {code};
    hid->expected_code = code;
    hid->received = false;
    IOReturn status = IOHIDDeviceSetReport(hid->device, kIOHIDReportTypeOutput, 0, packet, sizeof(packet));
    if (status != kIOReturnSuccess) return status;
    pump(hid, 0.45);
    if (!hid->received) return AiroxHIDNoReply;
    memcpy(response, hid->reply, report_size);
    return kIOReturnSuccess;
}

static int32_t write_report(AiroxHID *hid, const uint8_t *packet, bool require_confirmation) {
    hid->expected_code = packet[0];
    hid->received = false;
    IOReturn status = IOHIDDeviceSetReport(hid->device, kIOHIDReportTypeOutput, 0, packet, report_size);
    if (status != kIOReturnSuccess) return status;
    pump(hid, require_confirmation ? 0.45 : 0.16);
    if (require_confirmation && !hid->received) return AiroxHIDNoReply;
    return kIOReturnSuccess;
}

int32_t airox_hid_write(AiroxHID *hid, const uint8_t *packet) {
    return write_report(hid, packet, false);
}

int32_t airox_hid_write_confirmed(AiroxHID *hid, const uint8_t *packet) {
    return write_report(hid, packet, true);
}

void airox_hid_close(AiroxHID *hid) {
    IOHIDDeviceRegisterInputReportCallback(hid->device, hid->input, sizeof(hid->input), NULL, NULL);
    IOHIDDeviceUnscheduleFromRunLoop(hid->device, hid->loop, kCFRunLoopDefaultMode);
    IOHIDDeviceClose(hid->device, kIOHIDOptionsTypeNone);
    CFRelease(hid->device);
    CFRelease(hid->manager);
    free(hid);
}
