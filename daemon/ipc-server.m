#import "ipc-server.h"
#import "script-runner.h"
#import "logger.h"
#import <Foundation/Foundation.h>
#import <sys/socket.h>
#import <sys/un.h>
#import <unistd.h>
#import <pthread.h>
#import <string.h>

#define READ_BUF_SIZE 65536

static int server_fd = -1;

typedef struct { int fd; } ClientCtx;

static void handle_message(int fd, NSDictionary *req) {
    NSString *action = req[@"action"];
    NSString *reqId  = req[@"id"] ?: @"";

    if ([action isEqualToString:@"run_script"]) {
        NSString *script = req[@"script"] ?: @"";
        script_run(fd, reqId.UTF8String, script.UTF8String);

    } else if ([action isEqualToString:@"stop_script"]) {
        script_stop_current();
        char resp[128];
        snprintf(resp, sizeof(resp), "{\"id\":\"%s\",\"ok\":true}\n", reqId.UTF8String);
        write(fd, resp, strlen(resp));

    } else {
        char resp[256];
        snprintf(resp, sizeof(resp),
            "{\"id\":\"%s\",\"ok\":false,\"error\":\"unknown action: %s\"}\n",
            reqId.UTF8String, action.UTF8String ?: "null");
        write(fd, resp, strlen(resp));
    }
}

static void *client_thread(void *arg) {
    @autoreleasepool {
        ClientCtx *ctx = (ClientCtx *)arg;
        int fd = ctx->fd;
        free(ctx);

        char *buf = malloc(READ_BUF_SIZE);
        ssize_t n;

        while ((n = read(fd, buf, READ_BUF_SIZE - 1)) > 0) {
            buf[n] = '\0';

            NSData *data = [NSData dataWithBytes:buf length:n];
            NSError *err = nil;
            NSDictionary *req = [NSJSONSerialization
                JSONObjectWithData:data options:0 error:&err];

            if (!req || err || ![req isKindOfClass:[NSDictionary class]]) {
                const char *e = "{\"ok\":false,\"error\":\"invalid JSON\"}\n";
                write(fd, e, strlen(e));
                continue;
            }
            handle_message(fd, req);
        }

        free(buf);
        close(fd);
    }
    return NULL;
}

void ipc_server_start(const char *socket_path) {
    unlink(socket_path);

    server_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server_fd < 0) { log_error("socket() failed"); return; }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strlcpy(addr.sun_path, socket_path, sizeof(addr.sun_path));

    if (bind(server_fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        log_error("bind() failed at %s", socket_path);
        close(server_fd);
        return;
    }

    chmod(socket_path, 0777);
    chown(socket_path, 501, 501); // mobile:mobile

    listen(server_fd, 16);

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        while (1) {
            int client_fd = accept(server_fd, NULL, NULL);
            if (client_fd < 0) continue;

            ClientCtx *ctx = malloc(sizeof(ClientCtx));
            ctx->fd = client_fd;

            pthread_t t;
            pthread_create(&t, NULL, client_thread, ctx);
            pthread_detach(t);
        }
    });
}
