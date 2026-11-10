#import "bind-spoof.h"
#import "../../spoof/spoof-config.h"
#import <CoreFoundation/CoreFoundation.h>
#import <lua/lauxlib.h>
#import <math.h>
#import <string.h>

static int AbsoluteIndex(lua_State *L, int index) {
    return index > 0 || index <= LUA_REGISTRYINDEX ? index : lua_gettop(L) + index + 1;
}
static size_t TableLength(lua_State *L, int index) {
#if LUA_VERSION_NUM >= 502
    return lua_rawlen(L, index);
#else
    return lua_objlen(L, index);
#endif
}
static id ReadObject(lua_State *L, int index, unsigned depth, NSString **error) {
    index = AbsoluteIndex(L, index);
    if (depth > 16) { *error = @"configuration nesting exceeds 16 levels"; return nil; }
    switch (lua_type(L, index)) {
        case LUA_TBOOLEAN: return @(lua_toboolean(L, index) != 0);
        case LUA_TNUMBER: {
            double value = lua_tonumber(L, index);
            if (!isfinite(value)) { *error = @"configuration numbers must be finite"; return nil; }
            return @(value);
        }
        case LUA_TSTRING: {
            size_t size = 0;
            const char *bytes = lua_tolstring(L, index, &size);
            NSString *value = [[NSString alloc] initWithBytes:bytes length:size encoding:NSUTF8StringEncoding];
            if (!value) *error = @"configuration strings must be UTF-8";
            return value;
        }
        case LUA_TTABLE: {
            size_t length = TableLength(L, index);
            if (length > 10000) { *error = @"configuration array exceeds 10000 entries"; return nil; }
            NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
            NSMutableArray *array = [NSMutableArray arrayWithCapacity:length];
            for (size_t i = 0; i < length; i++) [array addObject:NSNull.null];
            lua_pushnil(L);
            while (lua_next(L, index)) {
                id value = ReadObject(L, -1, depth + 1, error);
                if (!value) { lua_pop(L, 2); return nil; }
                if (length) {
                    lua_Number number = lua_type(L, -2) == LUA_TNUMBER ? lua_tonumber(L, -2) : -1;
                    if (number < 1 || number > length || floor(number) != number) {
                        *error = @"mixed or sparse configuration tables are unsupported";
                        lua_pop(L, 2); return nil;
                    }
                    array[(NSUInteger)number - 1] = value;
                } else {
                    if (lua_type(L, -2) != LUA_TSTRING) {
                        *error = @"configuration object keys must be strings";
                        lua_pop(L, 2); return nil;
                    }
                    NSString *key = ReadObject(L, -2, depth + 1, error);
                    if (!key || dictionary.count > 10000) {
                        *error = @"invalid or oversized configuration object";
                        lua_pop(L, 2); return nil;
                    }
                    dictionary[key] = value;
                }
                lua_pop(L, 1);
            }
            if (length && [array containsObject:NSNull.null]) {
                *error = @"sparse configuration arrays are unsupported"; return nil;
            }
            return length ? array : dictionary;
        }
        default: *error = @"configuration accepts booleans, numbers, strings, arrays and objects"; return nil;
    }
}
static void PushObject(lua_State *L, id object) {
    if ([object isKindOfClass:NSDictionary.class]) {
        lua_newtable(L);
        for (NSString *key in object) {
            PushObject(L, object[key]);
            lua_setfield(L, -2, key.UTF8String);
        }
    } else if ([object isKindOfClass:NSArray.class]) {
        lua_newtable(L);
        lua_Integer index = 1;
        for (id item in object) { PushObject(L, item); lua_rawseti(L, -2, index++); }
    } else if ([object isKindOfClass:NSString.class]) {
        NSData *bytes = [object dataUsingEncoding:NSUTF8StringEncoding];
        lua_pushlstring(L, bytes.bytes, bytes.length);
    } else if ([object isKindOfClass:NSNumber.class]) {
        if (CFGetTypeID((__bridge CFTypeRef)object) == CFBooleanGetTypeID())
            lua_pushboolean(L, [object boolValue]);
        else lua_pushnumber(L, [object doubleValue]);
    } else lua_pushnil(L);
}
static int Save(lua_State *L, NSDictionary *configuration) {
    NSError *error = nil;
    if (![[SpoofConfig shared] setConfiguration:configuration error:&error])
        return luaL_error(L, "%s", error.localizedDescription.UTF8String ?: "cannot save device configuration");
    lua_pushboolean(L, 1);
    return 1;
}
static int SetModule(lua_State *L, BOOL enabled) {
    NSString *name = [NSString stringWithUTF8String:luaL_checkstring(L, 1)];
    if (!name) return luaL_error(L, "module name must be UTF-8");
    NSMutableDictionary *configuration = [[[SpoofConfig shared] getAll] mutableCopy];
    NSMutableDictionary *modules = [configuration[@"modules"] mutableCopy];
    NSMutableDictionary *entry = [modules[name] mutableCopy] ?: [NSMutableDictionary dictionary];
    entry[@"enabled"] = @(enabled);
    if (enabled && !lua_isnoneornil(L, 2)) {
        NSString *error = nil;
        id value = ReadObject(L, 2, 0, &error);
        if (!value) return luaL_error(L, "%s", error.UTF8String);
        entry[@"value"] = value;
    }
    modules[name] = entry;
    configuration[@"modules"] = modules;
    return Save(L, configuration);
}
static int l_enable(lua_State *L) { return SetModule(L, YES); }
static int l_disable(lua_State *L) { return SetModule(L, NO); }
static int l_reset(lua_State *L) { return Save(L, @{@"enabled": @NO, @"selectedApps": @[], @"modules": @{}}); }
static int l_reload(lua_State *L) { (void)L; [[SpoofConfig shared] reload]; return 0; }
static int l_is_enabled(lua_State *L) {
    NSString *name = [NSString stringWithUTF8String:luaL_checkstring(L, 1)];
    lua_pushboolean(L, name && [[SpoofConfig shared] isEnabled:name]);
    return 1;
}
static int l_get_all(lua_State *L) { PushObject(L, [[SpoofConfig shared] getAll]); return 1; }
static int l_selected_apps(lua_State *L) { PushObject(L, [[SpoofConfig shared] selectedApps]); return 1; }
static int l_set_master(lua_State *L) {
    luaL_checktype(L, 1, LUA_TBOOLEAN);
    NSMutableDictionary *configuration = [[[SpoofConfig shared] getAll] mutableCopy];
    configuration[@"enabled"] = @(lua_toboolean(L, 1) != 0);
    return Save(L, configuration);
}
static int l_select_apps(lua_State *L) {
    luaL_checktype(L, 1, LUA_TTABLE);
    NSString *error = nil;
    id apps = ReadObject(L, 1, 0, &error);
    if (!apps) return luaL_error(L, "%s", error.UTF8String);
    if ([apps isKindOfClass:NSDictionary.class] && [apps count] == 0) apps = @[];
    if (![apps isKindOfClass:NSArray.class]) return luaL_error(L, "expected an array of bundle identifiers");
    NSMutableDictionary *configuration = [[[SpoofConfig shared] getAll] mutableCopy];
    configuration[@"selectedApps"] = apps;
    return Save(L, configuration);
}
static int l_apply_preset(lua_State *L) {
    const char *name = luaL_checkstring(L, 1);
    NSDictionary *preset;
    if (strcmp(name, "iphone14_pro_max") == 0) {
        preset = @{@"device_model": @"iPhone15,3", @"device_family": @"iPhone", @"ios_version": @"17.2.1",
                   @"screen_resolution": @{@"w": @430, @"h": @932, @"scale": @3}};
    } else if (strcmp(name, "iphone13") == 0) {
        preset = @{@"device_model": @"iPhone14,5", @"device_family": @"iPhone", @"ios_version": @"16.7.2",
                   @"screen_resolution": @{@"w": @390, @"h": @844, @"scale": @3}};
    } else return luaL_error(L, "unknown preset");
    NSMutableDictionary *configuration = [[[SpoofConfig shared] getAll] mutableCopy];
    NSMutableDictionary *modules = [configuration[@"modules"] mutableCopy];
    for (NSString *key in preset) modules[key] = @{@"enabled": @YES, @"value": preset[key]};
    configuration[@"modules"] = modules;
    // A preset never opts in apps or enables the master switch.
    return Save(L, configuration);
}
static const luaL_Reg spoof_lib[] = {
    {"enable", l_enable}, {"disable", l_disable}, {"reset", l_reset}, {"reload", l_reload},
    {"isEnabled", l_is_enabled}, {"getAll", l_get_all}, {"applyPreset", l_apply_preset},
    {"setMasterEnabled", l_set_master}, {"setSelectedApps", l_select_apps}, {"selectedApps", l_selected_apps},
    {NULL, NULL}
};
void register_spoof_bindings(lua_State *L) {
#if LUA_VERSION_NUM >= 502
    luaL_newlib(L, spoof_lib);
#else
    lua_newtable(L);
    luaL_register(L, NULL, spoof_lib);
#endif
    lua_setglobal(L, "spoof");
}
