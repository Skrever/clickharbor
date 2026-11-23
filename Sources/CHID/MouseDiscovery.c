#include "MouseDiscovery.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hid/IOHIDLib.h>
#include <IOKit/hid/IOHIDUsageTables.h>

static int number_value(CFTypeRef property) {
    int value = 0;
    if (property && CFGetTypeID(property) == CFNumberGetTypeID()) {
        return CFNumberGetValue((CFNumberRef)property, kCFNumberIntType, &value) ? value : 0;
    }
    return 0;
}

static bool built_in_device(IOHIDDeviceRef device) {
    CFTypeRef property = IOHIDDeviceGetProperty(device, CFSTR(kIOHIDBuiltInKey));
    if (property && CFGetTypeID(property) == CFBooleanGetTypeID()) {
        return CFBooleanGetValue((CFBooleanRef)property);
    }
    return number_value(property) != 0;
}

static bool trackpad_device(IOHIDDeviceRef device) {
    if (IOHIDDeviceConformsTo(device, kHIDPage_Digitizer, kHIDUsage_Dig_TouchPad)) return true;
    CFTypeRef product = IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductKey));
    return product && CFGetTypeID(product) == CFStringGetTypeID() &&
        (CFStringFind((CFStringRef)product, CFSTR("trackpad"), kCFCompareCaseInsensitive).location != kCFNotFound ||
         CFStringFind((CFStringRef)product, CFSTR("touchpad"), kCFCompareCaseInsensitive).location != kCFNotFound);
}

static void check_mouse(const void *value, void *context) {
    bool *found = context;
    if (*found) return;

    IOHIDDeviceRef device = (IOHIDDeviceRef)value;
    CFTypeRef transport = IOHIDDeviceGetProperty(device, CFSTR(kIOHIDTransportKey));
    if (!transport || CFGetTypeID(transport) != CFStringGetTypeID()) return;

    const bool usb = CFEqual(transport, CFSTR(kIOHIDTransportUSBValue));
    const bool bluetooth = CFStringHasPrefix((CFStringRef)transport, CFSTR(kIOHIDTransportBluetoothValue));
    if ((!usb && !bluetooth) || built_in_device(device) || trackpad_device(device)) return;

    const int vendor = number_value(IOHIDDeviceGetProperty(device, CFSTR(kIOHIDVendorIDKey)));
    const int product = number_value(IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductIDKey)));
    const bool supported = usb && ((vendor == 0x248a && product == 0x5e2e) ||
        (vendor == 0x3554 && (product == 0xfb09 || product == 0xfb08)));
    *found = !supported;
}

bool io_unsupported_mouse_present(void) {
    IOHIDManagerRef manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (!manager) return false;

    const int page = kHIDPage_GenericDesktop;
    const int usage = kHIDUsage_GD_Mouse;
    CFNumberRef page_value = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &page);
    CFNumberRef usage_value = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &usage);
    CFDictionaryRef match = NULL;
    if (page_value && usage_value) {
        const void *keys[] = {CFSTR(kIOHIDDeviceUsagePageKey), CFSTR(kIOHIDDeviceUsageKey)};
        const void *values[] = {page_value, usage_value};
        match = CFDictionaryCreate(kCFAllocatorDefault, keys, values, 2,
                                   &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    }
    if (page_value) CFRelease(page_value);
    if (usage_value) CFRelease(usage_value);

    bool found = false;
    if (match) {
        IOHIDManagerSetDeviceMatching(manager, match);
        CFSetRef devices = IOHIDManagerCopyDevices(manager);
        if (devices) {
            CFSetApplyFunction(devices, check_mouse, &found);
            CFRelease(devices);
        }
        CFRelease(match);
    }
    CFRelease(manager);
    return found;
}
