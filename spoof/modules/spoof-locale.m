#import "../spoof-config.h"
#import <Foundation/Foundation.h>

%group IOSATLocale
%hook NSLocale
+ (NSLocale *)currentLocale {
    NSString *value = spoof_str(@"locale");
    return value ? [NSLocale localeWithLocaleIdentifier:value] : %orig;
}
+ (NSLocale *)autoupdatingCurrentLocale {
    NSString *value = spoof_str(@"locale");
    return value ? [NSLocale localeWithLocaleIdentifier:value] : %orig;
}
+ (NSArray<NSString *> *)preferredLanguages {
    NSString *value = spoof_str(@"locale");
    if (!value) return %orig;
    NSString *language = [NSLocale canonicalLanguageIdentifierFromString:value];
    return language.length ? @[language] : %orig;
}
%end
%end
%ctor { @autoreleasepool { if (IOSATShouldInitializeHooks()) { %init(IOSATLocale); } } }
