#import "shell-exec.h"
#import <Foundation/Foundation.h>
#include <stdlib.h>
#include <string.h>
#include <spawn.h>
#include <unistd.h>
#include <sys/wait.h>

extern char **environ;

// posix_spawn-based implementation — NSTask is restricted on iOS 14+
static char *run_command(const char *cmd, int *out_exit_code) {
    int pipefd[2];
    if (pipe(pipefd) != 0) {
        if (out_exit_code) *out_exit_code = -1;
        return strdup("");
    }

    pid_t pid;
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    // Redirect stdout + stderr to write-end of pipe
    posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, pipefd[0]);
    posix_spawn_file_actions_addclose(&actions, pipefd[1]);

    char *argv[] = { "/bin/sh", "-c", (char *)cmd, NULL };
    int rc = posix_spawn(&pid, "/bin/sh", &actions, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&actions);
    close(pipefd[1]);

    if (rc != 0) {
        close(pipefd[0]);
        if (out_exit_code) *out_exit_code = rc;
        return strdup("");
    }

    // Read all output
    NSMutableData *buf = [NSMutableData data];
    char chunk[4096];
    ssize_t n;
    while ((n = read(pipefd[0], chunk, sizeof(chunk))) > 0) {
        [buf appendBytes:chunk length:(NSUInteger)n];
    }
    close(pipefd[0]);

    int status = 0;
    waitpid(pid, &status, 0);
    if (out_exit_code) *out_exit_code = WIFEXITED(status) ? WEXITSTATUS(status) : -1;

    NSString *str = [[NSString alloc] initWithData:buf encoding:NSUTF8StringEncoding];
    return strdup(str.UTF8String ?: "");
}

int c_shell_exec(const char *cmd) {
    if (!cmd) return -1;
    int code = 0;
    char *out = run_command(cmd, &code);
    // Log output via daemon logger if available
    if (out && strlen(out) > 0) {
        // Avoid circular import — print to stderr which launchd captures
        fputs(out, stderr);
    }
    free(out);
    return code;
}

char *c_shell_exec_output(const char *cmd, int *exit_code) {
    if (!cmd) {
        if (exit_code) *exit_code = -1;
        return strdup("");
    }
    return run_command(cmd, exit_code);
}
