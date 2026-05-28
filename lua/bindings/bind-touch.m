#import "bind-touch.h"
#import "../../engine/touch/gesture.h"
#import "../../engine/touch/touch-inject.h"
#import <lua/lua.h>
#import <lua/lauxlib.h>

static int lua_tap(lua_State *L) {
    double x = luaL_checknumber(L, 1);
    double y = luaL_checknumber(L, 2);
    c_tap(x, y);
    return 0;
}

static int lua_double_tap(lua_State *L) {
    double x = luaL_checknumber(L, 1);
    double y = luaL_checknumber(L, 2);
    c_double_tap(x, y);
    return 0;
}

static int lua_long_press(lua_State *L) {
    double x   = luaL_checknumber(L, 1);
    double y   = luaL_checknumber(L, 2);
    int dur    = (int)luaL_optinteger(L, 3, 1000);
    c_long_press(x, y, dur);
    return 0;
}

static int lua_swipe(lua_State *L) {
    double x1  = luaL_checknumber(L, 1);
    double y1  = luaL_checknumber(L, 2);
    double x2  = luaL_checknumber(L, 3);
    double y2  = luaL_checknumber(L, 4);
    int dur    = (int)luaL_optinteger(L, 5, 300);
    c_swipe(x1, y1, x2, y2, dur);
    return 0;
}

static int lua_touch_down(lua_State *L) {
    double x         = luaL_checknumber(L, 1);
    double y         = luaL_checknumber(L, 2);
    uint32_t finger  = (uint32_t)luaL_optinteger(L, 3, 1);
    c_touch_down(x, y, finger);
    return 0;
}

static int lua_touch_move(lua_State *L) {
    double x         = luaL_checknumber(L, 1);
    double y         = luaL_checknumber(L, 2);
    uint32_t finger  = (uint32_t)luaL_optinteger(L, 3, 1);
    c_touch_move(x, y, finger);
    return 0;
}

static int lua_touch_up(lua_State *L) {
    double x         = luaL_checknumber(L, 1);
    double y         = luaL_checknumber(L, 2);
    uint32_t finger  = (uint32_t)luaL_optinteger(L, 3, 1);
    c_touch_up(x, y, finger);
    return 0;
}

void register_touch_bindings(lua_State *L) {
    touch_inject_init();
    lua_register(L, "tap",        lua_tap);
    lua_register(L, "doubleTap",  lua_double_tap);
    lua_register(L, "longPress",  lua_long_press);
    lua_register(L, "swipe",      lua_swipe);
    lua_register(L, "touchDown",  lua_touch_down);
    lua_register(L, "touchMove",  lua_touch_move);
    lua_register(L, "touchUp",    lua_touch_up);
}
