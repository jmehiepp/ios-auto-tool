#import "../spoof-config.h"
#import <AdSupport/ASIdentifierManager.h>
#import <UIKit/UIKit.h>

%group IOSATIdentifiers
%hook ASIdentifierManager
- (NSUUID *)advertisingIdentifier {
    NSUUID *original = %orig;
    // Preserve the system's denied/zero-IDFA result and all tracking policies.
    if (!original || [original.UUIDString isEqualToString:@"00000000-0000-0000-0000-000000000000"])
        return original;
    NSString *value = spoof_str(@"idfa");
    NSUUID *configured = value ? [[NSUUID alloc] initWithUUIDString:value] : nil;
    return configured ?: original;
}
%end
%hook UIDevice
- (NSUUID *)identifierForVendor {
    NSString *value = spoof_str(@"idfv");
    NSUUID *configured = value ? [[NSUUID alloc] initWithUUIDString:value] : nil;
    return configured ?: %orig;
}
%end
%end
%ctor { @autoreleasepool { if (IOSATShouldInitializeHooks()) { %init(IOSATIdentifiers); } } }
