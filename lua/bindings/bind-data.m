#import "bind-data.h"
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#include <lua/lauxlib.h>
#include <math.h>
static char null_sentinel;
static const char *ARRAY_MT = "IOSAutoTool.Array";
static id object(lua_State *L, int index, int depth, NSMutableSet *parents, NSString **error) {
    if (depth > 64) { *error = @"table nesting exceeds 64"; return nil; }
    if (index < 0) index = lua_gettop(L) + index + 1;
    switch (lua_type(L, index)) {
        case LUA_TNIL: return NSNull.null;
        case LUA_TLIGHTUSERDATA:
            if (lua_touserdata(L, index) == &null_sentinel) return NSNull.null;
            break;
        case LUA_TBOOLEAN: return @(lua_toboolean(L, index) != 0);
        case LUA_TNUMBER: {
            double value = lua_tonumber(L, index);
            if (!isfinite(value)) { *error = @"non-finite number"; return nil; }
            return @(value);
        }
        case LUA_TSTRING: {
            size_t n; const char *value = lua_tolstring(L, index, &n);
            NSString *text = [[NSString alloc] initWithBytes:value length:n encoding:NSUTF8StringEncoding];
            if (!text) *error = @"text must be UTF-8";
            return text;
        }
        case LUA_TTABLE: {
            NSValue *identity = [NSValue valueWithPointer:lua_topointer(L, index)];
            if ([parents containsObject:identity]) { *error = @"cyclic table"; return nil; }
            [parents addObject:identity];
            NSUInteger length = lua_objlen(L, index), entries = 0; BOOL array = YES, marked = NO;
            if (lua_getmetatable(L, index)) {
                luaL_getmetatable(L, ARRAY_MT); marked = lua_rawequal(L, -1, -2); lua_pop(L, 2);
            }
            lua_pushnil(L);
            while (lua_next(L, index)) {
                entries++;
                if (lua_type(L, -2) != LUA_TNUMBER || lua_tonumber(L, -2) < 1 ||
                    lua_tonumber(L, -2) > length || floor(lua_tonumber(L, -2)) != lua_tonumber(L, -2)) array = NO;
                lua_pop(L, 1);
            }
            array = array && entries == length && (entries > 0 || marked);
            id result;
            if (array) {
                NSMutableArray *list = [NSMutableArray arrayWithCapacity:length];
                for (NSUInteger i = 1; i <= length; i++) {
                    lua_rawgeti(L, index, (int)i); id value = object(L, -1, depth + 1, parents, error); lua_pop(L, 1);
                    if (!value) { [parents removeObject:identity]; return nil; }
                    [list addObject:value];
                }
                result = list;
            } else {
                NSMutableDictionary *dict = [NSMutableDictionary dictionary];
                lua_pushnil(L);
                while (lua_next(L, index)) {
                    if (lua_type(L, -2) != LUA_TSTRING) {
                        lua_pop(L, 2); *error = @"object keys must be strings; arrays must be dense";
                        [parents removeObject:identity]; return nil;
                    }
                    NSString *key = object(L, -2, depth + 1, parents, error);
                    id value = key ? object(L, -1, depth + 1, parents, error) : nil;
                    if (!value) { lua_pop(L, 2); [parents removeObject:identity]; return nil; }
                    dict[key] = value; lua_pop(L, 1);
                }
                result = dict;
            }
            [parents removeObject:identity]; return result;
        }
    }
    *error = @"unsupported value type"; return nil;
}
static void push(lua_State *L, id value) {
    if ([value isKindOfClass:NSString.class]) {
        NSData *bytes = [value dataUsingEncoding:NSUTF8StringEncoding]; lua_pushlstring(L, bytes.bytes, bytes.length);
    } else if ([value isKindOfClass:NSData.class]) lua_pushlstring(L, [value bytes], [value length]);
    else if ([value isKindOfClass:NSNumber.class]) {
        if (CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) lua_pushboolean(L, [value boolValue]);
        else lua_pushnumber(L, [value doubleValue]);
    } else if ([value isKindOfClass:NSArray.class]) {
        lua_createtable(L, (int)[value count], 0); int i = 0;
        for (id item in value) { push(L, item); lua_rawseti(L, -2, ++i); }
        luaL_getmetatable(L, ARRAY_MT); lua_setmetatable(L, -2);
    } else if ([value isKindOfClass:NSDictionary.class]) {
        lua_newtable(L);
        for (NSString *key in value) { push(L, key); push(L, value[key]); lua_rawset(L, -3); }
    } else if (value == NSNull.null) lua_pushlightuserdata(L, &null_sentinel);
    else if ([value isKindOfClass:NSDate.class]) lua_pushnumber(L, [value timeIntervalSince1970]);
    else lua_pushnil(L);
}
static NSData *bytes(lua_State *L, int index) {
    size_t n; const char *value = luaL_checklstring(L, index, &n);
    return [NSData dataWithBytes:value length:n];
}
static int failure(lua_State *L, NSString *message) {
    lua_pushnil(L); lua_pushstring(L, message.UTF8String ?: "conversion failed"); return 2;
}
static int json_encode(lua_State *L) {
    NSString *message = nil; id value = object(L, 1, 0, [NSMutableSet set], &message);
    if (!value) return failure(L, message);
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingFragmentsAllowed error:&error];
    if (!data) return failure(L, error.localizedDescription);
    lua_pushlstring(L, data.bytes, data.length); return 1;
}
static int json_decode(lua_State *L) {
    NSError *error = nil;
    id value = [NSJSONSerialization JSONObjectWithData:bytes(L, 1) options:NSJSONReadingFragmentsAllowed error:&error];
    if (!value) return failure(L, error.localizedDescription);
    push(L, value); return 1;
}
static int array(lua_State *L) {
    if (lua_isnoneornil(L, 1)) lua_newtable(L); else { luaL_checktype(L, 1, LUA_TTABLE); lua_pushvalue(L, 1); }
    luaL_getmetatable(L, ARRAY_MT); lua_setmetatable(L, -2); return 1;
}
static int b64_encode(lua_State *L) { push(L, [bytes(L, 1) base64EncodedStringWithOptions:0]); return 1; }
static int b64_decode(lua_State *L) {
    NSData *value = [[NSData alloc] initWithBase64EncodedData:bytes(L, 1) options:0];
    if (!value) return failure(L, @"invalid base64"); push(L, value); return 1;
}
static int md5(lua_State *L) {
    NSData *data = bytes(L, 1); unsigned char digest[CC_MD5_DIGEST_LENGTH];
    if (data.length > UINT32_MAX) return failure(L, @"input too large");
    CC_MD5(data.bytes, (CC_LONG)data.length, digest);
    char output[CC_MD5_DIGEST_LENGTH * 2 + 1];
    for (int i=0;i<CC_MD5_DIGEST_LENGTH;i++) snprintf(output+i*2, 3, "%02x", digest[i]);
    lua_pushstring(L, output); return 1;
}
static int plist_dump(lua_State *L) {
    NSString *message = nil; id value = object(L, 1, 0, [NSMutableSet set], &message);
    if (!value) return failure(L, message);
    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:value format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
    if (!data) return failure(L, error.localizedDescription); push(L, data); return 1;
}
static int plist_load(lua_State *L) {
    NSError *error = nil;
    id value = [NSPropertyListSerialization propertyListWithData:bytes(L, 1) options:NSPropertyListImmutable format:NULL error:&error];
    if (!value) return failure(L, error.localizedDescription); push(L, value); return 1;
}
static int plist_read(lua_State *L) {
    NSString *path = [[NSString alloc] initWithData:bytes(L, 1) encoding:NSUTF8StringEncoding];
    if (!path || [path rangeOfString:@"\0"].location != NSNotFound) return failure(L, @"invalid UTF-8 path");
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return failure(L, @"cannot read plist");
    lua_settop(L, 0); push(L, data); return plist_load(L);
}
static int plist_write(lua_State *L) {
    NSString *path = [[NSString alloc] initWithData:bytes(L, 1) encoding:NSUTF8StringEncoding];
    if (!path || [path rangeOfString:@"\0"].location != NSNotFound) return failure(L, @"invalid UTF-8 path");
    lua_remove(L, 1);
    int n = plist_dump(L);
    if (n != 1) return n;
    NSData *data = bytes(L, -1); NSError *error = nil;
    if (![data writeToFile:path options:NSDataWritingAtomic error:&error]) return failure(L, error.localizedDescription);
    lua_pushboolean(L, 1); return 1;
}
static int module_json(lua_State *L) {
    lua_newtable(L);
    lua_pushcfunction(L, json_encode); lua_setfield(L, -2, "encode");
    lua_pushcfunction(L, json_decode); lua_setfield(L, -2, "decode");
    lua_pushcfunction(L, array); lua_setfield(L, -2, "array");
    lua_pushlightuserdata(L, &null_sentinel); lua_setfield(L, -2, "null"); return 1;
}
static int module_base64(lua_State *L) {
    lua_newtable(L); lua_pushcfunction(L, b64_encode); lua_setfield(L, -2, "encode");
    lua_pushcfunction(L, b64_decode); lua_setfield(L, -2, "decode"); return 1;
}
static int module_plist(lua_State *L) {
    lua_newtable(L);
    const luaL_Reg lib[] = {{"read",plist_read},{"write",plist_write},{"load",plist_load},{"dump",plist_dump},{NULL,NULL}};
    luaL_register(L, NULL, lib); return 1;
}
void register_data_bindings(lua_State *L) {
    luaL_newmetatable(L, ARRAY_MT); lua_pop(L, 1);
    const luaL_Reg functions[] = {{"jsonEncode",json_encode},{"jsonDecode",json_decode},{"md5",md5},
        {"_ws_json_encode",json_encode},{"_ws_json_decode",json_decode},{"_ws_b64_encode",b64_encode},
        {"_ws_b64_decode",b64_decode},{"_ws_plist_read",plist_read},{"_ws_plist_write",plist_write},
        {"_ws_plist_load",plist_load},{"_ws_plist_dump",plist_dump},{NULL,NULL}};
    lua_pushvalue(L, LUA_GLOBALSINDEX); luaL_register(L, NULL, functions); lua_pop(L, 1);
    lua_getglobal(L, "package"); lua_getfield(L, -1, "preload");
    lua_pushcfunction(L, module_json); lua_setfield(L, -2, "json");
    lua_pushcfunction(L, module_base64); lua_setfield(L, -2, "base64");
    lua_pushcfunction(L, module_plist); lua_setfield(L, -2, "plist"); lua_pop(L, 2);
}
