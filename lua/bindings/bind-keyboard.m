#import "bind-keyboard.h"
#import "../../engine/keyboard/text-input.h"
#import "../../engine/keyboard/key-press.h"
#import <lua/lua.h>
#import <lua/lauxlib.h>
#import <Foundation/Foundation.h>

static int lua_type_text(lua_State *L) {
    const char *s = luaL_checkstring(L, 1);
    c_type_text([NSString stringWithUTF8String:s]);
    return 0;
}

static int lua_keyboard_type(lua_State *L) {
    const char *t = luaL_checkstring(L, 1);
    c_keyboard_type(t);
    return 0;
}

static int lua_set_keyboard_language(lua_State *L) {
    const char *lang = luaL_checkstring(L, 1);
    c_set_keyboard_language(lang);
    return 0;
}

static int lua_press_home(lua_State *L) {
    (void)L;
    c_press_home();
    return 0;
}

static int lua_press_lock(lua_State *L) {
    (void)L;
    c_press_lock();
    return 0;
}

static int lua_press_volume(lua_State *L) {
    const char *dir = luaL_checkstring(L, 1);
    c_press_volume(strcmp(dir, "up") == 0);
    return 0;
}

static int lua_press_mute(lua_State *L) {
    (void)L;
    c_press_mute();
    return 0;
}

static int lua_set_clipboard(lua_State *L) {
    const char *s = luaL_checkstring(L, 1);
    c_set_clipboard([NSString stringWithUTF8String:s]);
    return 0;
}

static int lua_get_clipboard(lua_State *L) {
    NSString *text = c_get_clipboard();
    lua_pushstring(L, text.UTF8String ?: "");
    return 1;
}

static int lua_clear_clipboard(lua_State *L) {
    (void)L;
    c_clear_clipboard();
    return 0;
}

void register_keyboard_bindings(lua_State *L) {
    lua_register(L, "typeText",            lua_type_text);
    lua_register(L, "keyboardType",        lua_keyboard_type);
    lua_register(L, "setKeyboardLanguage", lua_set_keyboard_language);
    lua_register(L, "pressHome",           lua_press_home);
    lua_register(L, "pressLock",           lua_press_lock);
    lua_register(L, "pressVolume",         lua_press_volume);
    lua_register(L, "pressMute",           lua_press_mute);
    lua_register(L, "setClipboard",        lua_set_clipboard);
    lua_register(L, "getClipboard",        lua_get_clipboard);
    lua_register(L, "clearClipboard",      lua_clear_clipboard);
}
