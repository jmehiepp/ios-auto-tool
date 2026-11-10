#import "../spoof-config.h"
#import "../identity-query.h"
#import <sys/sysctl.h>
#import <substrate.h>
#include <dlfcn.h>
#include <string.h>

static __thread BOOL identity_lookup;
static NSString *IdentityValue(const char *name) {
    if (!name || identity_lookup) return nil;
    NSString *module=nil;
    if (!strcmp(name,"hw.machine") || !strcmp(name,"ProductType")) module=@"device_model";
    else if (!strcmp(name,"kern.osproductversion") || !strcmp(name,"ProductVersion")) module=@"ios_version";
    else if (!strcmp(name,"DeviceName") || !strcmp(name,"UserAssignedDeviceName")) module=@"device_name";
    else if (!strcmp(name,"DeviceClass")) module=@"device_family";
    if (!module) return nil;
    identity_lookup=YES;
    NSString *value=spoof_str(module);
    identity_lookup=NO; return value;
}
static CFTypeRef (*OriginalCopyAnswer)(CFStringRef);
static CFTypeRef CopyAnswer(CFStringRef key) {
    if (key && CFGetTypeID(key)==CFStringGetTypeID()) {
        NSString *value=IdentityValue([(__bridge NSString *)key UTF8String]);
        if (value) return CFBridgingRetain(value);
    }
    return OriginalCopyAnswer ? OriginalCopyAnswer(key) : NULL;
}
%group IOSATIdentityQueries
%hookf(int, sysctlbyname, const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (!newp && newlen==0 && oldlenp) {
        NSString *value=IdentityValue(name);
        if (value) return iat_identity_string_read(value.UTF8String,oldp,oldlenp);
    }
    return %orig;
}
%hookf(int, sysctl, int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (name && namelen==2 && name[0]==CTL_HW && name[1]==HW_MACHINE && !newp && newlen==0 && oldlenp) {
        NSString *value=IdentityValue("hw.machine");
        if (value) return iat_identity_string_read(value.UTF8String,oldp,oldlenp);
    }
    return %orig;
}
%end
%ctor {
    @autoreleasepool {
        if (IOSATShouldInitializeHooks()) {
            %init(IOSATIdentityQueries);
            // Public entry point only; no inferred offsets into another image.
            void *library=dlopen("/usr/lib/libMobileGestalt.dylib",RTLD_LAZY);
            void *answer=library ? dlsym(library,"MGCopyAnswer") : NULL;
            if (answer) MSHookFunction(answer,(void *)CopyAnswer,(void **)&OriginalCopyAnswer);
        }
    }
}
