#import <Foundation/Foundation.h>
#import "../lua/bindings/bind-data.h"
#include <lua/lauxlib.h>
#include <lua/lualib.h>
int main(void) {
    @autoreleasepool {
        lua_State *L = luaL_newstate(); luaL_openlibs(L); register_data_bindings(L);
        if (luaL_dofile(L, "tests/data-bindings-tests.lua") != 0 || luaL_dofile(L, "tests/legacy-contract-tests.lua") != 0) {
            fprintf(stderr, "%s\n", lua_tostring(L, -1)); lua_close(L); return 1;
        }
        lua_close(L);
        puts("Lua data modules and legacy contract tests passed");
    }
    return 0;
}
