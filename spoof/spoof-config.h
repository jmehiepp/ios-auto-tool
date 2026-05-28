#pragma once
#import <Foundation/Foundation.h>

#define SPOOF_CONFIG_PATH @"/Library/IOSAutoTool/spoof.json"

@interface SpoofConfig : NSObject
+ (instancetype)shared;
- (BOOL)isEnabled:(NSString *)module;
- (NSString *)getString:(NSString *)module;
- (NSNumber *)getNumber:(NSString *)module;
- (NSDictionary *)getDict:(NSString *)module;
- (void)setEnabled:(BOOL)enabled forModule:(NSString *)module;
- (void)setValue:(id)value forModule:(NSString *)module;
- (void)reset;
- (void)reload;
@end

// Convenience macros for hook files
#define spoof_on(key)      [[SpoofConfig shared] isEnabled:(key)]
#define spoof_str(key)     [[SpoofConfig shared] getString:(key)]
#define spoof_num(key)     [[SpoofConfig shared] getNumber:(key)]
#define spoof_dict(key)    [[SpoofConfig shared] getDict:(key)]
