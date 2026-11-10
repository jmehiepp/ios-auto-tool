// Simulate select reporting readiness after its timeout while a thread was
// descheduled. Late EOF/data must not override the absolute transport budget.
#include <sys/select.h>
#include <unistd.h>
#include <assert.h>
#include <stdio.h>
static int late_select(int count, fd_set *reads, fd_set *writes,
                       fd_set *errors, struct timeval *timeout) {
    (void)count; (void)reads; (void)writes; (void)errors;
    usleep((unsigned int)(timeout->tv_sec * 1000000 + timeout->tv_usec + 30000));
    return 1;
}
#define select late_select
#include "../widget/widget-ipc-transport.h"
#undef select
int main(void) {
    long long started = widget_transport_now_ms();
    assert(widget_transport_wait(0, POLLIN, started + 20) == ETIMEDOUT);
    assert(widget_transport_now_ms() - started >= 20);
    char response[8]; size_t length = 0;
    assert(widget_transport_exchange(NULL, NULL, 0, response, sizeof(response), &length, 20) == EINVAL);
    puts("Widget late wakeup deadline tests passed");
    return 0;
}
