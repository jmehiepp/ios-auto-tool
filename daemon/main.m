#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import "logger.h"
#import "ipc-server.h"
#import "scheduler.h"
#import "../lua/lua-bridge.h"
#import "../webide/server/webide-server.h"
#import "../mcp/mcp-server.h"
#import "runtime-paths.h"
#import "widget-service.h"
#import "platform-paths.h"
#import "../spoof/spoof-config.h"
#import "../mcp/stdio-bridge.h"
#include <signal.h>
#include <unistd.h>
#include <dlfcn.h>

#define IPC_SOCKET_PATH  "/var/run/iosautotool.sock"
#define WEBIDE_PORT      8890
#define MCP_PORT         8765

static void configure_model_memory_budget(void) {
    // XNU's memorystatus_memlimit_properties_t, in MiB. Some bootstrap launchd
    // versions ignore per-job JetsamProperties, leaving an 18 MiB fatal limit.
    typedef struct { int32_t active; uint32_t active_flags;
                     int32_t inactive; uint32_t inactive_flags; } MemoryLimits;
    typedef int (*MemoryControl)(uint32_t, pid_t, uint32_t, void *, size_t);
    MemoryControl control = (MemoryControl)dlsym(RTLD_DEFAULT, "memorystatus_control");
    MemoryLimits limits = {256, 1, 256, 1}; // fatal, finite limits in both states
    if (!control || control(7, getpid(), 0, &limits, sizeof(limits)) != 0) {
        log_warn("Could not configure the 256 MiB Vision memory budget"); return;
    }
    if (control(8, getpid(), 0, &limits, sizeof(limits)) == 0)
        log_info("Model memory budget: active=%d MiB inactive=%d MiB", limits.active, limits.inactive);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        signal(SIGPIPE, SIG_IGN);
        NSString *path = [NSString stringWithFormat:@"%s:%s:%s:/usr/bin:/bin:/usr/sbin:/sbin",
            IAT_BOOTSTRAP_PATH("/usr/bin"), IAT_BOOTSTRAP_PATH("/bin"), IAT_BOOTSTRAP_PATH("/usr/sbin")];
        setenv("PATH", path.UTF8String, 1);
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
        configure_model_memory_budget();
        log_info("iOS Auto Tool daemon v1.2 beta starting");
        NSError *configError = nil;
        SpoofConfig *deviceConfig = [SpoofConfig shared];
        if (![deviceConfig setConfiguration:[deviceConfig getAll] error:&configError])
            log_warn("Device filter could not be refreshed: %s", configError.localizedDescription.UTF8String);

        lua_bridge_init();
        log_info("Lua engine initialized");

        ipc_server_start(IAT_PATH(IPC_SOCKET_PATH));
        widget_service_start();
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
