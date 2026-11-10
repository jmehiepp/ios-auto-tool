#import "../spoof-config.h"
#import <Foundation/Foundation.h>
#import <math.h>
#import <stdio.h>
#import <stdlib.h>

static void Check(BOOL condition, const char *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
static NSDictionary *Configuration(NSDictionary *modules) {
    return @{@"enabled": @YES, @"selectedApps": @[@"com.example.DeviceProbe"], @"modules": modules};
}
int main(void) {
    @autoreleasepool {
        Check([SPOOF_CONFIG_PATH containsString:@"iosautotool-device-test."], "use isolated test config path");
        Check([SPOOF_FILTER_PATH containsString:@"iosautotool-device-test."], "use isolated test filter path");
        SpoofConfig *config = [SpoofConfig shared];
        [config reset];
        Check(![config.getAll[@"enabled"] boolValue], "master defaults OFF");
        Check(config.selectedApps.count == 0, "whitelist defaults empty");
        Check(!config.shouldApplyInCurrentProcess, "command line test host never qualifies as app");
        Check(![SpoofConfig isApplicationBundleIdentifier:@"com.apple.springboard" bundlePath:@"/System/Library/CoreServices/SpringBoard.app"], "exclude SpringBoard");
        Check(![SpoofConfig isApplicationBundleIdentifier:@"com.example.extension" bundlePath:@"/Apps/Test.app/PlugIns/Extension.appex"], "exclude extensions");
        Check(![SpoofConfig isApplicationBundleIdentifier:@"com.example.daemon" bundlePath:@"/usr/libexec/test"], "exclude daemon paths");
        Check([SpoofConfig isApplicationBundleIdentifier:@"com.example.DeviceProbe" bundlePath:@"/var/containers/Bundle/Application/UUID/DeviceProbe.app"], "allow actual app shape");

        NSMutableDictionary *entry = [@{@"enabled": @YES, @"value": @"Test Phone"} mutableCopy];
        NSMutableDictionary *modules = [@{@"device_name": entry} mutableCopy];
        NSError *error = nil;
        Check([config setConfiguration:Configuration(modules) error:&error], "save valid config/filter");
        entry[@"value"] = @"mutated after validation";
        Check([[config getString:@"device_name"] isEqual:@"Test Phone"], "retain immutable deep snapshot");
        NSDictionary *filter = [NSDictionary dictionaryWithContentsOfFile:SPOOF_FILTER_PATH];
        Check([filter[@"Filter"][@"Bundles"] isEqual:@[@"com.example.DeviceProbe"]], "filter has only selected app");
        Check(!filter[@"Filter"][@"Classes"], "no global UIKit class injection filter");
        [config reload];
        Check([[config getString:@"device_name"] isEqual:@"Test Phone"], "persist/reload plist roundtrip");

        NSArray *invalid = @[
            Configuration(@{@"gps": @{@"enabled": @YES, @"value": @{@"lat": @91, @"lon": @0}}}),
            Configuration(@{@"accelerometer": @{@"enabled": @YES, @"value": @{@"x": @(NAN), @"y": @0, @"z": @0}}}),
            Configuration(@{@"idfv": @{@"enabled": @YES, @"value": @"bad-uuid"}}),
            Configuration(@{@"screen_resolution": @{@"enabled": @YES, @"value": @{@"w": @0, @"h": @100}}}),
            Configuration(@{@"unknown_feature": @{@"enabled": @YES}}),
            @{@"enabled": @YES, @"selectedApps": @[@"com.apple.springboard"], @"modules": @{}},
            @{@"enabled": @"true", @"selectedApps": @[], @"modules": @{}},
            @{@"enabled": @YES, @"selectedApps": @{}, @"modules": @{}},
        ];
        for (NSDictionary *bad in invalid) {
            error = nil;
            Check(![config setConfiguration:bad error:&error] && error != nil, "reject malformed config before effects");
            Check([[config getString:@"device_name"] isEqual:@"Test Phone"], "invalid write preserves previous config");
        }
        dispatch_group_t group = dispatch_group_create();
        dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0);
        dispatch_group_async(group, queue, ^{ for (int i=0;i<20;i++) [config setValue:@"Phone" forModule:@"device_name"]; });
        dispatch_group_async(group, queue, ^{ for (int i=0;i<20;i++) [config setValue:@"vi_VN" forModule:@"locale"]; });
        dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
        Check([config.getAll[@"modules"] count] == 2, "concurrent per-module mutations do not lose other fields");
        [config setMasterEnabled:NO];
        filter = [NSDictionary dictionaryWithContentsOfFile:SPOOF_FILTER_PATH];
        Check([filter[@"Filter"][@"Bundles"] count] == 0, "OFF commits empty injection filter");

        // Simulate a filesystem write error at the filter destination. Config
        // must remain disabled rather than reporting an uninstalled selection.
        [NSFileManager.defaultManager removeItemAtPath:SPOOF_FILTER_PATH error:NULL];
        [NSFileManager.defaultManager createDirectoryAtPath:SPOOF_FILTER_PATH
                              withIntermediateDirectories:YES attributes:nil error:NULL];
        error = nil;
        Check(![config setConfiguration:Configuration(@{}) error:&error], "filter-write failure rejects config commit");
        Check(![config.getAll[@"enabled"] boolValue], "filter-write failure preserves in-memory master OFF");
        NSDictionary *stored = [NSDictionary dictionaryWithContentsOfFile:SPOOF_CONFIG_PATH];
        Check(![stored[@"enabled"] boolValue], "filter-write failure preserves stored master OFF");
        puts("Device config contract tests passed");
    }
    return 0;
}
