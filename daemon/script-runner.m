#import "script-runner.h"
#import "logger.h"
#import "../lua/lua-bridge.h"
#import "../engine/screen/screenshot.h"
#import <Foundation/Foundation.h>
#include <pthread.h>
#include <sys/socket.h>
#include <unistd.h>
#include <string.h>

static pthread_mutex_t run_mutex = PTHREAD_MUTEX_INITIALIZER;
static bool running = false, stop_requested = false;
typedef struct { int fd; char *identifier; char *code; } RunContext;

bool script_is_running(void) {
    pthread_mutex_lock(&run_mutex);
    bool value = running;
    pthread_mutex_unlock(&run_mutex);
    return value;
}

bool script_should_stop(void) {
    pthread_mutex_lock(&run_mutex);
    bool value = stop_requested;
    pthread_mutex_unlock(&run_mutex);
    return value;
}
static void *run_thread(void *argument) {
    @autoreleasepool {
        RunContext *ctx = argument;
        if (ctx->fd >= 0) log_add_client(ctx->fd);
        log_info("Script started");
        int code = lua_run_script(ctx->code);
        screen_cache_invalidate();
        log_info("Script finished (exit %d)", code);
        if (ctx->fd >= 0) {
            NSDictionary *result = @{@"id": @(ctx->identifier), @"type": @"result", @"ok": @(code == 0)};
            NSMutableData *data = [[NSJSONSerialization dataWithJSONObject:result options:0 error:nil] mutableCopy];
            [data appendBytes:"\n" length:1];
            send(ctx->fd, data.bytes, data.length, 0);
            log_remove_client(ctx->fd);
            close(ctx->fd);
        }
        free(ctx->identifier); free(ctx->code); free(ctx);
        pthread_mutex_lock(&run_mutex); running = false; pthread_mutex_unlock(&run_mutex);
    }
    return NULL;
}
bool script_run(int client_fd, const char *identifier, const char *source) {
    if (!source || strlen(source) > 1024 * 1024) return false;
    pthread_mutex_lock(&run_mutex);
    if (running) { pthread_mutex_unlock(&run_mutex); return false; }
    running = true; stop_requested = false;
    pthread_mutex_unlock(&run_mutex);
    RunContext *ctx = calloc(1, sizeof(*ctx));
    if (!ctx) { pthread_mutex_lock(&run_mutex); running = false; pthread_mutex_unlock(&run_mutex); return false; }
    ctx->fd = client_fd >= 0 ? dup(client_fd) : -1;
    ctx->identifier = strdup(identifier ?: "script");
    ctx->code = strdup(source);
    pthread_t thread;
    if (ctx->identifier && ctx->code && pthread_create(&thread, NULL, run_thread, ctx) == 0) {
        pthread_detach(thread); return true;
    }
    if (ctx->fd >= 0) close(ctx->fd);
    free(ctx->identifier); free(ctx->code); free(ctx);
    pthread_mutex_lock(&run_mutex); running = false; pthread_mutex_unlock(&run_mutex);
    return false;
}
void script_stop_current(void) {
    pthread_mutex_lock(&run_mutex); stop_requested = true; pthread_mutex_unlock(&run_mutex);
}
void script_send_log(const char *level, const char *message) { log_broadcast(LOG_LEVEL_LUA, message ?: ""); }
