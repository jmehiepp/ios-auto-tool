#import "bind-screen.h"
#import "../../engine/screen/screenshot.h"
#import "../../engine/screen/color-find.h"
#import "../../engine/screen/image-match.h"
#import "../../engine/screen/ocr.h"
#import <lua/lua.h>
#import <lua/lauxlib.h>
#import <UIKit/UIKit.h>
#import "../../daemon/script-runner.h"
#include <math.h>

// Accessed only under the Lua VM mutex. HTTP capture has independent TLS pixels.
static UIImage *kept_image;
void reset_screen_bindings(void) { kept_image = nil; screen_cache_invalidate(); }
static UIImage *lua_frame(CGRect region, BOOL pixels) {
    UIImage *full = kept_image ?: capture_screen(CGRectZero);
    if (!full.CGImage) { screen_cache_invalidate(); return nil; }
    if (pixels) full = [UIImage imageWithCGImage:full.CGImage scale:1 orientation:full.imageOrientation];
    screen_cache_fill(full);
    if (CGRectIsEmpty(region)) return full;
    CGRect bounds = CGRectMake(0, 0, full.size.width, full.size.height);
    CGRect clipped = CGRectIntersection(bounds, region);
    if (CGRectIsNull(clipped) || CGRectIsEmpty(clipped)) return nil;
    CGFloat scale = full.scale;
    CGImageRef cg = CGImageCreateWithImageInRect(full.CGImage,
        CGRectMake(clipped.origin.x * scale, clipped.origin.y * scale,
                   clipped.size.width * scale, clipped.size.height * scale));
    if (!cg) return nil;
    UIImage *result = [UIImage imageWithCGImage:cg scale:scale orientation:full.imageOrientation];
    CGImageRelease(cg); return result;
}
static int lua_keep_screen(lua_State *L) { (void)L; kept_image = capture_screen(CGRectZero); return 0; }
static int lua_release_screen(lua_State *L) { (void)L; reset_screen_bindings(); return 0; }
static int lua_screen_geometry(lua_State *L) {
    __block CGSize points, pixels;
    void (^read)(void) = ^{ UIScreen *s = UIScreen.mainScreen; points = s.bounds.size;
        pixels = CGSizeMake(points.width * s.scale, points.height * s.scale); };
    if (NSThread.isMainThread) read(); else dispatch_sync(dispatch_get_main_queue(), read);
    lua_pushnumber(L, points.width); lua_pushnumber(L, points.height);
    lua_pushnumber(L, pixels.width); lua_pushnumber(L, pixels.height); return 4;
}

// ---------- UIImage Lua userdata ----------

#define IMG_MT "IOSAutoTool.Image"

typedef struct { void *retained_image; } LuaImage;
static UIImage *image_value(LuaImage *value) { return (__bridge UIImage *)value->retained_image; }

static LuaImage *check_image(lua_State *L, int idx) {
    return (LuaImage *)luaL_checkudata(L, idx, IMG_MT);
}

static int push_image(lua_State *L, UIImage *img) {
    if (!img) { lua_pushnil(L); return 1; }
    LuaImage *ud = lua_newuserdata(L, sizeof(LuaImage));
    ud->retained_image = (__bridge_retained void *)img;
    luaL_getmetatable(L, IMG_MT);
    lua_setmetatable(L, -2);
    return 1;
}

static int img_gc(lua_State *L) {
    LuaImage *ud = check_image(L, 1);
    if (ud->retained_image) CFRelease(ud->retained_image);
    ud->retained_image = NULL;
    return 0;
}

static int img_width(lua_State *L) {
    LuaImage *ud = check_image(L, 1);
    lua_pushnumber(L, image_value(ud).size.width);
    return 1;
}

static int img_height(lua_State *L) {
    LuaImage *ud = check_image(L, 1);
    lua_pushnumber(L, image_value(ud).size.height);
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
    [image_value(ud) drawAtPoint:CGPointZero];
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
    NSData *data = UIImagePNGRepresentation(image_value(ud));
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
    CGImageRef ci = CGImageCreateWithImageInRect(image_value(ud).CGImage, region);
    if (!ci) { lua_pushnil(L); return 1; }
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

    lua_frame(CGRectZero, NO);
    if (!g_screen_cache.pixels) { lua_pushnil(L); lua_pushnil(L); return 2; }
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

    lua_frame(CGRectZero, NO);
    if (!g_screen_cache.pixels) { lua_newtable(L); return 1; }
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
    lua_frame(CGRectZero, NO);
    if (!g_screen_cache.pixels || x < 0 || y < 0 || x >= g_screen_cache.width || y >= g_screen_cache.height) {
        lua_pushnil(L); return 1;
    }
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

    lua_frame(CGRectZero, NO);
    if (!g_screen_cache.pixels) { lua_pushnil(L); lua_pushnil(L); lua_pushnumber(L, 0); return 3; }
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
    UIImage *img = lua_frame(region, NO);
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
    UIImage *img = lua_frame(region, NO);
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

static CGRect legacy_region(lua_State *L, int index) {
    if (lua_isnoneornil(L, index)) return CGRectZero;
    luaL_checktype(L, index, LUA_TTABLE);
    double values[4];
    for (int i = 0; i < 4; i++) { lua_rawgeti(L, index, i + 1);
        values[i] = lua_isnil(L, -1) ? 0 : luaL_checknumber(L, -1); lua_pop(L, 1);
        if (!isfinite(values[i]) || fabs(values[i]) > 1000000) luaL_error(L, "invalid pixel region"); }
    return CGRectMake(values[0], values[1], values[2], values[3]);
}
static UIImage *legacy_frame(CGRect region, BOOL fresh) {
    UIImage *saved = kept_image;
    if (fresh) kept_image = nil;
    UIImage *frame = lua_frame(region, YES);
    kept_image = saved; return frame;
}
static int legacy_color(lua_State *L) {
    int x = (int)luaL_checkinteger(L, 1), y = (int)luaL_checkinteger(L, 2);
    legacy_frame(CGRectZero, lua_toboolean(L, 3));
    if (!g_screen_cache.pixels || x < 0 || y < 0 || x >= g_screen_cache.width || y >= g_screen_cache.height)
        lua_pushnil(L);
    else lua_pushinteger(L, get_pixel_color(g_screen_cache.pixels, g_screen_cache.width, g_screen_cache.height, x, y) >> 8);
    return 1;
}
static int legacy_colors(lua_State *L) {
    luaL_checktype(L, 1, LUA_TTABLE); size_t count=lua_objlen(L,1);
    if (count>10000) return luaL_error(L,"maximum 10000 color points");
    legacy_frame(CGRectZero, NO); lua_createtable(L,(int)count,0);
    for (int i=1;i<=(int)count;i++) {
        int x=0,y=0; lua_rawgeti(L,1,i);
        if (lua_istable(L,-1)) {
            lua_rawgeti(L,-1,1); x=(int)lua_tointeger(L,-1); lua_pop(L,1);
            lua_rawgeti(L,-1,2); y=(int)lua_tointeger(L,-1); lua_pop(L,1);
        }
        lua_pop(L,1);
        uint32_t rgb = g_screen_cache.pixels ? get_pixel_color(g_screen_cache.pixels,g_screen_cache.width,g_screen_cache.height,x,y)>>8 : 0;
        lua_pushinteger(L,rgb); lua_rawseti(L,-2,i);
    }
    return 1;
}
static int legacy_find_image(lua_State *L) {
    NSString *path = [NSString stringWithUTF8String:luaL_checkstring(L,1)];
    float threshold=(float)luaL_optnumber(L,3,.98);
    if (!isfinite(threshold) || threshold<=0 || threshold>1) threshold=.98;
    CGRect region=legacy_region(L,4);
    UIImage *image = [UIImage imageWithContentsOfFile:path]; lua_newtable(L);
    if (!image.CGImage) return 1;
    legacy_frame(CGRectZero,lua_toboolean(L,5));
    if (!g_screen_cache.pixels) return 1;
    image=[UIImage imageWithCGImage:image.CGImage scale:1 orientation:image.imageOrientation];
    ImageMatchResult result=find_image(g_screen_cache.pixels,g_screen_cache.width,g_screen_cache.height,image,threshold,region);
    if (result.center.x<0) return 1;
    lua_createtable(L,3,0); lua_pushnumber(L,result.center.x); lua_rawseti(L,-2,1);
    lua_pushnumber(L,result.center.y); lua_rawseti(L,-2,2); lua_pushnumber(L,result.score); lua_rawseti(L,-2,3);
    lua_rawseti(L,-2,1); return 1;
}
static int legacy_find_text(lua_State *L) {
    NSString *needle = [NSString stringWithUTF8String:luaL_checkstring(L,1)];
    CGRect region=legacy_region(L,2); UIImage *image=legacy_frame(region,lua_toboolean(L,3));
    int count=0; OcrObservation *obs=ocr_image_detailed(image,NULL,&count); double x=-1,y=-1;
    for (int i=0;i<count;i++) {
        NSString *text=obs[i].text ? @(obs[i].text) : @"";
        if (x<0 && needle.length && [text rangeOfString:needle options:NSCaseInsensitiveSearch].location!=NSNotFound) {
            x=MAX(0,region.origin.x)+obs[i].x+obs[i].w/2; y=MAX(0,region.origin.y)+obs[i].y+obs[i].h/2;
        }
        free(obs[i].text);
    }
    free(obs);
    if (x<0) { lua_pushnil(L); lua_pushnil(L); }
    else { lua_pushnumber(L,x); lua_pushnumber(L,y); } return 2;
}
static int legacy_screenshot(lua_State *L) {
    // screenshot always captures fresh; keepScreen only freezes analysis calls.
    UIImage *full = capture_screen(CGRectZero);
    return push_image(L, full.CGImage ? [UIImage imageWithCGImage:full.CGImage scale:1 orientation:full.imageOrientation] : nil);
}
static int legacy_ocr(lua_State *L) {
    CGRect region = legacy_region(L, 1);
    UIImage *image = lua_frame(region, YES);
    int count = 0; OcrObservation *observations = ocr_image_detailed(image, NULL, &count);
    lua_createtable(L, count, 0);
    double ox = MAX(0, region.origin.x), oy = MAX(0, region.origin.y);
    for (int i = 0; i < count; i++) {
        OcrObservation o = observations[i];
        lua_createtable(L, 0, 6);
        lua_pushstring(L, o.text ?: ""); lua_setfield(L, -2, "text");
        lua_pushnumber(L, o.confidence); lua_setfield(L, -2, "confidence");
        lua_pushnumber(L, o.x + ox); lua_setfield(L, -2, "x");
        lua_pushnumber(L, o.y + oy); lua_setfield(L, -2, "y");
        lua_pushnumber(L, o.w); lua_setfield(L, -2, "w"); lua_pushnumber(L, o.h); lua_setfield(L, -2, "h");
        free(o.text); lua_rawseti(L, -2, i + 1);
    }
    free(observations); return 1;
}
typedef struct { int dx, dy; uint32_t rgb; } ColorPoint;
static BOOL color_matches(const uint8_t *pixel, uint32_t rgb, int tolerance) {
    return abs((int)pixel[0] - (int)((rgb >> 16) & 255)) <= tolerance &&
           abs((int)pixel[1] - (int)((rgb >> 8) & 255)) <= tolerance && abs((int)pixel[2] - (int)(rgb & 255)) <= tolerance;
}
static int legacy_find_colors(lua_State *L) {
    ColorPoint pattern[256]; int count = 1; BOOL multi = lua_istable(L, 1);
    if (multi) {
        count = (int)lua_objlen(L, 1);
        if (count < 1 || count > 256) return luaL_error(L, "color pattern must have 1..256 points");
        for (int i = 0; i < count; i++) {
            lua_rawgeti(L, 1, i + 1); luaL_checktype(L, -1, LUA_TTABLE);
            lua_rawgeti(L, -1, 1); pattern[i].dx = (int)luaL_checkinteger(L, -1); lua_pop(L, 1);
            lua_rawgeti(L, -1, 2); pattern[i].dy = (int)luaL_checkinteger(L, -1); lua_pop(L, 1);
            lua_rawgeti(L, -1, 3); pattern[i].rgb = (uint32_t)luaL_checkinteger(L, -1); lua_pop(L, 2);
            if (llabs((long long)pattern[i].dx) > 1000000 || llabs((long long)pattern[i].dy) > 1000000)
                return luaL_error(L, "color offset out of range");
        }
        pattern[0].dx = 0; pattern[0].dy = 0;
    } else pattern[0] = (ColorPoint){0, 0, (uint32_t)luaL_checkinteger(L, 1)};
    int limit = (int)luaL_optinteger(L, 2, 1);
    if (limit <= 0) limit = 10000;
    if (limit > 10000) return luaL_error(L, "maximum 10000 color matches");
    CGRect region = legacy_region(L, 3);
    lua_frame(CGRectZero, YES); lua_newtable(L);
    if (!g_screen_cache.pixels) return 1;
    int w = g_screen_cache.width, h = g_screen_cache.height, found = 0;
    if (CGRectEqualToRect(region, CGRectZero)) region = CGRectMake(0, 0, w, h);
    else {
        if (region.size.width == 0) region.size.width = w - region.origin.x;
        if (region.size.height == 0) region.size.height = h - region.origin.y;
        region = CGRectIntersection(region, CGRectMake(0, 0, w, h));
    }
    if (CGRectIsEmpty(region) || CGRectIsNull(region)) return 1;
    for (int y = MAX(0, (int)region.origin.y); y < MIN(h, CGRectGetMaxY(region)); y++) {
        if (script_should_stop()) return luaL_error(L, "script stopped");
        for (int x = MAX(0, (int)region.origin.x); x < MIN(w, CGRectGetMaxX(region)); x++) {
            BOOL match = YES;
            for (int i = 0; i < count; i++) {
                int sx = x + pattern[i].dx, sy = y + pattern[i].dy;
                if (sx < 0 || sy < 0 || sx >= w || sy >= h ||
                    !color_matches(g_screen_cache.pixels + ((size_t)sy * w + sx) * 4, pattern[i].rgb, multi ? 25 : 8)) {
                    match = NO; break;
                }
            }
            if (match) {
                lua_createtable(L, 2, 0); lua_pushinteger(L, x); lua_rawseti(L, -2, 1);
                lua_pushinteger(L, y); lua_rawseti(L, -2, 2); lua_rawseti(L, -2, ++found);
                if (found >= limit) return 1;
            }
        }
    }
    return 1;
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
    lua_register(L, "keepScreen", lua_keep_screen);
    lua_register(L, "releaseScreen", lua_release_screen);
    lua_register(L, "screenGeometry", lua_screen_geometry);
    lua_register(L, "_legacyGetColor", legacy_color);
    lua_register(L, "_legacyGetColors", legacy_colors);
    lua_register(L, "_legacyFindColors", legacy_find_colors);
    lua_register(L, "_legacyFindImage", legacy_find_image);
    lua_register(L, "_legacyFindText", legacy_find_text);
    lua_register(L, "_legacyOCR", legacy_ocr);
    lua_register(L, "_legacyScreenshot", legacy_screenshot);
}
