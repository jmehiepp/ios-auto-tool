#import "../spoof-config.h"
#import <Foundation/Foundation.h>
#import <objc/message.h>

static NSArray *FilteredApplications(NSArray *list) {
    NSArray *hidden = spoof_dict(@"app_list")[@"hide"];
    if (![list isKindOfClass:NSArray.class] || ![hidden isKindOfClass:NSArray.class] || !hidden.count) return list;
    NSSet *identifiers = [NSSet setWithArray:hidden];
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:list.count];
    for (id application in list) {
        SEL selector = NSSelectorFromString(@"applicationIdentifier");
        if (![application respondsToSelector:selector]) selector = NSSelectorFromString(@"bundleIdentifier");
        NSString *identifier = [application respondsToSelector:selector]
            ? ((id (*)(id, SEL))objc_msgSend)(application, selector) : nil;
        if (![identifier isKindOfClass:NSString.class] || ![identifiers containsObject:identifier])
            [result addObject:application];
    }
    return [result copy];
}
%group IOSATAppList
%hook LSApplicationWorkspace
- (NSArray *)allInstalledApplications { return FilteredApplications(%orig); }
- (NSArray *)allApplications { return FilteredApplications(%orig); }
%end
%end
%ctor { @autoreleasepool {
    if (IOSATShouldInitializeHooks() && NSClassFromString(@"LSApplicationWorkspace")) { %init(IOSATAppList); }
} }
