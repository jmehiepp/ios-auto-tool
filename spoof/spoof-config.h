#pragma once
#import <Foundation/Foundation.h>
#if defined(IOSAT_ROOTHIDE)
#import <roothide.h>
#endif

#ifndef SPOOF_CONFIG_PATH
#if defined(IOSAT_ROOTHIDE)
#define SPOOF_CONFIG_PATH jbroot(@"/var/mobile/Library/Preferences/com.iosautotool.device.plist")
#else
#define SPOOF_CONFIG_PATH @"/var/mobile/Library/Preferences/com.iosautotool.device.plist"
#endif
#endif
#ifndef SPOOF_FILTER_PATH
#if defined(IOSAT_ROOTHIDE)
#define SPOOF_FILTER_PATH jbroot(@"/Library/MobileSubstrate/DynamicLibraries/iosautotool-spoof.plist")
#elif defined(IOSAT_ROOTLESS) || defined(ROOTLESS)
#define SPOOF_FILTER_PATH @"/var/jb/Library/MobileSubstrate/DynamicLibraries/iosautotool-spoof.plist"
#else
#define SPOOF_FILTER_PATH @"/Library/MobileSubstrate/DynamicLibraries/iosautotool-spoof.plist"
#endif
#endif
#define SPOOF_CONFIG_NOTIFICATION CFSTR("com.iosautotool.device.configuration-changed")

@interface SpoofConfig : NSObject
+ (instancetype)shared;
- (BOOL)isEnabled:(NSString *)module;
- (NSString *)getString:(NSString *)module;
- (NSNumber *)getNumber:(NSString *)module;
- (NSDictionary *)getDict:(NSString *)module;
- (NSDictionary *)getAll;
- (NSArray<NSString *> *)selectedApps;
- (void)setSelectedApps:(NSArray<NSString *> *)bundleIDs;
- (void)setMasterEnabled:(BOOL)enabled;
- (BOOL)shouldApplyInCurrentProcess;
+ (BOOL)isApplicationBundleIdentifier:(NSString *)bundleID bundlePath:(NSString *)path;
+ (BOOL)validateConfiguration:(NSDictionary *)configuration error:(NSError **)error;
- (BOOL)setConfiguration:(NSDictionary *)configuration error:(NSError **)error;
- (void)setEnabled:(BOOL)enabled forModule:(NSString *)module;
- (void)setValue:(id)value forModule:(NSString *)module;
- (void)reset;
- (void)reload;
@end

// Convenience macros for hook files
// The daemon/UI reads stored values; every hook also requires the process gate.
#define spoof_on(key)      ([[SpoofConfig shared] shouldApplyInCurrentProcess] && [[SpoofConfig shared] isEnabled:(key)])
#define spoof_str(key)     (spoof_on(key) ? [[SpoofConfig shared] getString:(key)] : nil)
#define spoof_num(key)     (spoof_on(key) ? [[SpoofConfig shared] getNumber:(key)] : nil)
#define spoof_dict(key)    (spoof_on(key) ? [[SpoofConfig shared] getDict:(key)] : nil)

static inline BOOL IOSATShouldInitializeHooks(void) {
    return [[SpoofConfig shared] shouldApplyInCurrentProcess];
}
