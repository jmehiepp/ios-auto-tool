#import "../spoof-config.h"
#import <UIKit/UIKit.h>

static CGFloat ConfiguredScale(CGFloat fallback) {
    NSNumber *standalone = spoof_num(@"screen_scale");
    NSDictionary *resolution = spoof_dict(@"screen_resolution");
    NSNumber *value = standalone ?: resolution[@"scale"];
    return value ? value.doubleValue : fallback;
}
%group IOSATScreen
%hook UIScreen
- (CGRect)bounds {
    CGRect original = %orig;
    if (self != UIScreen.mainScreen) return original;
    NSDictionary *config = spoof_dict(@"screen_resolution");
    return config ? CGRectMake(original.origin.x, original.origin.y, [config[@"w"] doubleValue],
                               [config[@"h"] doubleValue]) : original;
}
- (CGRect)nativeBounds {
    CGRect original = %orig;
    if (self != UIScreen.mainScreen) return original;
    NSDictionary *config = spoof_dict(@"screen_resolution");
    if (!config) return original;
    CGFloat scale = ConfiguredScale(self.nativeScale);
    return CGRectMake(original.origin.x, original.origin.y, [config[@"w"] doubleValue] * scale,
                       [config[@"h"] doubleValue] * scale);
}
- (CGFloat)scale {
    CGFloat original = %orig;
    return self == UIScreen.mainScreen ? ConfiguredScale(original) : original;
}
- (CGFloat)nativeScale {
    CGFloat original = %orig;
    return self == UIScreen.mainScreen ? ConfiguredScale(original) : original;
}
%end
%end
%ctor { @autoreleasepool { if (IOSATShouldInitializeHooks()) { %init(IOSATScreen); } } }
