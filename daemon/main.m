#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import "logger.h"
#import "ipc-server.h"
#import "scheduler.h"
#import "../lua/lua-bridge.h"
#import "../webide/server/webide-server.h"
#import "../mcp/mcp-server.h"
#import "runtime-paths.h"
#import "../mcp/stdio-bridge.h"
#include <signal.h>
#include <unistd.h>

#define IPC_SOCKET_PATH  "/var/run/iosautotool.sock"
#define WEBIDE_PORT      8890
#define MCP_PORT         8765

int main(int argc, char *argv[]) {
    @autoreleasepool {
        signal(SIGPIPE, SIG_IGN);
        if (getuid() != 0) { fprintf(stderr, "Run iosautotool-daemon as root.\n"); return 1; }
        if (argc > 1 && strcmp(argv[1], "--mcp-stdio") == 0) return iat_stdio_bridge();
        if (argc > 1 && strcmp(argv[1], "--access-code") == 0) {
            NSString *token = iat_access_token();
            if (!token) return 1;
            puts(token.UTF8String);
            return 0;
        }
        if (!iat_access_token()) { fprintf(stderr, "Could not initialize access code.\n"); return 1; }
        log_init();
        log_info("iOS Auto Tool daemon v1.0 starting");

        lua_bridge_init();
        log_info("Lua engine initialized");

        ipc_server_start(IPC_SOCKET_PATH);
        log_info("IPC ready at " IPC_SOCKET_PATH);

        NSString *scripts = [iat_data_directory() stringByAppendingPathComponent:@"scripts"];
        NSString *frontend = iat_resource_path(@"webide/frontend");
        webide_server_start(WEBIDE_PORT, strdup(scripts.UTF8String), strdup(frontend.UTF8String));
        log_info("Web IDE ready at port %d", WEBIDE_PORT);

        mcp_server_start(MCP_PORT);
        log_info("MCP server ready at port %d", MCP_PORT);

        scheduler_start(scripts.UTF8String);
        log_info("Scheduler ready");

        log_info("Daemon ready — waiting for connections");
        CFRunLoopRun();
    }
    return 0;
}
