#import "../mcp-tools.h"
#import "../../engine/app/app-control.h"
#import <Foundation/Foundation.h>
#include <string.h>

NSDictionary *tool_app_run(NSDictionary *args) {
    NSString *bid = [args[@"bundle_id"] isKindOfClass:NSString.class] ? args[@"bundle_id"] : nil;
    if (!bid.length || strlen(bid.UTF8String) != [bid lengthOfBytesUsingEncoding:NSUTF8StringEncoding]) return mcp_error_result(@"'bundle_id' must be a valid identifier string");
    if (!c_app_run(bid.UTF8String)) return mcp_error_result(@(c_app_last_error()));
    return mcp_text_result([NSString stringWithFormat:@"Launch accepted for %@", bid], NO);
}

NSDictionary *tool_app_kill(NSDictionary *args) {
    NSString *bid = [args[@"bundle_id"] isKindOfClass:NSString.class] ? args[@"bundle_id"] : nil;
    if (!bid.length || strlen(bid.UTF8String) != [bid lengthOfBytesUsingEncoding:NSUTF8StringEncoding]) return mcp_error_result(@"'bundle_id' must be a valid identifier string");
    if (!c_app_kill(bid.UTF8String)) return mcp_error_result(@(c_app_last_error()));
    return mcp_text_result([NSString stringWithFormat:@"App stopped (or already stopped): %@", bid], NO);
}

NSDictionary *tool_get_front_app(NSDictionary *args) {
    (void)args;
    const char *bid = c_get_front_app();
    if (!bid) return mcp_error_result(@(c_app_last_error()));
    NSData *json = [NSJSONSerialization dataWithJSONObject:@{@"bundleId":@(bid)} options:0 error:nil];
    NSString *result = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    return mcp_text_result(result, NO);
}
