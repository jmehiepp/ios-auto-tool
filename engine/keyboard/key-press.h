#pragma once
#include <stdbool.h>

void c_press_home(void);
void c_press_lock(void);
void c_press_volume(bool up);
void c_press_mute(void);
void c_send_key(unsigned short hid_usage, unsigned int modifiers);
