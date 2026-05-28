#pragma once
#include <stdarg.h>

typedef enum {
    LOG_LEVEL_INFO  = 0,
    LOG_LEVEL_WARN  = 1,
    LOG_LEVEL_ERROR = 2,
    LOG_LEVEL_LUA   = 3,
} LogLevel;

void log_init(void);
void log_info(const char *fmt, ...);
void log_warn(const char *fmt, ...);
void log_error(const char *fmt, ...);
void log_lua(const char *msg);
void log_broadcast(LogLevel level, const char *msg);
void log_add_client(int fd);
void log_remove_client(int fd);
