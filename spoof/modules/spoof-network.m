#import "../spoof-config.h"
#import <CoreTelephony/CTCarrier.h>
#import <SystemConfiguration/CaptiveNetwork.h>

%group IOSATNetwork
%hook CTCarrier
- (NSString *)carrierName { return spoof_str(@"carrier_name") ?: %orig; }
- (NSString *)mobileCountryCode { return spoof_str(@"mcc") ?: %orig; }
- (NSString *)mobileNetworkCode { return spoof_str(@"mnc") ?: %orig; }
- (NSString *)isoCountryCode { return spoof_str(@"iso_country") ?: %orig; }
%end
%hookf(CFDictionaryRef, CNCopyCurrentNetworkInfo, CFStringRef interfaceName) {
    CFDictionaryRef original = %orig(interfaceName);
    NSDictionary *config = spoof_dict(@"wifi");
    // Do not turn an unauthorized/unavailable network result into available data.
    if (!config || !original) return original;
    NSMutableDictionary *result = [(__bridge NSDictionary *)original mutableCopy];
    CFRelease(original);
    if ([config[@"ssid"] isKindOfClass:NSString.class]) {
        result[(__bridge id)kCNNetworkInfoKeySSID] = config[@"ssid"];
        result[(__bridge id)kCNNetworkInfoKeySSIDData] = [config[@"ssid"] dataUsingEncoding:NSUTF8StringEncoding];
    }
    if ([config[@"bssid"] isKindOfClass:NSString.class])
        result[(__bridge id)kCNNetworkInfoKeyBSSID] = config[@"bssid"];
    return (CFDictionaryRef)CFBridgingRetain([result copy]);
}
%end
%ctor { @autoreleasepool { if (IOSATShouldInitializeHooks()) { %init(IOSATNetwork); } } }
