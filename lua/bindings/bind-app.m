#import "bind-app.h"
#import "../../engine/app/app-control.h"
#import "../../engine/app/multi-account.h"
#import <lua/lua.h>
#import <lua/lauxlib.h>
#include <stdlib.h>

static int lua_app_run(lua_State *L) {
    const char *bid = luaL_checkstring(L, 1);
    c_app_run(bid);
    return 0;
}

static int lua_app_kill(lua_State *L) {
    const char *bid = luaL_checkstring(L, 1);
    c_app_kill(bid);
    return 0;
}

static int lua_app_kill_all(lua_State *L) {
    (void)L;
    c_app_kill_all();
    return 0;
}

static int lua_clear_switcher(lua_State *L) {
    (void)L;
    c_clear_switcher();
    return 0;
}

static int lua_get_front_app(lua_State *L) {
    const char *bid = c_get_front_app();
    lua_pushstring(L, bid ? bid : "");
    return 1;
}

static int lua_get_running_apps(lua_State *L) {
    int count = 0;
    AppInfo *apps = c_get_running_apps(&count);
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
    const char *bid  = luaL_checkstring(L, 1);
    int         slot = (int)luaL_checkinteger(L, 2);
    save_account(bid, slot);
    return 0;
}

static int lua_switch_account(lua_State *L) {
    const char *bid  = luaL_checkstring(L, 1);
    int         slot = (int)luaL_checkinteger(L, 2);
    switch_account(bid, slot);
    return 0;
}

static int lua_delete_account(lua_State *L) {
    const char *bid  = luaL_checkstring(L, 1);
    int         slot = (int)luaL_checkinteger(L, 2);
    delete_account(bid, slot);
    return 0;
}

static int lua_name_account(lua_State *L) {
    const char *bid   = luaL_checkstring(L, 1);
    int         slot  = (int)luaL_checkinteger(L, 2);
    const char *label = luaL_checkstring(L, 3);
    name_account(bid, slot, label);
    return 0;
}

static int lua_list_accounts(lua_State *L) {
    const char *bid = luaL_checkstring(L, 1);
    int count = 0;
    AccountSlot *slots = list_accounts(bid, &count);
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
    const char *bid = luaL_checkstring(L, 1);
    clear_keychain_for_app(bid);
    return 0;
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
