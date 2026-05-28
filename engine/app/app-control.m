#import "app-control.h"
#import <Foundation/Foundation.h>
#import <signal.h>
#import <stdlib.h>
#import <string.h>

// SpringBoardServices private API declarations
extern int SBSOpenApplicationWithBundleID(CFStringRef bundleID);
extern pid_t SBSProcessIDForDisplayIdentifier(CFStringRef identifier);
extern CFArrayRef SBSCopyApplicationDisplayIdentifiers(bool onlyFrontmost, bool notSuspended);
extern CFStringRef SBSCopyFrontmostApplicationDisplayIdentifier(void);

void c_app_run(const char *bundle_id) {
    if (!bundle_id) return;
    CFStringRef bid = CFStringCreateWithCString(kCFAllocatorDefault,
                                                bundle_id,
                                                kCFStringEncodingUTF8);
    // LSApplicationWorkspace is more reliable on iOS 15+
    id workspace = [NSClassFromString(@"LSApplicationWorkspace") performSelector:
                    @selector(defaultWorkspace)];
    if (workspace) {
        [workspace performSelector:@selector(openApplicationWithBundleID:)
                        withObject:(__bridge NSString *)bid];
    } else {
        SBSOpenApplicationWithBundleID(bid);
    }
    CFRelease(bid);
}

void c_app_kill(const char *bundle_id) {
    if (!bundle_id) return;
    CFStringRef bid = CFStringCreateWithCString(kCFAllocatorDefault,
                                                bundle_id,
                                                kCFStringEncodingUTF8);
    pid_t pid = SBSProcessIDForDisplayIdentifier(bid);
    CFRelease(bid);
    if (pid > 0) kill(pid, SIGKILL);
}

void c_app_kill_all(void) {
    CFArrayRef ids = SBSCopyApplicationDisplayIdentifiers(false, false);
    if (!ids) return;
    CFIndex n = CFArrayGetCount(ids);
    for (CFIndex i = 0; i < n; i++) {
        CFStringRef bid = (CFStringRef)CFArrayGetValueAtIndex(ids, i);
        pid_t pid = SBSProcessIDForDisplayIdentifier(bid);
        if (pid > 0) kill(pid, SIGKILL);
    }
    CFRelease(ids);
}

void c_clear_switcher(void) {
    // iOS 15+: kill SpringBoard's notion of recent apps via private API
    id ctrl = [NSClassFromString(@"SBUIController") performSelector:@selector(sharedInstance)];
    if ([ctrl respondsToSelector:@selector(clearMultitaskingApp:)]) {
        [ctrl performSelector:@selector(clearMultitaskingApp:) withObject:nil];
    }
    // Fallback: remove recent apps plist
    NSString *plist = @"/var/mobile/Library/Preferences/com.apple.springboard.plist";
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithContentsOfFile:plist];
    [d removeObjectForKey:@"SBRecentApplications"];
    [d writeToFile:plist atomically:YES];
}

const char *c_get_front_app(void) {
    static char buf[256];
    CFStringRef bid = SBSCopyFrontmostApplicationDisplayIdentifier();
    if (!bid) { buf[0] = '\0'; return buf; }
    CFStringGetCString(bid, buf, sizeof(buf), kCFStringEncodingUTF8);
    CFRelease(bid);
    return buf;
}

AppInfo *c_get_running_apps(int *count) {
    *count = 0;
    CFArrayRef ids = SBSCopyApplicationDisplayIdentifiers(false, false);
    if (!ids) return NULL;

    CFIndex n = CFArrayGetCount(ids);
    AppInfo *arr = calloc((size_t)n, sizeof(AppInfo));
    if (!arr) { CFRelease(ids); return NULL; }

    // LSApplicationProxy for display name
    id proxy_class = NSClassFromString(@"LSApplicationProxy");
    for (CFIndex i = 0; i < n; i++) {
        CFStringRef bid = (CFStringRef)CFArrayGetValueAtIndex(ids, i);
        CFStringGetCString(bid, arr[*count].bundleId,
                           sizeof(arr[*count].bundleId), kCFStringEncodingUTF8);

        pid_t pid = SBSProcessIDForDisplayIdentifier(bid);
        arr[*count].pid = (int)pid;

        if (proxy_class) {
            id proxy = [proxy_class performSelector:
                        @selector(applicationProxyForIdentifier:)
                        withObject:(__bridge NSString *)bid];
            NSString *name = [proxy performSelector:@selector(localizedName)];
            if (name) strncpy(arr[*count].name, name.UTF8String,
                              sizeof(arr[*count].name) - 1);
        }
        (*count)++;
    }
    CFRelease(ids);
    return arr;
}
