#import "screenshot.h"
#import <UIKit/UIKit.h>

typedef struct __IOSurface *IOSurfaceRef;
extern int IOSurfaceLock(IOSurfaceRef, uint32_t, uint32_t *);
extern int IOSurfaceUnlock(IOSurfaceRef, uint32_t, uint32_t *);
extern size_t IOSurfaceGetWidth(IOSurfaceRef);
extern size_t IOSurfaceGetHeight(IOSurfaceRef);
extern void *IOSurfaceGetBaseAddress(IOSurfaceRef);
extern size_t IOSurfaceGetBytesPerRow(IOSurfaceRef);
static const uint32_t kIOSurfaceLockReadOnly = 0x00000001;

ScreenCache g_screen_cache = {NULL, 0, 0};

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
extern IOSurfaceRef SBGetMainDisplayIOSurface(void);

static UIImage *capture_via_iosurface(void) {
    IOSurfaceRef surface = SBGetMainDisplayIOSurface();
    if (!surface) return nil;

    IOSurfaceLock(surface, kIOSurfaceLockReadOnly, NULL);

    int w = (int)IOSurfaceGetWidth(surface);
    int h = (int)IOSurfaceGetHeight(surface);
    void *base = IOSurfaceGetBaseAddress(surface);
    size_t bpr  = IOSurfaceGetBytesPerRow(surface);

    // Copy to own buffer so we can unlock immediately
    size_t total = bpr * h;
    void *copy = malloc(total);
    if (!copy) {
        IOSurfaceUnlock(surface, kIOSurfaceLockReadOnly, NULL);
        return nil;
    }
    memcpy(copy, base, total);
    IOSurfaceUnlock(surface, kIOSurfaceLockReadOnly, NULL);

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

    UIImage *img = [UIImage imageWithCGImage:cgImg];
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
