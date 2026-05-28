#import "../spoof-config.h"
#import <Foundation/Foundation.h>

%hook NSTimeZone
+ (NSTimeZone *)localTimeZone {
    NSString *v = spoof_str(@"timezone");
    return v ? [NSTimeZone timeZoneWithName:v] : %orig;
}
+ (NSTimeZone *)systemTimeZone {
    NSString *v = spoof_str(@"timezone");
    return v ? [NSTimeZone timeZoneWithName:v] : %orig;
}
%end
