#pragma once
#include <stdint.h>

void c_tap(double x, double y);
void c_double_tap(double x, double y);
void c_long_press(double x, double y, int duration_ms);
void c_swipe(double x1, double y1, double x2, double y2, int duration_ms);
void c_touch_down(double x, double y, uint32_t finger_id);
void c_touch_move(double x, double y, uint32_t finger_id);
void c_touch_up(double x, double y, uint32_t finger_id);
