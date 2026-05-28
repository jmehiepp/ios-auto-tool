#import "gesture.h"
#import "touch-inject.h"
#import <unistd.h>
#import <stdlib.h>

#define DEFAULT_FINGER 1

void c_tap(double x, double y) {
    send_touch_down(x, y, DEFAULT_FINGER);
    usleep(50000);
    send_touch_up(x, y, DEFAULT_FINGER);
}

void c_double_tap(double x, double y) {
    c_tap(x, y);
    usleep(100000);
    c_tap(x, y);
}

void c_long_press(double x, double y, int duration_ms) {
    send_touch_down(x, y, DEFAULT_FINGER);
    usleep((useconds_t)duration_ms * 1000);
    send_touch_up(x, y, DEFAULT_FINGER);
}

void c_swipe(double x1, double y1, double x2, double y2, int duration_ms) {
    int steps = duration_ms / 16;
    if (steps < 10) steps = 10;
    double dx = (x2 - x1) / steps;
    double dy = (y2 - y1) / steps;
    int step_delay = (duration_ms * 1000) / steps;

    send_touch_down(x1, y1, DEFAULT_FINGER);
    for (int i = 1; i <= steps; i++) {
        usleep((useconds_t)step_delay);
        send_touch_move(x1 + dx * i, y1 + dy * i, DEFAULT_FINGER);
    }
    send_touch_up(x2, y2, DEFAULT_FINGER);
}

void c_touch_down(double x, double y, uint32_t finger_id) {
    send_touch_down(x, y, finger_id);
}

void c_touch_move(double x, double y, uint32_t finger_id) {
    send_touch_move(x, y, finger_id);
}

void c_touch_up(double x, double y, uint32_t finger_id) {
    send_touch_up(x, y, finger_id);
}
