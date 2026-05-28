#import "spoof-license.h"
#import <CommonCrypto/CommonHMAC.h>
#import <sys/utsname.h>
#import <UIKit/UIKit.h>

// Returns device UDID via identifierForVendor (best available without entitlements)
static NSString *get_device_id(void) {
    return [[[UIDevice currentDevice] identifierForVendor] UUIDString] ?: @"";
}

static NSString *hmac_sha256(NSString *key, NSString *data) {
    const char *k = key.UTF8String;
    const char *d = data.UTF8String;
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, k, strlen(k), d, strlen(d), digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++)
        [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

BOOL spoof_license_verify(void) {
    NSString *contents = [NSString stringWithContentsOfFile:LICENSE_KEY_PATH
                                                   encoding:NSUTF8StringEncoding
                                                      error:nil];
    if (!contents.length) return NO;

    // Format: "<key>:<expected_sig>"
    // expected_sig = HMAC-SHA256(secret_server_key, key + ":" + device_id)
    NSArray *parts = [contents.stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]
                      componentsSeparatedByString:@":"];
    if (parts.count < 2) return NO;

    NSString *licenseKey = parts[0];
    NSString *storedSig  = parts[1];
    NSString *deviceId   = get_device_id();

    // Verify: HMAC-SHA256(licenseKey, deviceId) == storedSig
    NSString *computed = hmac_sha256(licenseKey, deviceId);
    return [computed isEqualToString:storedSig];
}
