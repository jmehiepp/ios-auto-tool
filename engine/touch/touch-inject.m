#import "touch-inject.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <mach/mach_time.h>

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

static IOHIDEventSystemClientRef hid_client = NULL;

void touch_inject_init(void) {
    hid_client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
}

static void dispatch_hid_event(IOHIDEventRef event) {
    if (!hid_client || !event) return;
    IOHIDEventSystemClientDispatchEvent(hid_client, event);
    CFRelease(event);
}

// Clamp normalized coordinate to [0.0, 1.0]
static double clamp01(double v) {
    return v < 0.0 ? 0.0 : (v > 1.0 ? 1.0 : v);
}

static CGSize get_screen_size(void) {
    // logical points, matches Lua coordinate space
    return [UIScreen mainScreen].bounds.size;
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
    dispatch_hid_event(event);
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
    dispatch_hid_event(event);
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
    dispatch_hid_event(event);
}
