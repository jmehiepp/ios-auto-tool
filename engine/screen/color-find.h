#pragma once
#import <CoreGraphics/CoreGraphics.h>
#include <stdint.h>

// Returns center of first matching pixel, or {-1,-1} if not found.
// target_rgb: 0xRRGGBB, tolerance: per-channel delta [0..255]
// region: CGRectZero = full buffer
CGPoint find_color(const uint8_t *pixels, int width, int height,
                   uint32_t target_rgb, int tolerance, CGRect region);

// Returns all matching points (caller frees result array). count set to number found.
CGPoint *find_colors(const uint8_t *pixels, int width, int height,
                     uint32_t target_rgb, int tolerance, CGRect region,
                     int *count);

// Returns RGBA packed as 0xRRGGBBAA, or 0 if out of bounds.
uint32_t get_pixel_color(const uint8_t *pixels, int width, int height,
                         int x, int y);
