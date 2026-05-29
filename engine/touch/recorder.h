#pragma once
#import <Foundation/Foundation.h>

void recorder_start(void);
NSString *recorder_stop_and_codegen(void);
BOOL recorder_is_recording(void);
NSArray *recorder_get_events(void);
void recorder_log_tap(double x, double y);
void recorder_log_swipe(double x1, double y1, double x2, double y2);
void recorder_clear(void);
