#import "../spoof-config.h"
#import <CoreMotion/CoreMotion.h>
#import <UIKit/UIKit.h>

%hook UIDevice
- (float)batteryLevel {
    NSNumber *v = spoof_num(@"battery_level");
    return v ? v.floatValue : %orig;
}
- (UIDeviceBatteryState)batteryState {
    NSNumber *v = spoof_num(@"battery_state");
    return v ? (UIDeviceBatteryState)v.intValue : %orig;
}
- (BOOL)proximityState {
    NSNumber *v = spoof_num(@"proximity");
    return v ? v.boolValue : %orig;
}
%end

%hook CMMotionManager
- (CMAccelerometerData *)accelerometerData {
    NSDictionary *cfg = spoof_dict(@"accelerometer");
    if (!cfg) return %orig;
    // Use real data structure but patch values via KVC on a fresh copy
    CMAccelerometerData *d = %orig;
    if (!d) return d;
    CMAcceleration a = { [cfg[@"x"] doubleValue], [cfg[@"y"] doubleValue], [cfg[@"z"] doubleValue] };
    [d setValue:[NSValue value:&a withObjCType:@encode(CMAcceleration)] forKey:@"acceleration"];
    return d;
}
- (CMGyroData *)gyroData {
    NSDictionary *cfg = spoof_dict(@"gyroscope");
    if (!cfg) return %orig;
    CMGyroData *d = %orig;
    if (!d) return d;
    CMRotationRate r = { [cfg[@"x"] doubleValue], [cfg[@"y"] doubleValue], [cfg[@"z"] doubleValue] };
    [d setValue:[NSValue value:&r withObjCType:@encode(CMRotationRate)] forKey:@"rotationRate"];
    return d;
}
%end
