#import "screenshot.h"
#import <UIKit/UIKit.h>
#import <IOSurface/IOSurface.h>
#include <dlfcn.h>

#define IOSURFACE_LOCK_READ_ONLY 0x00000001

__thread ScreenCache g_screen_cache = {NULL, 0, 0};

void screen_cache_invalidate(void) {
    if (g_screen_cache.pixels) {
        free(g_screen_cache.pixels);
        g_screen_cache.pixels = NULL;
    }
    g_screen_cache.width  = 0;
    g_screen_cache.height = 0;
}

void screen_cache_fill(UIImage *img) {
    screen_cache_invalidate();

    int w = (int)img.size.width;
    int h = (int)img.size.height;
    size_t byte_count = (size_t)(w * h * 4);
    uint8_t *pixels = malloc(byte_count);
    if (!pixels) return;

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(
        pixels, w, h, 8, w * 4, cs,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big
    );
    CGColorSpaceRelease(cs);
    if (!ctx) { free(pixels); return; }

    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), img.CGImage);
    CGContextRelease(ctx);

    g_screen_cache.pixels = pixels;
    g_screen_cache.width  = w;
    g_screen_cache.height = h;
}

// Private SpringBoard API — available on jailbroken devices
static IOSurfaceRef render_display(void) {
    typedef void (*RenderDisplay)(int, CFStringRef, IOSurfaceRef, int, int);
    static RenderDisplay render;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *quartz = dlopen("/System/Library/Frameworks/QuartzCore.framework/QuartzCore", RTLD_LAZY);
        render = quartz ? (RenderDisplay)dlsym(quartz, "CARenderServerRenderDisplay") : NULL;
    });
    if (!render) return NULL;
    __block CGSize size = CGSizeZero;
    void (^dimensions)(void) = ^{ size = UIScreen.mainScreen.nativeBounds.size; };
    if (NSThread.isMainThread) dimensions(); else dispatch_sync(dispatch_get_main_queue(), dimensions);
    size_t width = (size_t)size.width, height = (size_t)size.height;
    if (!width || !height || width > 8192 || height > 8192) return NULL;
    size_t row = (width * 4 + 63) & ~(size_t)63;
    NSDictionary *properties = @{(__bridge id)kIOSurfaceWidth: @(width), (__bridge id)kIOSurfaceHeight: @(height),
        (__bridge id)kIOSurfaceBytesPerElement: @4, (__bridge id)kIOSurfaceBytesPerRow: @(row),
        (__bridge id)kIOSurfaceAllocSize: @(row * height), (__bridge id)kIOSurfacePixelFormat: @(0x42475241)};
    IOSurfaceRef surface = IOSurfaceCreate((__bridge CFDictionaryRef)properties);
    if (surface) render(0, CFSTR("LCD"), surface, 0, 0);
    return surface;
}

static UIImage *capture_via_iosurface(void) {
    IOSurfaceRef surface = render_display();
    if (!surface) return nil;

    IOSurfaceLock(surface, IOSURFACE_LOCK_READ_ONLY, NULL);

    int w = (int)IOSurfaceGetWidth(surface);
    int h = (int)IOSurfaceGetHeight(surface);
    void *base = IOSurfaceGetBaseAddress(surface);
    size_t bpr  = IOSurfaceGetBytesPerRow(surface);
    if (!base || !w || !h || bpr < (size_t)w * 4) {
        IOSurfaceUnlock(surface, IOSURFACE_LOCK_READ_ONLY, NULL); CFRelease(surface); return nil;
    }

    // Copy to own buffer so we can unlock immediately
    size_t total = bpr * h;
    void *copy = malloc(total);
    if (!copy) {
        IOSurfaceUnlock(surface, IOSURFACE_LOCK_READ_ONLY, NULL);
        CFRelease(surface);
        return nil;
    }
    memcpy(copy, base, total);
    IOSurfaceUnlock(surface, IOSURFACE_LOCK_READ_ONLY, NULL);
    CFRelease(surface);

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(
        copy, w, h, 8, bpr, cs,
        kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little
    );
    CGColorSpaceRelease(cs);
    if (!ctx) { free(copy); return nil; }

    CGImageRef cgImg = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    free(copy);

    __block CGFloat scale = 1;
    void (^readScale)(void) = ^{ scale = UIScreen.mainScreen.scale; };
    if (NSThread.isMainThread) readScale(); else dispatch_sync(dispatch_get_main_queue(), readScale);
    UIImage *img = [UIImage imageWithCGImage:cgImg scale:scale orientation:UIImageOrientationUp];
    CGImageRelease(cgImg);
    return img;
}

static UIImage *capture_via_snapshot(void) {
    UIWindow *win = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.isKeyWindow) { win = w; break; }
    }
    if (!win) win = [UIApplication sharedApplication].windows.firstObject;
    if (!win) return nil;

    UIGraphicsBeginImageContextWithOptions(win.bounds.size, YES, 1.0);
    [win drawViewHierarchyInRect:win.bounds afterScreenUpdates:NO];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

UIImage *capture_screen(CGRect region) {
    UIImage *full = capture_via_iosurface();
    if (!full) full = capture_via_snapshot();
    if (!full) return nil;

    // Fill cache with the full-screen capture
    screen_cache_fill(full);

    // Return crop if requested
    if (!CGRectIsEmpty(region) && !CGRectEqualToRect(region, CGRectZero)) {
        CGFloat scale = full.scale;
        CGRect scaled = CGRectMake(
            region.origin.x * scale, region.origin.y * scale,
            region.size.width * scale, region.size.height * scale
        );
        CGImageRef cropped = CGImageCreateWithImageInRect(full.CGImage, scaled);
        UIImage *result = [UIImage imageWithCGImage:cropped scale:scale
                                        orientation:full.imageOrientation];
        CGImageRelease(cropped);
        return result;
    }
    return full;
}
