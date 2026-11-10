// POSIX framing/deadline tests of the same C transport included by widget-ipc.m.
#define _DEFAULT_SOURCE 1
#include "../widget/widget-ipc-transport.h"
#include <sys/wait.h>
#include <signal.h>
#include <stdlib.h>
#include <stdio.h>
#include <assert.h>

enum reply_mode { FRAGMENTED, ACK_THEN_CLOSE, NO_NEWLINE, NO_ACK, OVERSIZE, SLOW_PARTIAL };
static const char request[] = "{\"id\":\"fixture\",\"action\":\"script_status\"}\n";
static const char ack[] = "{\"id\":\"fixture\",\"ok\":true,\"running\":false}";

static void write_all(int fd, const void *bytes, size_t size) {
    size_t sent = 0;
    while (sent < size) {
        ssize_t count = write(fd, (const char *)bytes + sent, size - sent);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) _exit(2);
        sent += (size_t)count;
    }
}

static void server_child(int listener, enum reply_mode mode) {
    (void)signal(SIGPIPE, SIG_IGN);
    int fd = accept(listener, NULL, NULL);
    if (fd < 0) _exit(3);
    char input[sizeof(request)];
    size_t count = 0;
    while (count < sizeof(input) - 1) {
        ssize_t size = read(fd, input + count, 1); // Intentionally fragment reads.
        if (size < 0 && errno == EINTR) continue;
        if (size != 1) _exit(4);
        count++;
        if (input[count - 1] == '\n') break;
    }
    if (count != sizeof(request) - 1 || memcmp(input, request, count)) _exit(5);
    if (mode == FRAGMENTED) {
        write_all(fd, ack, 7);
        usleep(2000);
        write_all(fd, ack + 7, sizeof(ack) - 1 - 7);
        usleep(2000);
        write_all(fd, "\n", 1);
    } else if (mode == ACK_THEN_CLOSE) {
        write_all(fd, ack, sizeof(ack) - 1);
        write_all(fd, "\n", 1);
    } else if (mode == NO_NEWLINE) {
        write_all(fd, ack, sizeof(ack) - 1);
    } else if (mode == NO_ACK) {
        usleep(160000);
    } else if (mode == OVERSIZE) {
        char *payload = malloc(WIDGET_IPC_MAX_RESPONSE);
        if (!payload) _exit(6);
        memset(payload, 'x', WIDGET_IPC_MAX_RESPONSE);
        write_all(fd, payload, WIDGET_IPC_MAX_RESPONSE);
        free(payload);
    } else if (mode == SLOW_PARTIAL) {
        write_all(fd, "{", 1);
        usleep(30000);
        write_all(fd, "x", 1);
        usleep(130000); // Per-recv timeout must not extend the total deadline.
    }
    close(fd);
    close(listener);
    _exit(0);
}

static void exercise(enum reply_mode mode, int expected) {
    char temporary[] = "/tmp/iat-widget-XXXXXX";
    assert(mkdtemp(temporary));
    char path[sizeof(((struct sockaddr_un *)0)->sun_path)];
    assert(snprintf(path, sizeof(path), "%s/socket", temporary) < (int)sizeof(path));
    int listener = socket(AF_UNIX, SOCK_STREAM, 0);
    assert(listener >= 0);
    struct sockaddr_un address;
    memset(&address, 0, sizeof(address));
    address.sun_family = AF_UNIX;
    memcpy(address.sun_path, path, strlen(path) + 1);
#ifdef __APPLE__
    address.sun_len = (unsigned char)(offsetof(struct sockaddr_un, sun_path) + strlen(path) + 1);
#endif
    assert(bind(listener, (struct sockaddr *)&address, sizeof(address)) == 0);
    assert(listen(listener, 1) == 0);
    pid_t child = fork();
    assert(child >= 0);
    if (!child) server_child(listener, mode);
    unsigned char response[WIDGET_IPC_MAX_RESPONSE];
    size_t length = 0;
    int budget = (mode == NO_ACK || mode == SLOW_PARTIAL) ? 60 : 1000;
    long long started = widget_transport_now_ms();
    int result = widget_transport_exchange(path, request, sizeof(request) - 1,
        response, sizeof(response), &length, budget);
    long long elapsed = widget_transport_now_ms() - started;
    assert(result == expected);
    if (!result) {
        assert(length == sizeof(ack) - 1);
        assert(memcmp(response, ack, length) == 0);
    }
    if (expected == ETIMEDOUT) assert(elapsed >= 45 && elapsed < 1000);
    close(listener);
    int status = 0;
    assert(waitpid(child, &status, 0) == child);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    assert(unlink(path) == 0);
    assert(rmdir(temporary) == 0);
}

int main(void) {
    exercise(FRAGMENTED, 0);
    exercise(ACK_THEN_CLOSE, 0);
    exercise(NO_NEWLINE, EPROTO);
    exercise(NO_ACK, ETIMEDOUT);
    exercise(OVERSIZE, EMSGSIZE);
    exercise(SLOW_PARTIAL, ETIMEDOUT);
    unsigned char reply[8]; size_t length = 0;
    assert(widget_transport_exchange("/unused", "{}", 2, reply, sizeof(reply), &length, 10) == EINVAL);
    char long_path[200]; memset(long_path, 'x', sizeof(long_path)); long_path[199] = 0;
    assert(widget_transport_exchange(long_path, request, sizeof(request) - 1,
        reply, sizeof(reply), &length, 10) == ENAMETOOLONG);
    puts("widget transport: 8 tests passed");
    return 0;
}
