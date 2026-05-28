#pragma once
#import <Foundation/Foundation.h>

void c_type_text(NSString *text);
void c_keyboard_type(const char *type);  // "default","number","email","url","phone"
void c_set_keyboard_language(const char *lang);
void c_set_clipboard(NSString *text);
NSString *c_get_clipboard(void);
void c_clear_clipboard(void);
