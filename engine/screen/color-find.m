#import "color-find.h"
#include <stdlib.h>
#include <math.h>

static inline int clamp_int(int v, int lo, int hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

static CGRect normalize_region(int width, int height, CGRect region) {
    if (CGRectIsEmpty(region) || CGRectEqualToRect(region, CGRectZero)) {
        return CGRectMake(0, 0, width, height);
    }
    int x = clamp_int((int)region.origin.x, 0, width - 1);
    int y = clamp_int((int)region.origin.y, 0, height - 1);
    int w = clamp_int((int)region.size.width,  1, width  - x);
    int h = clamp_int((int)region.size.height, 1, height - y);
    return CGRectMake(x, y, w, h);
}

CGPoint find_color(const uint8_t *pixels, int width, int height,
                   uint32_t target_rgb, int tolerance, CGRect region)
{
    CGRect r = normalize_region(width, height, region);
    int r_t = (target_rgb >> 16) & 0xFF;
    int g_t = (target_rgb >>  8) & 0xFF;
    int b_t = (target_rgb      ) & 0xFF;

    int x_end = (int)(r.origin.x + r.size.width);
    int y_end = (int)(r.origin.y + r.size.height);

    for (int y = (int)r.origin.y; y < y_end; y++) {
        const uint8_t *row = pixels + y * width * 4;
        for (int x = (int)r.origin.x; x < x_end; x++) {
            const uint8_t *px = row + x * 4;
            if (abs(px[0] - r_t) <= tolerance &&
                abs(px[1] - g_t) <= tolerance &&
                abs(px[2] - b_t) <= tolerance) {
                return CGPointMake(x, y);
            }
        }
    }
    return CGPointMake(-1, -1);
}

CGPoint *find_colors(const uint8_t *pixels, int width, int height,
                     uint32_t target_rgb, int tolerance, CGRect region,
                     int *count)
{
    *count = 0;
    CGRect r = normalize_region(width, height, region);
    int r_t = (target_rgb >> 16) & 0xFF;
    int g_t = (target_rgb >>  8) & 0xFF;
    int b_t = (target_rgb      ) & 0xFF;

    int capacity = 64;
    CGPoint *results = malloc((size_t)capacity * sizeof(CGPoint));
    if (!results) return NULL;

    int x_end = (int)(r.origin.x + r.size.width);
    int y_end = (int)(r.origin.y + r.size.height);

    for (int y = (int)r.origin.y; y < y_end; y++) {
        const uint8_t *row = pixels + y * width * 4;
        for (int x = (int)r.origin.x; x < x_end; x++) {
            const uint8_t *px = row + x * 4;
            if (abs(px[0] - r_t) <= tolerance &&
                abs(px[1] - g_t) <= tolerance &&
                abs(px[2] - b_t) <= tolerance) {
                if (*count >= capacity) {
                    capacity *= 2;
                    CGPoint *tmp = realloc(results, (size_t)capacity * sizeof(CGPoint));
                    if (!tmp) { free(results); *count = 0; return NULL; }
                    results = tmp;
                }
                results[(*count)++] = CGPointMake(x, y);
            }
        }
    }
    return results;
}

uint32_t get_pixel_color(const uint8_t *pixels, int width, int height, int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) return 0;
    const uint8_t *px = pixels + (y * width + x) * 4;
    return ((uint32_t)px[0] << 24) |
           ((uint32_t)px[1] << 16) |
           ((uint32_t)px[2] <<  8) |
            (uint32_t)px[3];
}
