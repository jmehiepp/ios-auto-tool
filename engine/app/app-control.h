#pragma once
#import <Foundation/Foundation.h>

typedef struct {
    char bundleId[256];
    char name[256];
    int  pid;
} AppInfo;

void        c_app_run(const char *bundle_id);
void        c_app_kill(const char *bundle_id);
void        c_app_kill_all(void);
void        c_clear_switcher(void);
const char *c_get_front_app(void);           // returns static buffer, valid until next call

// Returns heap-allocated array; caller frees. count set to length.
AppInfo    *c_get_running_apps(int *count);
