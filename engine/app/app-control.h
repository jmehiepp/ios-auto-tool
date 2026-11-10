#pragma once
#import <Foundation/Foundation.h>

typedef struct {
    char bundleId[256];
    char name[256];
    int  pid;
} AppInfo;

BOOL        c_app_valid_bundle_id(const char *bundle_id);
const char *c_app_last_error(void);          // thread-local; copied before the next app call
BOOL        c_app_run(const char *bundle_id);
BOOL        c_app_kill(const char *bundle_id); // success includes already stopped; waits for exit
BOOL        c_app_kill_all(void);
BOOL        c_clear_switcher(void);
const char *c_get_front_app(void);            // thread-local; NULL on error, empty if none

// Returns heap-allocated array; caller frees. count is -1 on error, 0 if empty.
AppInfo    *c_get_running_apps(int *count);
