#import "../spoof-config.h"
#import <AdSupport/ASIdentifierManager.h>
#import <UIKit/UIKit.h>

%hook ASIdentifierManager
- (NSUUID *)advertisingIdentifier {
    NSString *v = spoof_str(@"idfa");
    return v ? [[NSUUID alloc] initWithUUIDString:v] : %orig;
}
- (BOOL)isAdvertisingTrackingEnabled {
    // Return YES when spoofing to avoid zero-IDFA fallback paths in apps
    if (spoof_on(@"idfa")) return YES;
    return %orig;
}
%end

%hook UIDevice
- (NSUUID *)identifierForVendor {
    NSString *v = spoof_str(@"idfv");
    return v ? [[NSUUID alloc] initWithUUIDString:v] : %orig;
}
%end
