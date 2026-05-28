#import "bind-system.h"
#import "../../engine/system/shell-exec.h"
#import "../../engine/system/file-ops.h"
#import "../../engine/system/http-client.h"
#import <lua/lua.h>
#import <lua/lauxlib.h>
#import <Foundation/Foundation.h>
#include <stdlib.h>
#include <string.h>

#define SCRIPTS_DIR "/Library/IOSAutoTool/scripts"

// ---------- Shell ----------

static int lua_shell(lua_State *L) {
    const char *cmd = luaL_checkstring(L, 1);
    int exit_code = 0;
    char *out = c_shell_exec_output(cmd, &exit_code);
    lua_pushstring(L, out ?: "");
    lua_pushinteger(L, exit_code);
    free(out);
    return 2;
}

// ---------- File ops ----------

static int lua_read_file(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);
    NSString *s = c_read_file(path);
    if (s) lua_pushstring(L, s.UTF8String);
    else   lua_pushnil(L);
    return 1;
}

static int lua_write_file(lua_State *L) {
    const char *path    = luaL_checkstring(L, 1);
    const char *content = luaL_checkstring(L, 2);
    lua_pushboolean(L, c_write_file(path, content));
    return 1;
}

static int lua_append_file(lua_State *L) {
    const char *path    = luaL_checkstring(L, 1);
    const char *content = luaL_checkstring(L, 2);
    lua_pushboolean(L, c_append_file(path, content));
    return 1;
}

static int lua_delete_file(lua_State *L) {
    lua_pushboolean(L, c_delete_file(luaL_checkstring(L, 1)));
    return 1;
}

static int lua_file_exists(lua_State *L) {
    lua_pushboolean(L, c_file_exists(luaL_checkstring(L, 1)));
    return 1;
}

static int lua_make_dir(lua_State *L) {
    lua_pushboolean(L, c_make_dir(luaL_checkstring(L, 1)));
    return 1;
}

static int lua_copy_file(lua_State *L) {
    lua_pushboolean(L, c_copy_file(luaL_checkstring(L, 1),
                                   luaL_checkstring(L, 2)));
    return 1;
}

static int lua_move_file(lua_State *L) {
    lua_pushboolean(L, c_move_file(luaL_checkstring(L, 1),
                                   luaL_checkstring(L, 2)));
    return 1;
}

static int lua_file_size(lua_State *L) {
    lua_pushinteger(L, c_file_size(luaL_checkstring(L, 1)));
    return 1;
}

static int lua_list_dir(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);
    int count = 0;
    DirEntry *entries = c_list_dir(path, &count);
    lua_createtable(L, count, 0);
    for (int i = 0; i < count; i++) {
        lua_createtable(L, 0, 4);
        lua_pushstring(L,  entries[i].name);     lua_setfield(L, -2, "name");
        lua_pushboolean(L, entries[i].is_dir);   lua_setfield(L, -2, "isDir");
        lua_pushinteger(L, entries[i].size);     lua_setfield(L, -2, "size");
        lua_pushnumber(L,  entries[i].modified); lua_setfield(L, -2, "modified");
        lua_rawseti(L, -2, i + 1);
    }
    free(entries);
    return 1;
}

// ---------- HTTP ----------

static int lua_http_get(lua_State *L) {
    const char *url     = luaL_checkstring(L, 1);
    lua_Number  timeout = luaL_optnumber(L, 2, 30.0);
    HttpResponse r = c_http_get(url, timeout);
    lua_pushstring(L,  r.body ?: "");
    lua_pushinteger(L, r.status_code);
    http_response_free(&r);
    return 2;
}

static int lua_http_post(lua_State *L) {
    const char *url     = luaL_checkstring(L, 1);
    const char *body    = luaL_checkstring(L, 2);
    lua_Number  timeout = luaL_optnumber(L, 3, 30.0);
    HttpResponse r = c_http_post_json(url, body, timeout);
    lua_pushstring(L,  r.body ?: "");
    lua_pushinteger(L, r.status_code);
    http_response_free(&r);
    return 2;
}

static int lua_http_post_form(lua_State *L) {
    const char *url     = luaL_checkstring(L, 1);
    luaL_checktype(L, 2, LUA_TTABLE);
    lua_Number  timeout = luaL_optnumber(L, 3, 30.0);

    NSMutableDictionary *fields = [NSMutableDictionary dictionary];
    lua_pushnil(L);
    while (lua_next(L, 2)) {
        NSString *k = [NSString stringWithUTF8String:lua_tostring(L, -2) ?: ""];
        NSString *v = [NSString stringWithUTF8String:lua_tostring(L, -1) ?: ""];
        fields[k] = v;
        lua_pop(L, 1);
    }
    HttpResponse r = c_http_post_form(url, fields, timeout);
    lua_pushstring(L,  r.body ?: "");
    lua_pushinteger(L, r.status_code);
    http_response_free(&r);
    return 2;
}

static int lua_http_request(lua_State *L) {
    luaL_checktype(L, 1, LUA_TTABLE);

    NSMutableDictionary *opts = [NSMutableDictionary dictionary];

    lua_getfield(L, 1, "url");
    if (lua_isstring(L, -1)) opts[@"url"] = @(lua_tostring(L, -1));
    lua_pop(L, 1);

    lua_getfield(L, 1, "method");
    if (lua_isstring(L, -1)) opts[@"method"] = @(lua_tostring(L, -1));
    lua_pop(L, 1);

    lua_getfield(L, 1, "body");
    if (lua_isstring(L, -1)) opts[@"body"] = @(lua_tostring(L, -1));
    lua_pop(L, 1);

    lua_getfield(L, 1, "timeout");
    if (lua_isnumber(L, -1)) opts[@"timeout"] = @(lua_tonumber(L, -1));
    lua_pop(L, 1);

    lua_getfield(L, 1, "headers");
    if (lua_istable(L, -1)) {
        NSMutableDictionary *hdrs = [NSMutableDictionary dictionary];
        lua_pushnil(L);
        while (lua_next(L, -2)) {
            hdrs[@(lua_tostring(L, -2) ?: "")] = @(lua_tostring(L, -1) ?: "");
            lua_pop(L, 1);
        }
        opts[@"headers"] = hdrs;
    }
    lua_pop(L, 1);

    HttpResponse r = c_http_request(opts);
    lua_pushstring(L,  r.body ?: "");
    lua_pushinteger(L, r.status_code);
    http_response_free(&r);
    return 2;
}

static int lua_download_file(lua_State *L) {
    const char *url  = luaL_checkstring(L, 1);
    const char *dest = luaL_checkstring(L, 2);
    lua_Number  to   = luaL_optnumber(L, 3, 60.0);
    lua_pushboolean(L, c_download_file(url, dest, to) == 0);
    return 1;
}

// ---------- Path helpers ----------

static int lua_script_dir(lua_State *L) {
    lua_pushstring(L, SCRIPTS_DIR);
    return 1;
}
static int lua_home_dir(lua_State *L) {
    lua_pushstring(L, "/var/mobile");
    return 1;
}
static int lua_tmp_dir(lua_State *L) {
    lua_pushstring(L, "/tmp");
    return 1;
}

void register_system_bindings(lua_State *L) {
    lua_register(L, "shell",         lua_shell);
    lua_register(L, "readFile",      lua_read_file);
    lua_register(L, "writeFile",     lua_write_file);
    lua_register(L, "appendFile",    lua_append_file);
    lua_register(L, "deleteFile",    lua_delete_file);
    lua_register(L, "fileExists",    lua_file_exists);
    lua_register(L, "listDir",       lua_list_dir);
    lua_register(L, "makeDir",       lua_make_dir);
    lua_register(L, "copyFile",      lua_copy_file);
    lua_register(L, "moveFile",      lua_move_file);
    lua_register(L, "fileSize",      lua_file_size);
    lua_register(L, "httpGet",       lua_http_get);
    lua_register(L, "httpPost",      lua_http_post);
    lua_register(L, "httpPostForm",  lua_http_post_form);
    lua_register(L, "httpRequest",   lua_http_request);
    lua_register(L, "downloadFile",  lua_download_file);
    lua_register(L, "scriptDir",     lua_script_dir);
    lua_register(L, "homeDir",       lua_home_dir);
    lua_register(L, "tmpDir",        lua_tmp_dir);
}
