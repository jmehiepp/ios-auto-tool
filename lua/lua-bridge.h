#pragma once
#include <lua/lua.h>
#include <lua/lauxlib.h>
#include <lua/lualib.h>

void       lua_bridge_init(void);
int        lua_run_script(const char *code);
lua_State *lua_bridge_state(void);
