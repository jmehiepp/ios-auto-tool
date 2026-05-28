#pragma once
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>

typedef struct {
    CGPoint center;   // center of matched region in screen coordinates
    float   score;    // NCC score [0.0 - 1.0]
} ImageMatchResult;

// Returns best match. result.score < threshold means not found (center = {-1,-1}).
// region: CGRectZero = search full screen buffer
ImageMatchResult find_image(const uint8_t *screen_pixels, int sw, int sh,
                            UIImage *tmpl, float threshold, CGRect region);
