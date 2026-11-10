#import "lua-bridge.h"
#import "../daemon/logger.h"
#import "../daemon/script-runner.h"
#import "bindings/bind-touch.h"
#import "bindings/bind-screen.h"
#import "bindings/bind-app.h"
#import "bindings/bind-keyboard.h"
#import "bindings/bind-system.h"
#import "bindings/bind-spoof.h"
#import "bindings/bind-data.h"
#import <Foundation/Foundation.h>
#import <pthread.h>
#import "../daemon/runtime-paths.h"
#include <lua/luajit.h>
#include <unistd.h>
#include <math.h>
#include <time.h>

static lua_State      *L          = NULL;
static pthread_mutex_t lua_mutex  = PTHREAD_MUTEX_INITIALIZER;

// ── built-in globals ────────────────────────────────────────────────

static int builtin_log(lua_State *state) {
    lua_getglobal(state, "tostring");
    if (lua_gettop(state) == 1) lua_pushnil(state); else lua_pushvalue(state, 1);
    lua_call(state, 1, 1);
    const char *msg = lua_tostring(state, -1);
    if (!msg) return luaL_error(state, "tostring must return a string");
    script_send_log("LUA", msg);
    return 0;
}

static int builtin_microsleep(lua_State *state) {
    double value = luaL_checknumber(state, 1);
    if (!isfinite(value) || value < 0 || value > 86400000000.0)
        return luaL_argerror(state, 1, "microseconds must be finite and 0..86400000000");
    uint64_t remaining = (uint64_t)ceil(value);
    while (remaining) {
        if (script_should_stop()) return luaL_error(state, "script stopped");
        useconds_t step = remaining > 50000 ? 50000 : (useconds_t)remaining;
        usleep(step); remaining -= step;
    }
    return 0;
}
static int builtin_clock(lua_State *state) {
    struct timespec value; clock_gettime(CLOCK_MONOTONIC, &value);
    lua_pushnumber(state, value.tv_sec * 1000.0 + value.tv_nsec / 1000000.0); return 1;
}
static int legacy_factory = LUA_NOREF;

static int builtin_sleep(lua_State *state) {
    lua_Integer ms = luaL_checkinteger(state, 1);
    if (ms < 0 || ms > 86400000) return luaL_error(state, "sleep must be 0..86400000 milliseconds");
    while (ms > 0) {
        if (script_should_stop()) return luaL_error(state, "script stopped");
        lua_Integer step = ms > 50 ? 50 : ms;
        usleep((useconds_t)(step * 1000));
        ms -= step;
    }
    return 0;
}

static void stop_hook(lua_State *state, lua_Debug *debug) {
    (void)debug;
    if (script_should_stop()) luaL_error(state, "script stopped");
}

// ── init ─────────────────────────────────────────────────────────────

void lua_bridge_init(void) {
    L = luaL_newstate();
    luaL_openlibs(L);
    luaJIT_setmode(L, 0, LUAJIT_MODE_ENGINE | LUAJIT_MODE_OFF);

    lua_register(L, "log",   builtin_log);
    lua_register(L, "sleep", builtin_sleep);
    lua_register(L, "usleep", builtin_microsleep);
    lua_register(L, "monotonicMillis", builtin_clock);

    register_touch_bindings(L);
    register_screen_bindings(L);
    register_app_bindings(L);
    register_keyboard_bindings(L);
    register_system_bindings(L);
    register_spoof_bindings(L);
    register_data_bindings(L);

    // Load stdlib helpers
    NSString *stdlibPath = iat_resource_path(@"lua/stdlib/utils.lua");
    if ([[NSFileManager defaultManager] fileExistsAtPath:stdlibPath]) {
        if (luaL_dofile(L, stdlibPath.UTF8String) != LUA_OK) {
            log_warn("stdlib load warning: %s", lua_tostring(L, -1));
            lua_pop(L, 1);
        }
    }

    NSString *legacyPath = iat_resource_path(@"lua/stdlib/legacy.lua");
    if (luaL_dofile(L, legacyPath.UTF8String) == LUA_OK && lua_isfunction(L, -1)) {
        legacy_factory = luaL_ref(L, LUA_REGISTRYINDEX);
    } else {
        log_error("legacy compatibility unavailable: %s", lua_tostring(L, -1) ?: "invalid factory");
        lua_pop(L, 1);
    }

    log_info("Lua bridge initialized — LuaJIT ready");
}

// ── run ──────────────────────────────────────────────────────────────

int lua_run_script(const char *code) {
    pthread_mutex_lock(&lua_mutex);
    int base = lua_gettop(L);
    lua_sethook(L, stop_hook, LUA_MASKCOUNT | LUA_MASKLINE, 1000);

    int rc = 0;
    // Opt in explicitly: the same file works through IDE, scheduler, widget and CLI.
    const char *start = code ?: "";
    if (!strncmp(start, "\xef\xbb\xbf", 3)) start += 3;
    bool legacy = !strncmp(start, "--!iosautomate", 14) &&
        (start[14] == '\n' || start[14] == '\r' || start[14] == 0);
    int status = luaL_loadbuffer(L, start, strlen(start), "@script");
    if (status == LUA_OK) {
        if (legacy) {
            if (legacy_factory == LUA_NOREF) {
                lua_pushstring(L, "legacy compatibility module is unavailable"); status = LUA_ERRRUN;
            } else {
                lua_rawgeti(L, LUA_REGISTRYINDEX, legacy_factory);
                lua_pushvalue(L, LUA_GLOBALSINDEX);
                status = lua_pcall(L, 1, 1, 0);
                if (status == LUA_OK) lua_setfenv(L, -2);
            }
        }
        if (status == LUA_OK) status = lua_pcall(L, 0, 0, 0);
    }
    if (status != LUA_OK) {
        const char *err = lua_tostring(L, -1);
        log_error("Lua fatal: %s", err ?: "(unknown)");
        lua_pop(L, 1);
        rc = 1;
    }

    lua_sethook(L, NULL, 0, 0);
    reset_touch_bindings();
    reset_screen_bindings();
    lua_settop(L, base);
    pthread_mutex_unlock(&lua_mutex);
    return rc;
}

lua_State *lua_bridge_state(void) {
    return L;
}
