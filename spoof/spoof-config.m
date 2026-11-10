#import "spoof-config.h"
#import <CoreFoundation/CoreFoundation.h>
#import <math.h>
#import <sys/file.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>

static NSDictionary *Defaults(void) {
    return @{@"enabled": @NO, @"selectedApps": @[], @"modules": @{}};
}
static BOOL Fail(NSError **error, NSString *message) {
    if (error) *error = [NSError errorWithDomain:@"IOSAutoTool.Device" code:1
                                      userInfo:@{NSLocalizedDescriptionKey: message}];
    return NO;
}
static BOOL Number(id value) {
    return [value isKindOfClass:NSNumber.class] && isfinite([value doubleValue]);
}
static BOOL Boolean(id value) {
    return Number(value) && ([value doubleValue] == 0 || [value doubleValue] == 1);
}
static BOOL String(id value, NSUInteger limit) {
    return [value isKindOfClass:NSString.class] && [value length] > 0 && [value length] <= limit;
}
static BOOL BundleID(id value) {
    if (!String(value, 255) || [value rangeOfString:@"."].location == NSNotFound) return NO;
    NSCharacterSet *bad = [[NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"] invertedSet];
    return [value rangeOfCharacterFromSet:bad].location == NSNotFound;
}
static BOOL Range(id value, double low, double high) {
    return Number(value) && [value doubleValue] >= low && [value doubleValue] <= high;
}
static NSSet *ExcludedBundles(void) {
    static NSSet *excluded;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ excluded = [NSSet setWithArray:@[@"com.apple.springboard", @"com.apple.backboardd",
        @"com.apple.frontboard", @"com.apple.runningboardd", @"com.apple.WebKit.WebContent",
        @"com.apple.WebKit.Networking", @"com.apple.WebKit.GPU"]]; });
    return excluded;
}
static NSSet *ModuleNames(void) {
    static NSSet *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ names = [NSSet setWithArray:@[@"device_model", @"device_family", @"ios_version",
        @"device_name", @"idfa", @"idfv", @"carrier_name", @"mcc", @"mnc", @"iso_country", @"locale",
        @"timezone", @"user_agent", @"webgl_vendor", @"webgl_renderer", @"screen_scale", @"screen_resolution",
        @"battery_level", @"battery_state", @"proximity", @"gps", @"gps_accuracy", @"wifi", @"app_list",
        @"accelerometer", @"gyroscope", @"canvas"]]; });
    return names;
}
static BOOL ValidValue(NSString *name, id value) {
    NSSet *strings = [NSSet setWithArray:@[@"device_model", @"device_family", @"ios_version", @"device_name",
        @"carrier_name", @"mcc", @"mnc", @"iso_country", @"locale", @"user_agent", @"webgl_vendor", @"webgl_renderer"]];
    if ([strings containsObject:name]) return String(value, [name isEqual:@"user_agent"] ? 2048 : 256);
    if ([name isEqual:@"timezone"]) return String(value, 128) && [NSTimeZone timeZoneWithName:value] != nil;
    if ([name isEqual:@"idfa"] || [name isEqual:@"idfv"])
        return String(value, 36) && [[NSUUID alloc] initWithUUIDString:value] != nil;
    if ([name isEqual:@"screen_scale"]) return Range(value, 0.25, 8);
    if ([name isEqual:@"battery_level"]) return Range(value, -1, 1);
    if ([name isEqual:@"battery_state"]) return Range(value, 0, 3) && [value doubleValue] == [value integerValue];
    if ([name isEqual:@"proximity"] || [name isEqual:@"canvas"]) return Boolean(value);
    if ([name isEqual:@"gps_accuracy"]) return Range(value, 0, 1000000);
    if (![value isKindOfClass:NSDictionary.class]) return NO;
    NSDictionary *v = value;
    if ([name isEqual:@"screen_resolution"])
        return Range(v[@"w"], 1, 16384) && Range(v[@"h"], 1, 16384) && (!v[@"scale"] || Range(v[@"scale"], 0.25, 8));
    if ([name isEqual:@"gps"])
        return Range(v[@"lat"], -90, 90) && Range(v[@"lon"], -180, 180) &&
               (!v[@"accuracy"] || Range(v[@"accuracy"], 0, 1000000)) && (!v[@"altitude"] || Number(v[@"altitude"]));
    if ([name isEqual:@"accelerometer"] || [name isEqual:@"gyroscope"])
        return Number(v[@"x"]) && Number(v[@"y"]) && Number(v[@"z"]);
    if ([name isEqual:@"wifi"])
        return (v[@"ssid"] || v[@"bssid"]) && (!v[@"ssid"] || String(v[@"ssid"], 32)) &&
               (!v[@"bssid"] || String(v[@"bssid"], 64));
    if ([name isEqual:@"app_list"]) {
        if (![v[@"hide"] isKindOfClass:NSArray.class] || [v[@"hide"] count] > 1000) return NO;
        for (id bundle in v[@"hide"]) if (!BundleID(bundle)) return NO;
        return YES;
    }
    return NO;
}

@interface SpoofConfig ()
@property(nonatomic, strong) NSDictionary *configuration;
@property(nonatomic, strong) dispatch_queue_t queue;
@property(nonatomic, strong) dispatch_source_t reloadTimer;
@end
static void ConfigChanged(CFNotificationCenterRef center, void *observer, CFStringRef name,
                          const void *object, CFDictionaryRef info) {
    (void)center; (void)name; (void)object; (void)info;
    @autoreleasepool { [(__bridge SpoofConfig *)observer reload]; }
}
@implementation SpoofConfig
+ (instancetype)shared {
    static SpoofConfig *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [self new]; });
    return instance;
}
- (instancetype)init {
    if (!(self = [super init])) return nil;
    _queue = dispatch_queue_create("com.iosautotool.device.configuration", DISPATCH_QUEUE_SERIAL);
    _configuration = Defaults();
    [self reload];
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self,
        ConfigChanged, SPOOF_CONFIG_NOTIFICATION, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    // Atomic file replacement invalidates vnode watches; retain a timer to also
    // notice manual edits/removal. Read failures restore the OFF defaults.
    _reloadTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                         dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    dispatch_source_set_timer(_reloadTimer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC),
                              NSEC_PER_SEC, NSEC_PER_SEC / 5);
    __weak SpoofConfig *weakSelf = self;
    dispatch_source_set_event_handler(_reloadTimer, ^{ @autoreleasepool { [weakSelf reload]; } });
    dispatch_resume(_reloadTimer);
    return self;
}
- (void)dealloc {
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        (__bridge void *)self, SPOOF_CONFIG_NOTIFICATION, NULL);
    if (_reloadTimer) dispatch_source_cancel(_reloadTimer);
}
+ (BOOL)validateConfiguration:(NSDictionary *)configuration error:(NSError **)error {
    if (![configuration isKindOfClass:NSDictionary.class] || !Boolean(configuration[@"enabled"]) ||
        ![configuration[@"selectedApps"] isKindOfClass:NSArray.class] ||
        ![configuration[@"modules"] isKindOfClass:NSDictionary.class])
        return Fail(error, @"Expected enabled:boolean, selectedApps:array, modules:dictionary");
    if ([configuration[@"selectedApps"] count] > 1000 || [configuration[@"modules"] count] > 100)
        return Fail(error, @"Configuration exceeds supported limits");
    for (id bundle in configuration[@"selectedApps"])
        if (!BundleID(bundle) || [ExcludedBundles() containsObject:bundle])
            return Fail(error, @"selectedApps contains an invalid or protected bundle identifier");
    for (id name in configuration[@"modules"]) {
        id entry = configuration[@"modules"][name];
        if (!String(name, 64) || ![ModuleNames() containsObject:name] ||
            ![entry isKindOfClass:NSDictionary.class] || !Boolean(entry[@"enabled"]))
            return Fail(error, @"Invalid or unsupported module entry");
        id value = entry[@"value"];
        if (value && !ValidValue(name, value))
            return Fail(error, [NSString stringWithFormat:@"Invalid module value: %@", name]);
    }
    if (![NSPropertyListSerialization propertyList:configuration isValidForFormat:NSPropertyListBinaryFormat_v1_0])
        return Fail(error, @"Configuration must contain only property-list values");
    return YES;
}
+ (BOOL)isApplicationBundleIdentifier:(NSString *)bundleID bundlePath:(NSString *)path {
    if (!BundleID(bundleID) || ![path isKindOfClass:NSString.class] ||
        ![[path pathExtension] isEqualToString:@"app"]) return NO;
    return ![ExcludedBundles() containsObject:bundleID] &&
        [path rangeOfString:@".appex/"].location == NSNotFound &&
        [path rangeOfString:@"/PlugIns/"].location == NSNotFound;
}
- (BOOL)shouldApplyInCurrentProcess {
    NSBundle *bundle = NSBundle.mainBundle;
    NSString *bundleID = bundle.bundleIdentifier;
    if (![[self class] isApplicationBundleIdentifier:bundleID bundlePath:bundle.bundlePath]) return NO;
    NSDictionary *config = [self getAll];
    return [config[@"enabled"] boolValue] && [config[@"selectedApps"] containsObject:bundleID];
}
- (void)reload {
    @synchronized (self) {
    NSDictionary *read = [NSDictionary dictionaryWithContentsOfFile:SPOOF_CONFIG_PATH];
    NSDictionary *next = [[self class] validateConfiguration:read error:NULL] ? read : Defaults();
    dispatch_sync(_queue, ^{ self->_configuration = next; });
    }
}
- (NSDictionary *)getAll {
    __block NSDictionary *result;
    dispatch_sync(_queue, ^{ result = self->_configuration; });
    return result;
}
- (NSArray<NSString *> *)selectedApps { return [self getAll][@"selectedApps"]; }
- (NSDictionary *)entry:(NSString *)module { return module ? [self getAll][@"modules"][module] : nil; }
- (BOOL)isEnabled:(NSString *)module { return [[self entry:module][@"enabled"] boolValue]; }
- (id)value:(NSString *)module class:(Class)type {
    NSDictionary *entry = [self entry:module];
    id value = entry[@"value"];
    return [entry[@"enabled"] boolValue] && [value isKindOfClass:type] ? value : nil;
}
- (NSString *)getString:(NSString *)module { return [self value:module class:NSString.class]; }
- (NSNumber *)getNumber:(NSString *)module { return [self value:module class:NSNumber.class]; }
- (NSDictionary *)getDict:(NSString *)module { return [self value:module class:NSDictionary.class]; }
- (BOOL)setConfiguration:(NSDictionary *)configuration error:(NSError **)error {
    @synchronized (self) {
    if (![[self class] validateConfiguration:configuration error:error]) return NO;
#ifndef IOSAT_DEVICE_TESTING
    if (geteuid() != 0) return Fail(error, @"Device configuration must be saved by the root daemon");
#endif
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:configuration
        format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    if (!data) return NO;
    NSDictionary *snapshot = [NSPropertyListSerialization propertyListWithData:data
        options:NSPropertyListImmutable format:NULL error:error];
    NSString *directory = [SPOOF_CONFIG_PATH stringByDeletingLastPathComponent];
    if (![[NSFileManager defaultManager] createDirectoryAtPath:directory
          withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    NSString *lockPath = [SPOOF_CONFIG_PATH stringByAppendingString:@".lock"];
    int fd = open(lockPath.fileSystemRepresentation, O_CREAT | O_RDWR, 0600);
    if (fd < 0) return Fail(error, @"Cannot lock device configuration");
    if (flock(fd, LOCK_EX) != 0) { close(fd); return Fail(error, @"Cannot lock device configuration"); }
    NSArray *bundles = [snapshot[@"enabled"] boolValue] ? snapshot[@"selectedApps"] : @[];
    NSDictionary *filter = @{@"Filter": @{@"Bundles": bundles}};
    NSData *filterData = [NSPropertyListSerialization dataWithPropertyList:filter
        format:NSPropertyListXMLFormat_v1_0 options:0 error:error];
    NSString *filterDirectory = [SPOOF_FILTER_PATH stringByDeletingLastPathComponent];
    BOOL ok = filterData && [[NSFileManager defaultManager] createDirectoryAtPath:filterDirectory
        withIntermediateDirectories:YES attributes:nil error:error] &&
        [filterData writeToFile:SPOOF_FILTER_PATH options:NSDataWritingAtomic error:error];
    if (ok) {
        chmod(SPOOF_FILTER_PATH.fileSystemRepresentation, 0644);
        ok = [data writeToFile:SPOOF_CONFIG_PATH options:NSDataWritingAtomic error:error];
    }
    if (ok) {
        chmod(SPOOF_CONFIG_PATH.fileSystemRepresentation, 0644);
        dispatch_sync(_queue, ^{ self->_configuration = snapshot; });
    }
    flock(fd, LOCK_UN);
    close(fd);
    if (ok) CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                 SPOOF_CONFIG_NOTIFICATION, NULL, NULL, true);
    return ok;
    }
}
- (void)setMasterEnabled:(BOOL)enabled {
    @synchronized (self) {
    NSMutableDictionary *next = [[self getAll] mutableCopy];
    next[@"enabled"] = @(enabled);
    [self setConfiguration:next error:NULL];
    }
}
- (void)setSelectedApps:(NSArray<NSString *> *)bundleIDs {
    @synchronized (self) {
    NSMutableDictionary *next = [[self getAll] mutableCopy];
    next[@"selectedApps"] = bundleIDs ?: @[];
    [self setConfiguration:next error:NULL];
    }
}
- (void)setEnabled:(BOOL)enabled forModule:(NSString *)module {
    @synchronized (self) {
    if (!module) return;
    NSMutableDictionary *next = [[self getAll] mutableCopy];
    NSMutableDictionary *modules = [next[@"modules"] mutableCopy];
    NSMutableDictionary *entry = [modules[module] mutableCopy] ?: [NSMutableDictionary dictionary];
    entry[@"enabled"] = @(enabled);
    modules[module] = entry;
    next[@"modules"] = modules;
    [self setConfiguration:next error:NULL];
    }
}
- (void)setValue:(id)value forModule:(NSString *)module {
    @synchronized (self) {
    if (!module || !value) return;
    NSMutableDictionary *next = [[self getAll] mutableCopy];
    NSMutableDictionary *modules = [next[@"modules"] mutableCopy];
    modules[module] = @{@"enabled": @YES, @"value": value};
    next[@"modules"] = modules;
    [self setConfiguration:next error:NULL];
    }
}
- (void)reset { [self setConfiguration:Defaults() error:NULL]; }
@end
