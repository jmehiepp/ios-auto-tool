#pragma once

// Runs cmd in /bin/sh -c. Returns exit code. stdout+stderr are logged.
int c_shell_exec(const char *cmd);

// Same but returns heap-allocated stdout+stderr string (caller frees).
// Sets *exit_code if non-NULL.
char *c_shell_exec_output(const char *cmd, int *exit_code);
