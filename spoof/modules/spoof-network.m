#import "../spoof-config.h"
#import <CoreTelephony/CTCarrier.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <SystemConfiguration/CaptiveNetwork.h>

%hook CTCarrier
- (NSString *)carrierName {
    return spoof_str(@"carrier_name") ?: %orig;
}
- (NSString *)mobileCountryCode {
    return spoof_str(@"mcc") ?: %orig;
}
- (NSString *)mobileNetworkCode {
    return spoof_str(@"mnc") ?: %orig;
}
- (NSString *)isoCountryCode {
    return spoof_str(@"iso_country") ?: %orig;
}
%end

// WiFi SSID — hook CNCopyCurrentNetworkInfo
%hookf(CFDictionaryRef, CNCopyCurrentNetworkInfo, CFStringRef interfaceName) {
    NSDictionary *cfg = spoof_dict(@"wifi");
    if (!cfg) return %orig(interfaceName);
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (cfg[@"ssid"])  d[(__bridge id)kCNNetworkInfoKeySSID]     = cfg[@"ssid"];
    if (cfg[@"bssid"]) d[(__bridge id)kCNNetworkInfoKeyBSSID]    = cfg[@"bssid"];
    return (CFDictionaryRef)CFBridgingRetain(d);
}
