#import "../spoof-config.h"
#import <UIKit/UIKit.h>

%hook UIScreen
- (CGRect)bounds {
    NSDictionary *cfg = spoof_dict(@"screen_resolution");
    if (!cfg) return %orig;
    CGFloat w = [cfg[@"w"] doubleValue];
    CGFloat h = [cfg[@"h"] doubleValue];
    return CGRectMake(0, 0, w, h);
}
- (CGRect)nativeBounds {
    NSDictionary *cfg = spoof_dict(@"screen_resolution");
    if (!cfg) return %orig;
    CGFloat scale = self.nativeScale;
    CGFloat w = [cfg[@"w"] doubleValue] * scale;
    CGFloat h = [cfg[@"h"] doubleValue] * scale;
    return CGRectMake(0, 0, w, h);
}
- (CGFloat)scale {
    NSNumber *v = spoof_num(@"screen_scale");
    return v ? v.doubleValue : %orig;
}
%end
