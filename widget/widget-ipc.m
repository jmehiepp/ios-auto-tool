#import "widget-ipc.h"
#import <sys/socket.h>
#import <sys/un.h>
#import <unistd.h>
#import <string.h>

#define IPC_SOCKET_PATH "/var/run/iosautotool.sock"

BOOL widget_ipc_run_script(NSString *script_path) {
    NSString *code = [NSString stringWithContentsOfFile:script_path
                                               encoding:NSUTF8StringEncoding
                                                  error:nil];
    if (!code.length) return NO;

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return NO;

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strlcpy(addr.sun_path, IPC_SOCKET_PATH, sizeof(addr.sun_path));

    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(fd);
        return NO;
    }

    NSDictionary *req = @{
        @"action": @"run_script",
        @"id":     [[NSUUID UUID] UUIDString],
        @"script": code,
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:req options:0 error:nil];
    if (!data) { close(fd); return NO; }

    ssize_t n = send(fd, data.bytes, data.length, 0);
    close(fd);
    return n == (ssize_t)data.length;
}
