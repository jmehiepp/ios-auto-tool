#import "logger.h"
#import "../webide/server/webide-server.h"
#import <Foundation/Foundation.h>
#import <sys/stat.h>
#import <unistd.h>
#import <pthread.h>
#import <string.h>
#import <time.h>

#define MAX_LOG_CLIENTS 32
#define LOG_DIR "/var/log/iosautotool"

static FILE            *log_file        = NULL;
static int              log_clients[MAX_LOG_CLIENTS];
static int              log_client_count = 0;
static pthread_mutex_t  log_mutex       = PTHREAD_MUTEX_INITIALIZER;

static const char *level_names[] = { "INFO", "WARN", "ERROR", "LUA" };

void log_init(void) {
    mkdir(LOG_DIR, 0755);
    time_t t = time(NULL);
    char path[256];
    snprintf(path, sizeof(path), LOG_DIR "/run-%ld.log", (long)t);
    log_file = fopen(path, "w");

    pthread_mutex_lock(&log_mutex);
    memset(log_clients, -1, sizeof(log_clients));
    pthread_mutex_unlock(&log_mutex);
}

void log_add_client(int fd) {
    pthread_mutex_lock(&log_mutex);
    for (int i = 0; i < MAX_LOG_CLIENTS; i++) {
        if (log_clients[i] < 0) {
            log_clients[i] = fd;
            if (i >= log_client_count) log_client_count = i + 1;
            break;
        }
    }
    pthread_mutex_unlock(&log_mutex);
}

void log_remove_client(int fd) {
    pthread_mutex_lock(&log_mutex);
    for (int i = 0; i < log_client_count; i++) {
        if (log_clients[i] == fd) {
            log_clients[i] = -1;
            break;
        }
    }
    pthread_mutex_unlock(&log_mutex);
}

void log_broadcast(LogLevel level, const char *msg) {
    if (log_file) {
        fprintf(log_file, "[%s] %s\n", level_names[level], msg);
        fflush(log_file);
    }

    char json[4096 + 128];
    snprintf(json, sizeof(json),
        "{\"type\":\"log\",\"level\":\"%s\",\"data\":\"%s\"}\n",
        level_names[level], msg);
    size_t len = strlen(json);

    pthread_mutex_lock(&log_mutex);
    for (int i = 0; i < log_client_count; i++) {
        if (log_clients[i] >= 0) {
            write(log_clients[i], json, len);
        }
    }
    pthread_mutex_unlock(&log_mutex);

    // Broadcast to Web IDE WebSocket clients
    webide_ws_broadcast_log(level_names[level], msg);
}

static void log_vfmt(LogLevel level, const char *fmt, va_list args) {
    char buf[4096];
    vsnprintf(buf, sizeof(buf), fmt, args);
    log_broadcast(level, buf);
}

void log_info(const char *fmt, ...) {
    va_list a; va_start(a, fmt); log_vfmt(LOG_LEVEL_INFO,  fmt, a); va_end(a);
}
void log_warn(const char *fmt, ...) {
    va_list a; va_start(a, fmt); log_vfmt(LOG_LEVEL_WARN,  fmt, a); va_end(a);
}
void log_error(const char *fmt, ...) {
    va_list a; va_start(a, fmt); log_vfmt(LOG_LEVEL_ERROR, fmt, a); va_end(a);
}
void log_lua(const char *msg) {
    log_broadcast(LOG_LEVEL_LUA, msg);
}
