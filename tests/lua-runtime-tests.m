#import <Foundation/Foundation.h>
#import "../lua/lua-bridge.h"
#include <stdatomic.h>
#include <stdbool.h>
#include <pthread.h>
#include <signal.h>
#include <unistd.h>

static atomic_bool stop_flag = false;
static int thread_result;
bool script_should_stop(void) { return atomic_load(&stop_flag); }
void script_send_log(const char *level, const char *message) { (void)level; (void)message; }
void log_info(const char *format, ...) { (void)format; }
void log_warn(const char *format, ...) { (void)format; }
void log_error(const char *format, ...) { (void)format; }
void register_touch_bindings(lua_State *state) { (void)state; }
void register_screen_bindings(lua_State *state) { (void)state; }
void register_app_bindings(lua_State *state) { (void)state; }
void register_keyboard_bindings(lua_State *state) { (void)state; }
void register_system_bindings(lua_State *state) { (void)state; }
void register_spoof_bindings(lua_State *state) { (void)state; }

static void check(bool condition, const char *name) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", name); exit(1); }
}
static void *run(void *source) {
    @autoreleasepool { thread_result = lua_run_script(source); }
    return NULL;
}
static void timeout_handler(int signal_number) { (void)signal_number; _exit(2); }
static void cancel_test(const char *source) {
    atomic_store(&stop_flag, false);
    pthread_t thread;
    check(pthread_create(&thread, NULL, run, (void *)source) == 0, "worker starts");
    usleep(100000);
    NSDate *before = NSDate.date;
    atomic_store(&stop_flag, true);
    alarm(5);
    pthread_join(thread, NULL);
    alarm(0);
    check(thread_result != 0, "cancel returns a Lua error");
    check(-[before timeIntervalSinceNow] < 2, "cancel completes promptly");
    atomic_store(&stop_flag, false);
}
int main(void) {
    @autoreleasepool {
        signal(SIGALRM, timeout_handler);
        lua_bridge_init();
        int base = lua_gettop(lua_bridge_state());
        check(lua_run_script("assert(6*7==42); log('ready'); sleep(5)") == 0, "valid program");
        check(lua_run_script("this is ! not Lua") != 0, "syntax error is reported");
        check(lua_run_script("error('expected')") != 0, "runtime error is reported");
        cancel_test("while true do end");
        cancel_test("sleep(60000)");
        check(lua_run_script("assert(2+2==4)") == 0, "VM reusable after errors and cancellation");
        check(lua_gettop(lua_bridge_state()) == base, "VM stack restored between runs");
        puts("Lua runtime and cancellation tests passed");
    }
    return 0;
}
