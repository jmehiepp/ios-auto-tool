#import "../mcp-tools.h"
#import "../../lua/lua-bridge.h"
#import <Foundation/Foundation.h>

// Collected log output from Lua execution (thread-local via script-runner)
#import "../../daemon/script-runner.h"

NSDictionary *tool_lua_run(NSDictionary *args) {
    NSString *code = args[@"code"];
    if (!code.length) return mcp_error_result(@"'code' is required");

    // Run synchronously on the Lua state (already mutex-protected in lua-bridge)
    int rc = script_run(-1, "mcp", code.UTF8String) ? 0 : 1;

    NSString *status = rc == 0
        ? @"Script accepted. Read the Web IDE log for completion."
        : @"A script is already running, or the script could not be scheduled.";
    return mcp_text_result(status, rc != 0);
}
