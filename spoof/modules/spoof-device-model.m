#import "../spoof-config.h"
#import <UIKit/UIKit.h>
#import <sys/utsname.h>

%hook UIDevice
- (NSString *)model {
    NSString *v = spoof_str(@"device_model");
    return v ?: %orig;
}
- (NSString *)systemVersion {
    NSString *v = spoof_str(@"ios_version");
    return v ?: %orig;
}
- (NSString *)name {
    NSString *v = spoof_str(@"device_name");
    return v ?: %orig;
}
%end

%hookf(int, uname, struct utsname *info) {
    int ret = %orig(info);
    NSString *model = spoof_str(@"device_model");
    if (model) strlcpy(info->machine, model.UTF8String, sizeof(info->machine));
    return ret;
}
