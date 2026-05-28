#import "../mcp-tools.h"
#import "../../lua/lua-bridge.h"
#import <Foundation/Foundation.h>

// Collected log output from Lua execution (thread-local via script-runner)
extern void script_run(int client_fd, const char *req_id, const char *code);

NSDictionary *tool_lua_run(NSDictionary *args) {
    NSString *code = args[@"code"];
    if (!code.length) return mcp_error_result(@"'code' is required");

    // Run synchronously on the Lua state (already mutex-protected in lua-bridge)
    int rc = lua_run_script(code.UTF8String);

    NSString *status = rc == 0
        ? [NSString stringWithFormat:@"Script executed (exit %d)", rc]
        : [NSString stringWithFormat:@"Script error (exit %d)", rc];
    return mcp_text_result(status, rc != 0);
}
