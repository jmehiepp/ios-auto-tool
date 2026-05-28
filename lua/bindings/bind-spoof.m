#import "../../spoof/spoof-config.h"
#import <lua/lua.h>
#import <lua/lauxlib.h>

// spoof.enable(module, value)
static int l_enable(lua_State *L) {
    const char *mod = luaL_checkstring(L, 1);
    NSString *key = @(mod);
    if (lua_isnoneornil(L, 2)) {
        [[SpoofConfig shared] setEnabled:YES forModule:key];
    } else if (lua_type(L, 2) == LUA_TSTRING) {
        [[SpoofConfig shared] setValue:@(lua_tostring(L, 2)) forModule:key];
    } else if (lua_type(L, 2) == LUA_TNUMBER) {
        [[SpoofConfig shared] setValue:@(lua_tonumber(L, 2)) forModule:key];
    } else if (lua_type(L, 2) == LUA_TBOOLEAN) {
        [[SpoofConfig shared] setValue:@(lua_toboolean(L, 2)) forModule:key];
    } else if (lua_type(L, 2) == LUA_TTABLE) {
        // Convert Lua table to NSDictionary
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        lua_pushnil(L);
        while (lua_next(L, 2)) {
            NSString *k = lua_type(L, -2) == LUA_TSTRING ? @(lua_tostring(L, -2)) : nil;
            if (k) {
                if (lua_type(L, -1) == LUA_TNUMBER) d[k] = @(lua_tonumber(L, -1));
                else if (lua_type(L, -1) == LUA_TSTRING) d[k] = @(lua_tostring(L, -1));
            }
            lua_pop(L, 1);
        }
        [[SpoofConfig shared] setValue:d forModule:key];
    }
    return 0;
}

// spoof.disable(module)
static int l_disable(lua_State *L) {
    const char *mod = luaL_checkstring(L, 1);
    [[SpoofConfig shared] setEnabled:NO forModule:@(mod)];
    return 0;
}

// spoof.reset()
static int l_reset(lua_State *L) {
    (void)L;
    [[SpoofConfig shared] reset];
    return 0;
}

// spoof.reload()
static int l_reload(lua_State *L) {
    (void)L;
    [[SpoofConfig shared] reload];
    return 0;
}

// spoof.isEnabled(module) -> bool
static int l_is_enabled(lua_State *L) {
    const char *mod = luaL_checkstring(L, 1);
    lua_pushboolean(L, [[SpoofConfig shared] isEnabled:@(mod)]);
    return 1;
}

// spoof.applyPreset(name) — built-in device presets
static int l_apply_preset(lua_State *L) {
    const char *name = luaL_checkstring(L, 1);
    SpoofConfig *cfg = [SpoofConfig shared];
    if (strcmp(name, "iphone14_pro_max") == 0) {
        [cfg setValue:@"iPhone15,3"   forModule:@"device_model"];
        [cfg setValue:@"17.2.1"       forModule:@"ios_version"];
        [cfg setValue:@{@"w":@430, @"h":@932, @"scale":@3} forModule:@"screen_resolution"];
    } else if (strcmp(name, "iphone13") == 0) {
        [cfg setValue:@"iPhone14,5"   forModule:@"device_model"];
        [cfg setValue:@"16.7.2"       forModule:@"ios_version"];
        [cfg setValue:@{@"w":@390, @"h":@844, @"scale":@3} forModule:@"screen_resolution"];
    } else {
        lua_pushstring(L, "unknown preset");
        return lua_error(L);
    }
    return 0;
}

static const luaL_Reg spoof_lib[] = {
    {"enable",      l_enable},
    {"disable",     l_disable},
    {"reset",       l_reset},
    {"reload",      l_reload},
    {"isEnabled",   l_is_enabled},
    {"applyPreset", l_apply_preset},
    {NULL, NULL}
};

void register_spoof_bindings(lua_State *L) {
    luaL_newlib(L, spoof_lib);
    lua_setglobal(L, "spoof");
}
