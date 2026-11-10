#pragma once
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/select.h>
#include <errno.h>
#include <stddef.h>
#include <string.h>
#include <time.h>
#include <limits.h>

#define WIDGET_IPC_SOCKET_PATH "/var/run/iosautotool-widget.sock"
#define WIDGET_IPC_TIMEOUT_MS 3000
#define WIDGET_IPC_MAX_RESPONSE 65536

static long long widget_transport_now_ms(void) {
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) return -1;
    return (long long)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

static int widget_transport_wait(int fd, short events, long long deadline) {
    if (fd < 0 || fd >= FD_SETSIZE) return EBADF;
    for (;;) {
        long long now = widget_transport_now_ms();
        if (now < 0) return EIO;
        long long remaining = deadline - now;
        if (remaining <= 0) return ETIMEDOUT;
        // SpringBoard's sandbox on iOS 15 denies poll (Darwin syscall 230).
        // select preserves the total deadline without changing host privileges.
        fd_set reads, writes, errors;
        FD_ZERO(&reads); FD_ZERO(&writes); FD_ZERO(&errors);
        if (events & POLLIN) FD_SET(fd, &reads);
        if (events & POLLOUT) FD_SET(fd, &writes);
        FD_SET(fd, &errors);
        struct timeval timeout = {remaining / 1000, (remaining % 1000) * 1000};
        int result = select(fd + 1, &reads, &writes, &errors, &timeout);
        if (result < 0 && errno == EINTR) continue;
        if (result < 0) return errno;
        if (!result) return ETIMEDOUT;
        return 0;
    }
}

// One newline-delimited request and ACK. Returns errno-style result; no global state.
static int widget_transport_exchange(const char *socket_path, const void *request,
        size_t length, void *response, size_t capacity, size_t *response_length,
        int timeout_ms) {
    if (!socket_path || !request || !length || length > 4096 || !response ||
        !capacity || !response_length || timeout_ms <= 0) return EINVAL;
    *response_length = 0;
    if (((const unsigned char *)request)[length - 1] != '\n') return EINVAL;
    struct sockaddr_un address;
    memset(&address, 0, sizeof(address));
    address.sun_family = AF_UNIX;
    size_t path_length = strlen(socket_path);
    if (!path_length || path_length >= sizeof(address.sun_path)) return ENAMETOOLONG;
    memcpy(address.sun_path, socket_path, path_length + 1);
#ifdef __APPLE__
    address.sun_len = (unsigned char)(offsetof(struct sockaddr_un, sun_path) + path_length + 1);
#endif
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return errno;
    int result = 0;
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0) {
        result = errno; goto done;
    }
    (void)fcntl(fd, F_SETFD, FD_CLOEXEC);
#ifdef SO_NOSIGPIPE
    int no_sigpipe = 1;
    if (setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &no_sigpipe, sizeof(no_sigpipe)) != 0) {
        result = errno; goto done;
    }
#endif
    long long now = widget_transport_now_ms();
    if (now < 0) { result = EIO; goto done; }
    long long deadline = now + timeout_ms;
    if (connect(fd, (struct sockaddr *)&address,
            (socklen_t)(offsetof(struct sockaddr_un, sun_path) + path_length + 1)) < 0) {
        if (errno != EINPROGRESS && errno != EAGAIN && errno != EINTR) {
            result = errno; goto done;
        }
        result = widget_transport_wait(fd, POLLOUT, deadline);
        if (result) goto done;
        int error = 0;
        socklen_t error_length = sizeof(error);
        if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &error_length) != 0) {
            result = errno; goto done;
        }
        if (error) { result = error; goto done; }
    }
    size_t sent = 0;
    while (sent < length) {
        result = widget_transport_wait(fd, POLLOUT, deadline);
        if (result) goto done;
        int send_flags = 0;
#ifdef MSG_NOSIGNAL
        send_flags = MSG_NOSIGNAL;
#endif
        ssize_t count = send(fd, (const unsigned char *)request + sent, length - sent, send_flags);
        if (count < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)) continue;
        if (count <= 0) { result = count < 0 ? errno : EPIPE; goto done; }
        sent += (size_t)count;
    }
    size_t received = 0;
    for (;;) {
        if (received == capacity) { result = EMSGSIZE; goto done; }
        result = widget_transport_wait(fd, POLLIN, deadline);
        if (result) goto done;
        ssize_t count = recv(fd, (unsigned char *)response + received, capacity - received, 0);
        if (count < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)) continue;
        if (count <= 0) { result = count < 0 ? errno : EPROTO; goto done; }
        unsigned char *newline = memchr((unsigned char *)response + received, '\n', (size_t)count);
        if (newline) {
            *response_length = (size_t)(newline - (unsigned char *)response);
            if (!*response_length) result = EPROTO;
            goto done;
        }
        received += (size_t)count;
    }
done:
    close(fd);
    return result;
}
