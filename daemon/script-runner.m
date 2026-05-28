#import "script-runner.h"
#import "logger.h"
#import "../lua/lua-bridge.h"
#import <Foundation/Foundation.h>
#import <pthread.h>
#import <string.h>
#import <unistd.h>

static int         current_fd     = -1;
static char        current_id[64] = {0};
static pthread_mutex_t run_mutex  = PTHREAD_MUTEX_INITIALIZER;
static volatile int stop_flag     = 0;

typedef struct {
    int   fd;
    char  req_id[64];
    char *code;
} RunCtx;

static void *run_thread(void *arg) {
    @autoreleasepool {
        RunCtx *ctx = (RunCtx *)arg;

        pthread_mutex_lock(&run_mutex);
        current_fd  = ctx->fd;
        stop_flag   = 0;
        strlcpy(current_id, ctx->req_id, sizeof(current_id));
        pthread_mutex_unlock(&run_mutex);

        log_add_client(ctx->fd);

        int rc = lua_run_script(ctx->code);

        char result[256];
        snprintf(result, sizeof(result),
            "{\"id\":\"%s\",\"type\":\"result\",\"ok\":%s}\n",
            ctx->req_id, rc == 0 ? "true" : "false");
        write(ctx->fd, result, strlen(result));

        log_remove_client(ctx->fd);

        pthread_mutex_lock(&run_mutex);
        current_fd = -1;
        current_id[0] = '\0';
        pthread_mutex_unlock(&run_mutex);

        free(ctx->code);
        free(ctx);
    }
    return NULL;
}

void script_run(int client_fd, const char *req_id, const char *code) {
    RunCtx *ctx = malloc(sizeof(RunCtx));
    ctx->fd   = client_fd;
    strlcpy(ctx->req_id, req_id, sizeof(ctx->req_id));
    ctx->code = strdup(code);

    pthread_t t;
    pthread_create(&t, NULL, run_thread, ctx);
    pthread_detach(t);
}

void script_stop_current(void) {
    pthread_mutex_lock(&run_mutex);
    stop_flag = 1;
    pthread_mutex_unlock(&run_mutex);
}

void script_send_log(const char *level, const char *msg) {
    pthread_mutex_lock(&run_mutex);
    int   fd  = current_fd;
    char  id[64];
    strlcpy(id, current_id, sizeof(id));
    pthread_mutex_unlock(&run_mutex);

    if (fd < 0) {
        log_broadcast(LOG_LEVEL_LUA, msg);
        return;
    }

    char json[4096 + 256];
    snprintf(json, sizeof(json),
        "{\"id\":\"%s\",\"type\":\"log\",\"level\":\"%s\",\"data\":\"%s\"}\n",
        id, level, msg);
    write(fd, json, strlen(json));
}
