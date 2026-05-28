#import "../spoof-config.h"
#import <Foundation/Foundation.h>

// LSApplicationWorkspace is a private class — forward-declare
@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray *)allInstalledApplications;
- (NSArray *)allApplications;
@end

%hook LSApplicationWorkspace
- (NSArray *)allInstalledApplications {
    NSArray *list = %orig;
    NSArray *hidden = spoof_dict(@"app_list") ? spoof_dict(@"app_list")[@"hide"] : nil;
    if (!hidden.count) return list;
    NSSet *hideSet = [NSSet setWithArray:hidden];
    return [list filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id app, NSDictionary *b) {
        NSString *bid = [app valueForKey:@"applicationIdentifier"];
        return ![hideSet containsObject:bid];
    }]];
}
- (NSArray *)allApplications {
    NSArray *list = %orig;
    NSArray *hidden = spoof_dict(@"app_list") ? spoof_dict(@"app_list")[@"hide"] : nil;
    if (!hidden.count) return list;
    NSSet *hideSet = [NSSet setWithArray:hidden];
    return [list filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id app, NSDictionary *b) {
        NSString *bid = [app valueForKey:@"applicationIdentifier"];
        return ![hideSet containsObject:bid];
    }]];
}
%end
