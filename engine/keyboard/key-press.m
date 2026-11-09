#import "key-press.h"
#import <CoreFoundation/CoreFoundation.h>
#import <mach/mach_time.h>
#import <unistd.h>

// IOHIDEvent private API — reuse declarations from touch-inject.m context
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
typedef struct __IOHIDEvent            *IOHIDEventRef;
typedef uint32_t IOOptionBits;

// HID pages
#define kHIDPage_KeyboardOrKeypad 0x07
#define kHIDPage_Consumer         0x0C

// Consumer key usages
#define kHIDUsage_Csmr_Menu            0x0040  // Home button
#define kHIDUsage_Csmr_Power           0x0030  // Lock/Power
#define kHIDUsage_Csmr_VolumeIncrement 0x00E9
#define kHIDUsage_Csmr_VolumeDecrement 0x00EA
#define kHIDUsage_Csmr_Mute            0x00E2

extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef);
extern IOHIDEventRef IOHIDEventCreateKeyboardEvent(
    CFAllocatorRef allocator,
    uint64_t timeStamp,
    uint32_t usagePage,
    uint32_t usage,
    Boolean  down,
    IOOptionBits options
);
extern void IOHIDEventSystemClientDispatchEvent(IOHIDEventSystemClientRef, IOHIDEventRef);

static IOHIDEventSystemClientRef s_hid_client = NULL;

static IOHIDEventSystemClientRef get_client(void) {
    if (!s_hid_client)
        s_hid_client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    return s_hid_client;
}

static void dispatch_key(uint32_t page, uint32_t usage, uint32_t modifiers) {
    IOHIDEventSystemClientRef client = get_client();
    if (!client) return;
    bool command = (modifiers & 0x100) != 0;
    if (command) {
        IOHIDEventRef modifier = IOHIDEventCreateKeyboardEvent(kCFAllocatorDefault, mach_absolute_time(), 7, 0xe3, true, 0);
        if (modifier) { IOHIDEventSystemClientDispatchEvent(client, modifier); CFRelease(modifier); }
    }

    uint64_t ts = mach_absolute_time();
    IOHIDEventRef down = IOHIDEventCreateKeyboardEvent(
        kCFAllocatorDefault, ts, page, usage, true, 0);
    if (down) { IOHIDEventSystemClientDispatchEvent(client, down); CFRelease(down); }

    usleep(50000);

    ts = mach_absolute_time();
    IOHIDEventRef up = IOHIDEventCreateKeyboardEvent(
        kCFAllocatorDefault, ts, page, usage, false, 0);
    if (up) { IOHIDEventSystemClientDispatchEvent(client, up); CFRelease(up); }
    if (command) {
        IOHIDEventRef modifier = IOHIDEventCreateKeyboardEvent(kCFAllocatorDefault, mach_absolute_time(), 7, 0xe3, false, 0);
        if (modifier) { IOHIDEventSystemClientDispatchEvent(client, modifier); CFRelease(modifier); }
    }
}

void c_send_key(unsigned short hid_usage, unsigned int modifiers) {
    dispatch_key(kHIDPage_KeyboardOrKeypad, hid_usage, modifiers);
}

void c_press_home(void) {
    dispatch_key(kHIDPage_Consumer, kHIDUsage_Csmr_Menu, 0);
}

void c_press_lock(void) {
    dispatch_key(kHIDPage_Consumer, kHIDUsage_Csmr_Power, 0);
}

void c_press_volume(bool up) {
    uint32_t usage = up ? kHIDUsage_Csmr_VolumeIncrement
                        : kHIDUsage_Csmr_VolumeDecrement;
    dispatch_key(kHIDPage_Consumer, usage, 0);
}

void c_press_mute(void) {
    dispatch_key(kHIDPage_Consumer, kHIDUsage_Csmr_Mute, 0);
}
