#import "../spoof-config.h"
#import <UIKit/UIKit.h>
#import <sys/utsname.h>
#import <string.h>

%group IOSATDeviceModel
%hook UIDevice
- (NSString *)model {
    NSString *family = spoof_str(@"device_family");
    if (family) return family;
    NSString *hardware = spoof_str(@"device_model");
    if ([hardware hasPrefix:@"iPhone"]) return @"iPhone";
    if ([hardware hasPrefix:@"iPad"]) return @"iPad";
    return %orig;
}
- (NSString *)systemVersion { return spoof_str(@"ios_version") ?: %orig; }
- (NSString *)name { return spoof_str(@"device_name") ?: %orig; }
%end
%hookf(int, uname, struct utsname *info) {
    int result = %orig(info);
    NSString *hardware = spoof_str(@"device_model");
    if (result == 0 && info && hardware)
        strlcpy(info->machine, hardware.UTF8String, sizeof(info->machine));
    return result;
}
%end
%ctor { @autoreleasepool { if (IOSATShouldInitializeHooks()) { %init(IOSATDeviceModel); } } }
