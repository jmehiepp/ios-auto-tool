#import <Foundation/Foundation.h>
#import "../engine/touch/recorder.h"
#include <lua/lua.h>
#include <lua/lauxlib.h>
#include <lua/lualib.h>
#include <assert.h>
#include <unistd.h>
static int calls,sleeps;
static int tap(lua_State *L) { assert(lua_tonumber(L,1)==10.5 && lua_tonumber(L,2)==20.25);calls++;return 0; }
static int swipe(lua_State *L) { assert(lua_tonumber(L,3)==30.5 && lua_tonumber(L,5)==300);calls++;return 0; }
static int sleep_ms(lua_State *L) { assert(lua_tonumber(L,1)>=50);sleeps++;return 0; }
int main(void) {
    @autoreleasepool {
        recorder_start();recorder_log_tap(10.5,20.25);usleep(80000);recorder_log_swipe(10.5,20.25,30.5,40.25);
        NSString *code=recorder_stop_and_codegen(); assert(!recorder_is_recording() && recorder_get_events().count==2);
        lua_State *L=luaL_newstate();luaL_openlibs(L);
        lua_register(L,"tap",tap);lua_register(L,"swipe",swipe);lua_register(L,"sleep",sleep_ms);
        if (luaL_dostring(L,code.UTF8String)!=0) { fprintf(stderr,"%s\n",lua_tostring(L,-1));return 1; }
        assert(calls==2 && sleeps==1);lua_close(L);recorder_clear();
        puts("Recorder generated Lua execution tests passed");
    }
    return 0;
}
