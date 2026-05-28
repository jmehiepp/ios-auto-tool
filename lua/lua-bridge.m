#import "lua-bridge.h"
#import "../daemon/logger.h"
#import "../daemon/script-runner.h"
#import "bindings/bind-touch.h"
#import "bindings/bind-screen.h"
#import "bindings/bind-app.h"
#import "bindings/bind-keyboard.h"
#import "bindings/bind-system.h"
#import "bindings/bind-spoof.h"
#import <Foundation/Foundation.h>
#import <pthread.h>

static lua_State      *L          = NULL;
static pthread_mutex_t lua_mutex  = PTHREAD_MUTEX_INITIALIZER;

// ── built-in globals ────────────────────────────────────────────────

static int builtin_log(lua_State *state) {
    const char *msg = luaL_checkstring(state, 1);
    script_send_log("LUA", msg);
    return 0;
}

static int builtin_sleep(lua_State *state) {
    lua_Integer ms = luaL_checkinteger(state, 1);
    if (ms > 0) usleep((useconds_t)(ms * 1000));
    return 0;
}

// ── init ─────────────────────────────────────────────────────────────

void lua_bridge_init(void) {
    L = luaL_newstate();
    luaL_openlibs(L);

    lua_register(L, "log",   builtin_log);
    lua_register(L, "sleep", builtin_sleep);

    register_touch_bindings(L);
    register_screen_bindings(L);
    register_app_bindings(L);
    register_keyboard_bindings(L);
    register_system_bindings(L);
    register_spoof_bindings(L);

    // Load stdlib helpers
    NSString *stdlibPath = @"/Library/IOSAutoTool/lua/stdlib/utils.lua";
    if ([[NSFileManager defaultManager] fileExistsAtPath:stdlibPath]) {
        if (luaL_dofile(L, stdlibPath.UTF8String) != LUA_OK) {
            log_warn("stdlib load warning: %s", lua_tostring(L, -1));
            lua_pop(L, 1);
        }
    }

    log_info("Lua bridge initialized — LuaJIT ready");
}

// ── run ──────────────────────────────────────────────────────────────

int lua_run_script(const char *code) {
    pthread_mutex_lock(&lua_mutex);

    // Wrap user code in pcall so errors return cleanly instead of crashing
    NSString *wrapped = [NSString stringWithFormat:
        @"local _ok, _err = pcall(function()\n"
        "%s\n"
        "end)\n"
        "if not _ok then\n"
        "  log('[ERROR] ' .. tostring(_err))\n"
        "  return 1\n"
        "end\n"
        "return 0",
        code];

    int rc = 0;
    if (luaL_dostring(L, wrapped.UTF8String) != LUA_OK) {
        const char *err = lua_tostring(L, -1);
        log_error("Lua fatal: %s", err ?: "(unknown)");
        lua_pop(L, 1);
        rc = 1;
    } else if (lua_isnumber(L, -1)) {
        rc = (int)lua_tointeger(L, -1);
        lua_pop(L, 1);
    }

    pthread_mutex_unlock(&lua_mutex);
    return rc;
}

lua_State *lua_bridge_state(void) {
    return L;
}
