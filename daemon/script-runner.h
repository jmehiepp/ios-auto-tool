#pragma once

void script_run(int client_fd, const char *req_id, const char *code);
void script_stop_current(void);
void script_send_log(const char *level, const char *msg);
