#import "../spoof-config.h"
#import <CoreMotion/CoreMotion.h>
#import <UIKit/UIKit.h>

%group IOSATSensors
%hook UIDevice
- (float)batteryLevel { NSNumber *v = spoof_num(@"battery_level"); return v ? v.floatValue : %orig; }
- (UIDeviceBatteryState)batteryState { NSNumber *v = spoof_num(@"battery_state"); return v ? (UIDeviceBatteryState)v.integerValue : %orig; }
- (BOOL)proximityState { NSNumber *v = spoof_num(@"proximity"); return v ? v.boolValue : %orig; }
%end
// Typed value getters work for both polling and delivered sample objects. Never
// mutate Apple's read-only private ivars with KVC or invent availability/permission.
%hook CMAccelerometerData
- (CMAcceleration)acceleration {
    NSDictionary *v = spoof_dict(@"accelerometer");
    if (v) return (CMAcceleration){[v[@"x"] doubleValue], [v[@"y"] doubleValue], [v[@"z"] doubleValue]};
    return %orig;
}
%end
%hook CMGyroData
- (CMRotationRate)rotationRate {
    NSDictionary *v = spoof_dict(@"gyroscope");
    if (v) return (CMRotationRate){[v[@"x"] doubleValue], [v[@"y"] doubleValue], [v[@"z"] doubleValue]};
    return %orig;
}
%end
%end
%ctor { @autoreleasepool { if (IOSATShouldInitializeHooks()) { %init(IOSATSensors); } } }
