#import "../spoof-config.h"
#import <CoreLocation/CoreLocation.h>

// Keep CLLocationManager delivery and authorization intact. These accessors only
// change values read by the selected application from a delivered location.
%group IOSATLocation
%hook CLLocation
- (CLLocationCoordinate2D)coordinate {
    NSDictionary *config = spoof_dict(@"gps");
    if (config) return CLLocationCoordinate2DMake([config[@"lat"] doubleValue], [config[@"lon"] doubleValue]);
    return %orig;
}
- (CLLocationDistance)altitude {
    NSDictionary *config = spoof_dict(@"gps");
    return config[@"altitude"] ? [config[@"altitude"] doubleValue] : %orig;
}
- (CLLocationAccuracy)horizontalAccuracy {
    NSNumber *value = spoof_num(@"gps_accuracy");
    if (value) return value.doubleValue;
    NSDictionary *config = spoof_dict(@"gps");
    return config[@"accuracy"] ? [config[@"accuracy"] doubleValue] : %orig;
}
%end
%end
%ctor { @autoreleasepool { if (IOSATShouldInitializeHooks()) { %init(IOSATLocation); } } }
