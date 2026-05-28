#import "../spoof-config.h"
#import <CoreLocation/CoreLocation.h>

%hook CLLocationManager
- (void)startUpdatingLocation {
    NSDictionary *cfg = spoof_dict(@"gps");
    if (!cfg) { %orig; return; }
    double lat = [cfg[@"lat"] doubleValue];
    double lon = [cfg[@"lon"] doubleValue];
    double acc = cfg[@"accuracy"] ? [cfg[@"accuracy"] doubleValue] : 10.0;
    CLLocation *fake = [[CLLocation alloc]
        initWithCoordinate:CLLocationCoordinate2DMake(lat, lon)
                  altitude:cfg[@"altitude"] ? [cfg[@"altitude"] doubleValue] : 0.0
        horizontalAccuracy:acc
          verticalAccuracy:acc
                 timestamp:[NSDate date]];
    id<CLLocationManagerDelegate> delegate = self.delegate;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{
        if ([delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)])
            [delegate locationManager:self didUpdateLocations:@[fake]];
    });
}
- (void)requestWhenInUseAuthorization { %orig; }
- (void)requestAlwaysAuthorization    { %orig; }
%end

%hook CLLocation
- (CLLocationAccuracy)horizontalAccuracy {
    NSNumber *v = spoof_num(@"gps_accuracy");
    return v ? v.doubleValue : %orig;
}
%end
