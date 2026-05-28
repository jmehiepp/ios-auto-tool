#pragma once
#include <stdint.h>
#include <stdbool.h>

void touch_inject_init(void);
void send_touch_down(double nx, double ny, uint32_t finger_id);
void send_touch_move(double nx, double ny, uint32_t finger_id);
void send_touch_up(double nx, double ny, uint32_t finger_id);
