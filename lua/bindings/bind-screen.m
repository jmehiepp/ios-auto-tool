#import "bind-screen.h"
#import "../../engine/screen/screenshot.h"
#import "../../engine/screen/color-find.h"
#import "../../engine/screen/image-match.h"
#import "../../engine/screen/ocr.h"
#import <lua/lua.h>
#import <lua/lauxlib.h>
#import <UIKit/UIKit.h>

// ---------- UIImage Lua userdata ----------

#define IMG_MT "IOSAutoTool.Image"

typedef struct { UIImage *__strong img; } LuaImage;

static LuaImage *check_image(lua_State *L, int idx) {
    return (LuaImage *)luaL_checkudata(L, idx, IMG_MT);
}

static int push_image(lua_State *L, UIImage *img) {
    if (!img) { lua_pushnil(L); return 1; }
    LuaImage *ud = lua_newuserdata(L, sizeof(LuaImage));
    ud->img = img;
    luaL_getmetatable(L, IMG_MT);
    lua_setmetatable(L, -2);
    return 1;
}

static int img_gc(lua_State *L) {
    LuaImage *ud = check_image(L, 1);
    ud->img = nil;
    return 0;
}

static int img_width(lua_State *L) {
    LuaImage *ud = check_image(L, 1);
    lua_pushnumber(L, ud->img.size.width);
    return 1;
}

static int img_height(lua_State *L) {
    LuaImage *ud = check_image(L, 1);
    lua_pushnumber(L, ud->img.size.height);
    return 1;
}

static int img_get_color(lua_State *L) {
    LuaImage *ud = check_image(L, 1);
    int x = (int)luaL_checkinteger(L, 2);
    int y = (int)luaL_checkinteger(L, 3);

    // Render into a 1-pixel context at the requested coordinate
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(1, 1), NO, 1.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextTranslateCTM(ctx, -x, -y);
    [ud->img drawAtPoint:CGPointZero];
    UIImage *pixel = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    uint8_t px[4] = {0};
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef pctx = CGBitmapContextCreate(px, 1, 1, 8, 4, cs,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    CGContextDrawImage(pctx, CGRectMake(0,0,1,1), pixel.CGImage);
    CGContextRelease(pctx);

    lua_pushinteger(L, px[0]);
    lua_pushinteger(L, px[1]);
    lua_pushinteger(L, px[2]);
    lua_pushinteger(L, px[3]);
    return 4;
}

static int img_save(lua_State *L) {
    LuaImage *ud = check_image(L, 1);
    const char *path = luaL_checkstring(L, 2);
    NSData *data = UIImagePNGRepresentation(ud->img);
    BOOL ok = [data writeToFile:[NSString stringWithUTF8String:path] atomically:YES];
    lua_pushboolean(L, ok);
    return 1;
}

static int img_crop(lua_State *L) {
    LuaImage *ud = check_image(L, 1);
    int x = (int)luaL_checkinteger(L, 2);
    int y = (int)luaL_checkinteger(L, 3);
    int w = (int)luaL_checkinteger(L, 4);
    int h = (int)luaL_checkinteger(L, 5);
    CGRect region = CGRectMake(x, y, w, h);
    CGImageRef ci = CGImageCreateWithImageInRect(ud->img.CGImage, region);
    UIImage *cropped = [UIImage imageWithCGImage:ci];
    CGImageRelease(ci);
    return push_image(L, cropped);
}

static const luaL_Reg img_methods[] = {
    {"width",    img_width},
    {"height",   img_height},
    {"getColor", img_get_color},
    {"save",     img_save},
    {"crop",     img_crop},
    {"__gc",     img_gc},
    {NULL, NULL}
};

// ---------- Global screen functions ----------

static int lua_screenshot(lua_State *L) {
    CGRect region = CGRectZero;
    if (lua_gettop(L) >= 4) {
        double x = luaL_checknumber(L, 1);
        double y = luaL_checknumber(L, 2);
        double w = luaL_checknumber(L, 3);
        double h = luaL_checknumber(L, 4);
        region = CGRectMake(x, y, w, h);
    }
    UIImage *img = capture_screen(region);
    return push_image(L, img);
}

static int lua_find_color(lua_State *L) {
    lua_Integer color = luaL_checkinteger(L, 1);
    int tol = (int)luaL_optinteger(L, 2, 5);
    CGRect region = CGRectZero;
    if (lua_gettop(L) >= 6) {
        region = CGRectMake(luaL_checknumber(L, 3), luaL_checknumber(L, 4),
                            luaL_checknumber(L, 5), luaL_checknumber(L, 6));
    }

    if (!g_screen_cache.pixels) capture_screen(CGRectZero);
    CGPoint pt = find_color(g_screen_cache.pixels, g_screen_cache.width,
                            g_screen_cache.height, (uint32_t)color, tol, region);
    if (pt.x < 0) { lua_pushnil(L); lua_pushnil(L); }
    else { lua_pushnumber(L, pt.x); lua_pushnumber(L, pt.y); }
    return 2;
}

static int lua_find_colors(lua_State *L) {
    lua_Integer color = luaL_checkinteger(L, 1);
    int tol = (int)luaL_optinteger(L, 2, 5);
    CGRect region = CGRectZero;
    if (lua_gettop(L) >= 6) {
        region = CGRectMake(luaL_checknumber(L, 3), luaL_checknumber(L, 4),
                            luaL_checknumber(L, 5), luaL_checknumber(L, 6));
    }

    if (!g_screen_cache.pixels) capture_screen(CGRectZero);
    int count = 0;
    CGPoint *pts = find_colors(g_screen_cache.pixels, g_screen_cache.width,
                               g_screen_cache.height, (uint32_t)color, tol,
                               region, &count);
    lua_createtable(L, count, 0);
    for (int i = 0; i < count; i++) {
        lua_createtable(L, 2, 0);
        lua_pushnumber(L, pts[i].x); lua_rawseti(L, -2, 1);
        lua_pushnumber(L, pts[i].y); lua_rawseti(L, -2, 2);
        lua_rawseti(L, -2, i + 1);
    }
    free(pts);
    return 1;
}

static int lua_get_color(lua_State *L) {
    int x = (int)luaL_checkinteger(L, 1);
    int y = (int)luaL_checkinteger(L, 2);
    if (!g_screen_cache.pixels) capture_screen(CGRectZero);
    uint32_t rgba = get_pixel_color(g_screen_cache.pixels,
                                    g_screen_cache.width,
                                    g_screen_cache.height, x, y);
    lua_pushinteger(L, (rgba >> 24) & 0xFF); // r
    lua_pushinteger(L, (rgba >> 16) & 0xFF); // g
    lua_pushinteger(L, (rgba >>  8) & 0xFF); // b
    lua_pushinteger(L, (rgba      ) & 0xFF); // a
    return 4;
}

static int lua_find_image(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);
    float threshold  = (float)luaL_optnumber(L, 2, 0.85);
    CGRect region = CGRectZero;
    if (lua_gettop(L) >= 6) {
        region = CGRectMake(luaL_checknumber(L, 3), luaL_checknumber(L, 4),
                            luaL_checknumber(L, 5), luaL_checknumber(L, 6));
    }

    UIImage *tmpl = [UIImage imageWithContentsOfFile:
                     [NSString stringWithUTF8String:path]];
    if (!tmpl) { lua_pushnil(L); lua_pushnil(L); lua_pushnumber(L, 0); return 3; }

    if (!g_screen_cache.pixels) capture_screen(CGRectZero);
    ImageMatchResult r = find_image(g_screen_cache.pixels,
                                    g_screen_cache.width,
                                    g_screen_cache.height,
                                    tmpl, threshold, region);
    if (r.center.x < 0) { lua_pushnil(L); lua_pushnil(L); lua_pushnumber(L, 0); }
    else {
        lua_pushnumber(L, r.center.x);
        lua_pushnumber(L, r.center.y);
        lua_pushnumber(L, r.score);
    }
    return 3;
}

static int lua_ocr(lua_State *L) {
    CGRect region = CGRectZero;
    if (lua_gettop(L) >= 4) {
        region = CGRectMake(luaL_checknumber(L, 1), luaL_checknumber(L, 2),
                            luaL_checknumber(L, 3), luaL_checknumber(L, 4));
    }
    UIImage *img = capture_screen(region);
    char *text = ocr_image(img, NULL);
    if (text) { lua_pushstring(L, text); free(text); }
    else        lua_pushstring(L, "");
    return 1;
}

static int lua_ocr_detailed(lua_State *L) {
    CGRect region = CGRectZero;
    if (lua_gettop(L) >= 4) {
        region = CGRectMake(luaL_checknumber(L, 1), luaL_checknumber(L, 2),
                            luaL_checknumber(L, 3), luaL_checknumber(L, 4));
    }
    UIImage *img = capture_screen(region);
    int count = 0;
    OcrObservation *obs = ocr_image_detailed(img, NULL, &count);

    lua_createtable(L, count, 0);
    for (int i = 0; i < count; i++) {
        lua_createtable(L, 0, 6);
        lua_pushstring(L, obs[i].text);   lua_setfield(L, -2, "text");
        lua_pushnumber(L, obs[i].confidence); lua_setfield(L, -2, "confidence");
        lua_pushnumber(L, obs[i].x);      lua_setfield(L, -2, "x");
        lua_pushnumber(L, obs[i].y);      lua_setfield(L, -2, "y");
        lua_pushnumber(L, obs[i].w);      lua_setfield(L, -2, "w");
        lua_pushnumber(L, obs[i].h);      lua_setfield(L, -2, "h");
        free(obs[i].text);
        lua_rawseti(L, -2, i + 1);
    }
    free(obs);
    return 1;
}

static int lua_set_ocr_languages(lua_State *L) {
    const char *langs = luaL_checkstring(L, 1);
    ocr_set_languages(langs);
    return 0;
}

void register_screen_bindings(lua_State *L) {
    // Image userdata metatable
    luaL_newmetatable(L, IMG_MT);
    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");
    luaL_setfuncs(L, img_methods, 0);
    lua_pop(L, 1);

    lua_register(L, "screenshot",       lua_screenshot);
    lua_register(L, "findColor",        lua_find_color);
    lua_register(L, "findColors",       lua_find_colors);
    lua_register(L, "getColor",         lua_get_color);
    lua_register(L, "findImage",        lua_find_image);
    lua_register(L, "ocr",              lua_ocr);
    lua_register(L, "ocrDetailed",      lua_ocr_detailed);
    lua_register(L, "setOcrLanguages",  lua_set_ocr_languages);
}
