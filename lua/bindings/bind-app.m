#import "bind-app.h"
#import "../../engine/app/app-control.h"
#import "../../engine/app/multi-account.h"
#import <lua/lua.h>
#import <lua/lauxlib.h>
#include <stdlib.h>
#include <string.h>

static const char *checked_text(lua_State *L, int index) {
    size_t length = 0;
    const char *value = luaL_checklstring(L, index, &length);
    if (strlen(value) != length) luaL_argerror(L, index, "embedded NUL is not allowed");
    return value;
}

static int lua_app_run(lua_State *L) {
    const char *bid = checked_text(L, 1);
    if (!c_app_run(bid)) return luaL_error(L, "%s", c_app_last_error());
    lua_pushboolean(L, 1); return 1;
}

static int lua_app_kill(lua_State *L) {
    const char *bid = checked_text(L, 1);
    if (!c_app_kill(bid)) return luaL_error(L, "%s", c_app_last_error());
    lua_pushboolean(L, 1); return 1;
}

static int lua_app_kill_all(lua_State *L) {
    (void)L;
    if (!c_app_kill_all()) return luaL_error(L, "%s", c_app_last_error());
    lua_pushboolean(L, 1); return 1;
}

static int lua_clear_switcher(lua_State *L) {
    (void)L;
    if (!c_clear_switcher()) return luaL_error(L, "%s", c_app_last_error());
    lua_pushboolean(L, 1); return 1;
}

static int lua_get_front_app(lua_State *L) {
    const char *bid = c_get_front_app();
    if (!bid) return luaL_error(L, "%s", c_app_last_error());
    lua_pushstring(L, bid);
    return 1;
}

static int lua_get_running_apps(lua_State *L) {
    int count = 0;
    AppInfo *apps = c_get_running_apps(&count);
    if (count < 0) return luaL_error(L, "%s", c_app_last_error());
    lua_createtable(L, count, 0);
    for (int i = 0; i < count; i++) {
        lua_createtable(L, 0, 3);
        lua_pushstring(L, apps[i].bundleId); lua_setfield(L, -2, "bundleId");
        lua_pushstring(L, apps[i].name);     lua_setfield(L, -2, "name");
        lua_pushinteger(L, apps[i].pid);     lua_setfield(L, -2, "pid");
        lua_rawseti(L, -2, i + 1);
    }
    free(apps);
    return 1;
}

static int lua_save_account(lua_State *L) {
    const char *bid  = checked_text(L, 1);
    lua_Integer value = luaL_checkinteger(L, 2);
    if (value < 1 || value > 9999) return luaL_argerror(L, 2, "slot must be 1...9999");
    if (!save_account(bid, (int)value)) return luaL_error(L, "%s", account_last_error());
    lua_pushboolean(L, 1); return 1;
}

static int lua_switch_account(lua_State *L) {
    const char *bid  = checked_text(L, 1);
    lua_Integer value = luaL_checkinteger(L, 2);
    if (value < 1 || value > 9999) return luaL_argerror(L, 2, "slot must be 1...9999");
    if (!switch_account(bid, (int)value)) return luaL_error(L, "%s", account_last_error());
    lua_pushboolean(L, 1); return 1;
}

static int lua_delete_account(lua_State *L) {
    const char *bid  = checked_text(L, 1);
    lua_Integer value = luaL_checkinteger(L, 2);
    if (value < 1 || value > 9999) return luaL_argerror(L, 2, "slot must be 1...9999");
    if (!delete_account(bid, (int)value)) return luaL_error(L, "%s", account_last_error());
    lua_pushboolean(L, 1); return 1;
}

static int lua_name_account(lua_State *L) {
    const char *bid   = checked_text(L, 1);
    lua_Integer value = luaL_checkinteger(L, 2);
    if (value < 1 || value > 9999) return luaL_argerror(L, 2, "slot must be 1...9999");
    const char *label = checked_text(L, 3);
    if (!name_account(bid, (int)value, label)) return luaL_error(L, "%s", account_last_error());
    lua_pushboolean(L, 1); return 1;
}

static int lua_list_accounts(lua_State *L) {
    const char *bid = checked_text(L, 1);
    int count = 0;
    AccountSlot *slots = list_accounts(bid, &count);
    if (count < 0) return luaL_error(L, "%s", account_last_error());
    lua_createtable(L, count, 0);
    for (int i = 0; i < count; i++) {
        lua_createtable(L, 0, 3);
        lua_pushinteger(L, slots[i].slot);       lua_setfield(L, -2, "slot");
        lua_pushstring(L, slots[i].name);        lua_setfield(L, -2, "name");
        lua_pushnumber(L, slots[i].saved_at);    lua_setfield(L, -2, "savedAt");
        lua_rawseti(L, -2, i + 1);
    }
    free(slots);
    return 1;
}

static int lua_clear_keychain(lua_State *L) {
    const char *bid = checked_text(L, 1);
    if (!clear_keychain_for_app(bid)) return luaL_error(L, "%s", account_last_error());
    lua_pushboolean(L, 1); return 1;
}

void register_app_bindings(lua_State *L) {
    lua_register(L, "appRun",          lua_app_run);
    lua_register(L, "appKill",         lua_app_kill);
    lua_register(L, "appKillAll",      lua_app_kill_all);
    lua_register(L, "clearSwitcher",   lua_clear_switcher);
    lua_register(L, "getFrontApp",     lua_get_front_app);
    lua_register(L, "getRunningApps",  lua_get_running_apps);
    lua_register(L, "saveAccount",     lua_save_account);
    lua_register(L, "switchAccount",   lua_switch_account);
    lua_register(L, "deleteAccount",   lua_delete_account);
    lua_register(L, "nameAccount",     lua_name_account);
    lua_register(L, "listAccounts",    lua_list_accounts);
    lua_register(L, "clearKeychain",   lua_clear_keychain);
}
