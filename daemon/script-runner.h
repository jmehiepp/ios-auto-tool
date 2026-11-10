#pragma once

#include <stdbool.h>
bool script_run(int client_fd, const char *req_id, const char *code);
bool script_should_stop(void);
bool script_is_running(void);
void script_stop_current(void);
void script_send_log(const char *level, const char *msg);
