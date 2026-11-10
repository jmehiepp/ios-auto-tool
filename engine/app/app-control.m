#import "app-control.h"
#import <objc/message.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdarg.h>
#include <errno.h>
#include <unistd.h>
#include <stdbool.h>

static __thread char app_error[512];
static __thread char front_buffer[256];
static uint32_t (*open_application)(NSString *, NSURL *, NSDictionary *, NSDictionary *, BOOL);
static CFArrayRef (*copy_application_ids)(bool, bool);
static CFStringRef (*copy_front_identifier)(void);

#ifdef IAT_APP_CONTROL_TESTING
extern void *iat_test_app_symbol(const char *name);
extern Class iat_test_app_workspace_class(void);
extern Class iat_test_app_system_service_class(void);
extern int iat_test_app_kill(pid_t pid, int signal_number);
#define app_kill_process iat_test_app_kill
#else
#define app_kill_process kill
#endif

static BOOL app_fail(const char *format, ...) {
    va_list args; va_start(args, format);
    vsnprintf(app_error, sizeof(app_error), format, args);
    va_end(args); return NO;
}
const char *c_app_last_error(void) { return app_error; }

BOOL c_app_valid_bundle_id(const char *identifier) {
    if (!identifier) return NO;
    size_t length = strnlen(identifier, 256);
    if (!length || length > 255) return NO;
    BOOL dot = NO, component_start = YES;
    for (size_t i = 0; i < length; i++) {
        unsigned char c = (unsigned char)identifier[i];
        BOOL alnum = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9');
        if (c == '.') {
            if (component_start || identifier[i - 1] == '-') return NO;
            dot = YES; component_start = YES;
        } else {
            if ((!alnum && c != '-') || (component_start && !alnum)) return NO;
            component_start = NO;
        }
    }
    return dot && !component_start && identifier[length - 1] != '-';
}

static void load_symbols(void) {
#ifdef IAT_APP_CONTROL_TESTING
    open_application = iat_test_app_symbol("SBSLaunchApplicationWithIdentifierAndURLAndLaunchOptions");
    copy_application_ids = iat_test_app_symbol("SBSCopyApplicationDisplayIdentifiers");
    copy_front_identifier = iat_test_app_symbol("SBSCopyFrontmostApplicationDisplayIdentifier");
#else
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *framework = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY | RTLD_LOCAL);
        if (framework) {
            open_application = dlsym(framework, "SBSLaunchApplicationWithIdentifierAndURLAndLaunchOptions");
            copy_application_ids = dlsym(framework, "SBSCopyApplicationDisplayIdentifiers");
            copy_front_identifier = dlsym(framework, "SBSCopyFrontmostApplicationDisplayIdentifier");
        }
        // Keep framework handles loaded for the lifetime of these pointers/classes.
        dlopen("/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices", RTLD_LAZY | RTLD_LOCAL);
        dlopen("/System/Library/PrivateFrameworks/LaunchServices.framework/LaunchServices", RTLD_LAZY | RTLD_LOCAL);
        dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_LAZY | RTLD_LOCAL);
    });
#endif
}

static BOOL lookup_pid(NSString *identifier, pid_t *output) {
#ifdef IAT_APP_CONTROL_TESTING
    Class cls = iat_test_app_system_service_class();
#else
    Class cls = NSClassFromString(@"FBSSystemService");
#endif
    SEL shared = sel_registerName("sharedService");
    SEL lookup = sel_registerName("pidForApplication:");
    @try {
        if (![cls respondsToSelector:shared]) return app_fail("App process lookup API is unavailable");
        id service = ((id (*)(id, SEL))objc_msgSend)(cls, shared);
        if (![service respondsToSelector:lookup]) return app_fail("App process lookup API is unavailable");
        *output = ((pid_t (*)(id, SEL, NSString *))objc_msgSend)(service, lookup, identifier);
        if (*output < 0) return app_fail("App process lookup failed");
        return YES;
    } @catch (NSException *exception) {
        return app_fail("App process lookup failed: %s", exception.reason.UTF8String ?: "exception");
    }
}

BOOL c_app_run(const char *bundle_id) {
    app_error[0] = 0;
    if (!c_app_valid_bundle_id(bundle_id)) return app_fail("Invalid bundle identifier");
    load_symbols();
    NSString *identifier = @(bundle_id);
#ifdef IAT_APP_CONTROL_TESTING
    Class workspace_class = iat_test_app_workspace_class();
#else
    Class workspace_class = NSClassFromString(@"LSApplicationWorkspace");
#endif
    @try {
        SEL default_selector = sel_registerName("defaultWorkspace");
        SEL open_selector = sel_registerName("openApplicationWithBundleID:");
        if ([workspace_class respondsToSelector:default_selector]) {
            id workspace = ((id (*)(id, SEL))objc_msgSend)(workspace_class, default_selector);
            if ([workspace respondsToSelector:open_selector]) {
                BOOL accepted = ((BOOL (*)(id, SEL, NSString *))objc_msgSend)(workspace, open_selector, identifier);
                return accepted ? YES : app_fail("LaunchServices rejected launch of %s", bundle_id);
            }
        }
        if (!open_application) return app_fail("App launch API is unavailable on this device");
        uint32_t status = open_application(identifier, nil, @{}, @{}, NO);
        return status == 0 ? YES : app_fail("SpringBoard rejected launch (%u)", status);
    } @catch (NSException *exception) {
        return app_fail("App launch API failed: %s", exception.reason.UTF8String ?: "exception");
    }
}

BOOL c_app_kill(const char *bundle_id) {
    app_error[0] = 0;
    if (!c_app_valid_bundle_id(bundle_id)) return app_fail("Invalid bundle identifier");
    if (!strcmp(bundle_id, "com.apple.springboard")) return app_fail("Refusing to terminate SpringBoard");
    load_symbols();
    pid_t pid = 0;
    if (!lookup_pid(@(bundle_id), &pid)) return NO;
    if (pid == 0) return YES;
    if (pid <= 1 || pid == getpid()) return app_fail("Refusing unsafe app process ID");
    if (app_kill_process(pid, SIGKILL) != 0) {
        if (errno == ESRCH) return YES;
        return app_fail("Could not terminate app: %s", strerror(errno));
    }
    for (int attempt = 0; attempt < 60; attempt++) {
        if (app_kill_process(pid, 0) != 0) {
            if (errno == ESRCH) return YES;
            return app_fail("Could not verify app exit: %s", strerror(errno));
        }
        usleep(50000);
    }
    return app_fail("App did not exit within 3 seconds");
}

AppInfo *c_get_running_apps(int *count) {
    app_error[0] = 0;
    if (!count) { app_fail("Missing app count output"); return NULL; }
    *count = -1;
    load_symbols();
    if (!copy_application_ids) {
        app_fail("Running-app API is unavailable"); return NULL;
    }
    CFArrayRef copied = copy_application_ids(false, false);
    NSArray *identifiers = CFBridgingRelease(copied);
    if (!identifiers || ![identifiers isKindOfClass:NSArray.class]) {
        app_fail("Invalid running-app response"); return NULL;
    }
    if (identifiers.count > 4096) { app_fail("Running-app response exceeded limit"); return NULL; }
    AppInfo *apps = calloc(MAX((NSUInteger)1, identifiers.count), sizeof(AppInfo));
    if (!apps) { app_fail("Out of memory"); return NULL; }
    *count = 0;
    for (id value in identifiers) {
        if (![value isKindOfClass:NSString.class] || !c_app_valid_bundle_id([value UTF8String])) continue;
        pid_t pid = 0;
        if (!lookup_pid(value, &pid)) { free(apps); *count = -1; return NULL; }
        if (pid <= 1 || pid == getpid() || [value isEqualToString:@"com.apple.springboard"]) continue;
        strlcpy(apps[*count].bundleId, [value UTF8String], sizeof(apps[*count].bundleId));
        strlcpy(apps[*count].name, [value UTF8String], sizeof(apps[*count].name));
        apps[*count].pid = pid;
        (*count)++;
    }
    return apps;
}

BOOL c_app_kill_all(void) {
    int count;
    AppInfo *apps = c_get_running_apps(&count);
    if (count < 0) return NO;
    for (int index = 0; index < count; index++) {
        if (!c_app_kill(apps[index].bundleId)) { free(apps); return NO; }
    }
    free(apps); return YES;
}

BOOL c_clear_switcher(void) {
    app_error[0] = 0;
    // Daemon cannot prove a SpringBoard UI controller mutation succeeded. Do not
    // edit SpringBoard preferences as a silent fallback or claim kill-all clears recents.
    return app_fail("Clearing switcher UI is not supported from the daemon");
}

const char *c_get_front_app(void) {
    app_error[0] = 0; front_buffer[0] = 0;
    load_symbols();
    if (!copy_front_identifier) { app_fail("Foreground-app API is unavailable"); return NULL; }
    NSString *identifier = CFBridgingRelease(copy_front_identifier());
    if (!identifier) return front_buffer;
    if (![identifier isKindOfClass:NSString.class] || !c_app_valid_bundle_id(identifier.UTF8String)) {
        app_fail("Invalid foreground-app response"); return NULL;
    }
    strlcpy(front_buffer, identifier.UTF8String, sizeof(front_buffer));
    return front_buffer;
}
