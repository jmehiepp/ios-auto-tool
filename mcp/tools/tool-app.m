#import "../mcp-tools.h"
#import "../../engine/app/app-control.h"
#import <Foundation/Foundation.h>

NSDictionary *tool_app_run(NSDictionary *args) {
    NSString *bid = args[@"bundle_id"];
    if (!bid.length) return mcp_error_result(@"'bundle_id' is required");
    c_app_run(bid.UTF8String);
    return mcp_text_result([NSString stringWithFormat:@"launched %@", bid], NO);
}

NSDictionary *tool_app_kill(NSDictionary *args) {
    NSString *bid = args[@"bundle_id"];
    if (!bid.length) return mcp_error_result(@"'bundle_id' is required");
    c_app_kill(bid.UTF8String);
    return mcp_text_result([NSString stringWithFormat:@"killed %@", bid], NO);
}

NSDictionary *tool_get_front_app(NSDictionary *args) {
    (void)args;
    const char *bid = c_get_front_app();
    NSString *result = [NSString stringWithFormat:@"{\"bundleId\":\"%s\"}", bid ?: ""];
    return mcp_text_result(result, NO);
}
