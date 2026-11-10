#import "../spoof-config.h"
#import <Foundation/Foundation.h>

%group IOSATTimeZone
%hook NSTimeZone
+ (NSTimeZone *)localTimeZone {
    NSString *value = spoof_str(@"timezone");
    NSTimeZone *configured = value ? [NSTimeZone timeZoneWithName:value] : nil;
    return configured ?: %orig;
}
+ (NSTimeZone *)systemTimeZone {
    NSString *value = spoof_str(@"timezone");
    NSTimeZone *configured = value ? [NSTimeZone timeZoneWithName:value] : nil;
    return configured ?: %orig;
}
%end
%end
%ctor { @autoreleasepool { if (IOSATShouldInitializeHooks()) { %init(IOSATTimeZone); } } }
