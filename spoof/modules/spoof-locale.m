#import "../spoof-config.h"
#import <Foundation/Foundation.h>

%hook NSLocale
+ (NSLocale *)currentLocale {
    NSString *v = spoof_str(@"locale");
    return v ? [NSLocale localeWithLocaleIdentifier:v] : %orig;
}
+ (NSLocale *)autoupdatingCurrentLocale {
    NSString *v = spoof_str(@"locale");
    return v ? [NSLocale localeWithLocaleIdentifier:v] : %orig;
}
+ (NSArray<NSString *> *)preferredLanguages {
    NSString *v = spoof_str(@"locale");
    return v ? @[v] : %orig;
}
%end
