#pragma once
#import <UIKit/UIKit.h>

// Shared pixel buffer cache — populated by capture_screen(), consumed by color/image/ocr functions
typedef struct {
    uint8_t *pixels;  // RGBA bytes, heap-allocated
    int      width;
    int      height;
} ScreenCache;

extern ScreenCache g_screen_cache;

void screen_cache_invalidate(void);

// Returns autoreleased UIImage. If region is CGRectZero, captures full screen.
UIImage *capture_screen(CGRect region);

// Fills g_screen_cache from a UIImage (call after capture_screen)
void screen_cache_fill(UIImage *img);
