#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import "logger.h"
#import "ipc-server.h"
#import "../lua/lua-bridge.h"
#import "../webide/server/webide-server.h"
#import "../mcp/mcp-server.h"

#define IPC_SOCKET_PATH  "/var/run/iosautotool.sock"
#define WEBIDE_PORT      8888
#define MCP_PORT         8765
#define SCRIPTS_DIR      "/Library/IOSAutoTool/scripts"
#define WEBIDE_ROOT      "/Library/IOSAutoTool/webide"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        log_init();
        log_info("iOS Auto Tool daemon v1.0 starting");

        lua_bridge_init();
        log_info("Lua engine initialized");

        ipc_server_start(IPC_SOCKET_PATH);
        log_info("IPC ready at " IPC_SOCKET_PATH);

        webide_server_start(WEBIDE_PORT, SCRIPTS_DIR, WEBIDE_ROOT);
        log_info("Web IDE ready at port " #WEBIDE_PORT);

        mcp_server_start(MCP_PORT);
        log_info("MCP server ready at port " #MCP_PORT);

        log_info("Daemon ready — waiting for connections");
        CFRunLoopRun();
    }
    return 0;
}
