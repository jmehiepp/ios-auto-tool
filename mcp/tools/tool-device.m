#import "../mcp-tools.h"
#import "../../engine/keyboard/text-input.h"
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <sys/utsname.h>
#import <arpa/inet.h>
#import <ifaddrs.h>

static NSString *get_device_ip(void) {
    struct ifaddrs *addrs = NULL;
    getifaddrs(&addrs);
    NSString *ip = @"unknown";
    for (struct ifaddrs *ifa = addrs; ifa; ifa = ifa->ifa_next) {
        if (ifa->ifa_addr->sa_family != AF_INET) continue;
        if (strncmp(ifa->ifa_name, "en", 2) != 0) continue;
        char buf[INET_ADDRSTRLEN];
        inet_ntop(AF_INET,
                  &((struct sockaddr_in *)ifa->ifa_addr)->sin_addr,
                  buf, sizeof(buf));
        ip = @(buf);
        break;
    }
    freeifaddrs(addrs);
    return ip;
}

NSDictionary *tool_device_info(NSDictionary *args) {
    (void)args;
    struct utsname sys; uname(&sys);
    UIScreen *screen = [UIScreen mainScreen];
    NSString *ios    = [UIDevice currentDevice].systemVersion;
    NSString *ip     = get_device_ip();

    NSString *json = [NSString stringWithFormat:
        @"{\"model\":\"%s\",\"ios\":\"%@\","
         "\"screen_w\":%.0f,\"screen_h\":%.0f,"
         "\"scale\":%.1f,\"ip\":\"%@\"}",
        sys.machine, ios,
        screen.bounds.size.width, screen.bounds.size.height,
        screen.scale, ip];
    return mcp_text_result(json, NO);
}

NSDictionary *tool_set_clipboard(NSDictionary *args) {
    NSString *text = args[@"text"];
    if (!text) return mcp_error_result(@"'text' is required");
    c_set_clipboard(text);
    return mcp_text_result(@"clipboard set", NO);
}

NSDictionary *tool_get_clipboard(NSDictionary *args) {
    (void)args;
    NSString *text = c_get_clipboard();
    return mcp_text_result(text ?: @"", NO);
}
