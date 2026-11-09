#import "touch-inject.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <mach/mach_time.h>
#include <math.h>

// IOHIDEvent private API declarations
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
typedef struct __IOHIDEvent *IOHIDEventRef;
typedef uint32_t IOOptionBits;
typedef uint32_t IOHIDEventField;

enum {
    kIOHIDEventTypeDigitizer = 11,
};
enum {
    kIOHIDDigitizerEventRange    = 0x00000001,
    kIOHIDDigitizerEventTouch    = 0x00000002,
    kIOHIDDigitizerEventPosition = 0x00000004,
};

extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern IOHIDEventRef IOHIDEventCreateDigitizerFingerEvent(
    CFAllocatorRef allocator,
    uint64_t timeStamp,
    uint32_t index,
    uint32_t identity,
    uint32_t eventMask,
    double x, double y,
    double z, double tipPressure,
    double twist,
    Boolean range, Boolean touch,
    IOOptionBits options
);
extern void IOHIDEventSystemClientDispatchEvent(IOHIDEventSystemClientRef client, IOHIDEventRef event);
extern IOHIDEventRef IOHIDEventCreateDigitizerEvent(CFAllocatorRef, uint64_t, uint32_t,
    uint32_t, uint32_t, uint32_t, uint32_t, double, double, double, double, double, Boolean, Boolean, IOOptionBits);
extern void IOHIDEventAppendEvent(IOHIDEventRef parent, IOHIDEventRef child);
extern void IOHIDEventSetIntegerValue(IOHIDEventRef event, IOHIDEventField field, int value);

static IOHIDEventSystemClientRef hid_client = NULL;

void touch_inject_init(void) {
    hid_client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
}

static void dispatch_hid_event(IOHIDEventRef event, double x, double y, bool touching, uint32_t mask) {
    if (!event) return;
    if (!hid_client) touch_inject_init();
    if (!hid_client) { CFRelease(event); return; }
    IOHIDEventRef hand = IOHIDEventCreateDigitizerEvent(kCFAllocatorDefault, mach_absolute_time(),
        3, 0, 0, mask, 0, x, y, 0, touching ? 1 : 0, 0, touching, touching, 0);
    if (hand) {
        IOHIDEventSetIntegerValue(hand, 1, 1);
        IOHIDEventSetIntegerValue(hand, 0xb0025, 1);
        IOHIDEventAppendEvent(hand, event);
        IOHIDEventSystemClientDispatchEvent(hid_client, hand);
        CFRelease(hand);
    }
    CFRelease(event);
}

// Clamp normalized coordinate to [0.0, 1.0]
static double clamp01(double v) {
    if (!isfinite(v)) return 0;
    return v < 0.0 ? 0.0 : (v > 1.0 ? 1.0 : v);
}

static CGSize get_screen_size(void) {
    // logical points, matches Lua coordinate space
    __block CGSize size = CGSizeMake(1, 1);
    void (^readSize)(void) = ^{ size = UIScreen.mainScreen.bounds.size; };
    if (NSThread.isMainThread) readSize(); else dispatch_sync(dispatch_get_main_queue(), readSize);
    return size;
}

void send_touch_down(double x, double y, uint32_t finger_id) {
    CGSize s = get_screen_size();
    double nx = clamp01(x / s.width);
    double ny = clamp01(y / s.height);
    uint64_t ts = mach_absolute_time();
    IOHIDEventRef event = IOHIDEventCreateDigitizerFingerEvent(
        kCFAllocatorDefault, ts,
        finger_id, finger_id,
        kIOHIDDigitizerEventRange | kIOHIDDigitizerEventTouch,
        nx, ny, 0, 1.0, 0,
        true, true, 0
    );
    dispatch_hid_event(event, nx, ny, true, 7);
}

void send_touch_move(double x, double y, uint32_t finger_id) {
    CGSize s = get_screen_size();
    double nx = clamp01(x / s.width);
    double ny = clamp01(y / s.height);
    uint64_t ts = mach_absolute_time();
    IOHIDEventRef event = IOHIDEventCreateDigitizerFingerEvent(
        kCFAllocatorDefault, ts,
        finger_id, finger_id,
        kIOHIDDigitizerEventPosition,
        nx, ny, 0, 1.0, 0,
        true, true, 0
    );
    dispatch_hid_event(event, nx, ny, true, 4);
}

void send_touch_up(double x, double y, uint32_t finger_id) {
    CGSize s = get_screen_size();
    double nx = clamp01(x / s.width);
    double ny = clamp01(y / s.height);
    uint64_t ts = mach_absolute_time();
    IOHIDEventRef event = IOHIDEventCreateDigitizerFingerEvent(
        kCFAllocatorDefault, ts,
        finger_id, finger_id,
        kIOHIDDigitizerEventRange | kIOHIDDigitizerEventTouch,
        nx, ny, 0, 0, 0,
        false, false, 0
    );
    dispatch_hid_event(event, nx, ny, false, 7);
}
