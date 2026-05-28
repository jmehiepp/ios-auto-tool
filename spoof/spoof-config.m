#import "spoof-config.h"

@interface SpoofConfig ()
@property (nonatomic, strong) NSMutableDictionary *config;
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@implementation SpoofConfig

+ (instancetype)shared {
    static SpoofConfig *s;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [SpoofConfig new]; });
    return s;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _queue = dispatch_queue_create("com.iosautotool.spoof", DISPATCH_QUEUE_CONCURRENT);
    _config = [NSMutableDictionary dictionary];
    [self reload];
    // Watch config file for realtime changes
    dispatch_async(dispatch_get_global_queue(0, 0), ^{ [self watchConfig]; });
    return self;
}

- (void)reload {
    NSData *data = [NSData dataWithContentsOfFile:SPOOF_CONFIG_PATH];
    if (!data) return;
    NSDictionary *parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (!parsed) return;
    dispatch_barrier_async(_queue, ^{
        [self->_config removeAllObjects];
        [self->_config addEntriesFromDictionary:parsed];
    });
}

- (void)watchConfig {
    int fd = open(SPOOF_CONFIG_PATH.UTF8String, O_EVTONLY);
    if (fd < 0) return;
    dispatch_source_t src = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, fd,
        DISPATCH_VNODE_WRITE | DISPATCH_VNODE_RENAME | DISPATCH_VNODE_ATTRIB,
        dispatch_get_global_queue(0, 0));
    dispatch_source_set_event_handler(src, ^{ [self reload]; });
    dispatch_source_set_cancel_handler(src, ^{ close(fd); });
    dispatch_resume(src);
}

- (NSDictionary *)_entry:(NSString *)module {
    __block NSDictionary *entry;
    dispatch_sync(_queue, ^{ entry = self->_config[module]; });
    return entry;
}

- (BOOL)isEnabled:(NSString *)module {
    NSDictionary *e = [self _entry:module];
    return [e[@"enabled"] boolValue];
}

- (NSString *)getString:(NSString *)module {
    NSDictionary *e = [self _entry:module];
    if (![e[@"enabled"] boolValue]) return nil;
    id v = e[@"value"];
    return [v isKindOfClass:[NSString class]] ? v : nil;
}

- (NSNumber *)getNumber:(NSString *)module {
    NSDictionary *e = [self _entry:module];
    if (![e[@"enabled"] boolValue]) return nil;
    id v = e[@"value"];
    return [v isKindOfClass:[NSNumber class]] ? v : nil;
}

- (NSDictionary *)getDict:(NSString *)module {
    NSDictionary *e = [self _entry:module];
    if (![e[@"enabled"] boolValue]) return nil;
    id v = e[@"value"];
    return [v isKindOfClass:[NSDictionary class]] ? v : nil;
}

- (void)setEnabled:(BOOL)enabled forModule:(NSString *)module {
    dispatch_barrier_async(_queue, ^{
        NSMutableDictionary *e = [self->_config[module] mutableCopy] ?: [NSMutableDictionary dictionary];
        e[@"enabled"] = @(enabled);
        self->_config[module] = e;
    });
    [self _persist];
}

- (void)setValue:(id)value forModule:(NSString *)module {
    dispatch_barrier_async(_queue, ^{
        NSMutableDictionary *e = [self->_config[module] mutableCopy] ?: [NSMutableDictionary dictionary];
        e[@"enabled"] = @YES;
        e[@"value"] = value ?: [NSNull null];
        self->_config[module] = e;
    });
    [self _persist];
}

- (void)reset {
    dispatch_barrier_async(_queue, ^{ [self->_config removeAllObjects]; });
    [[NSFileManager defaultManager] removeItemAtPath:SPOOF_CONFIG_PATH error:nil];
}

- (void)_persist {
    __block NSDictionary *snapshot;
    dispatch_sync(_queue, ^{ snapshot = [self->_config copy]; });
    NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:NSJSONWritingPrettyPrinted error:nil];
    [data writeToFile:SPOOF_CONFIG_PATH atomically:YES];
}

@end
