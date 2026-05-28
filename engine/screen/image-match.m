#import "image-match.h"
#import <Accelerate/Accelerate.h>
#include <stdlib.h>
#include <math.h>

// Convert RGBA pixel buffer region to grayscale float array (row-major)
static float *rgba_to_gray_float(const uint8_t *pixels, int stride,
                                  int x0, int y0, int w, int h) {
    float *out = malloc((size_t)(w * h) * sizeof(float));
    if (!out) return NULL;
    for (int y = 0; y < h; y++) {
        const uint8_t *row = pixels + (y0 + y) * stride * 4 + x0 * 4;
        for (int x = 0; x < w; x++) {
            float r = row[x * 4 + 0];
            float g = row[x * 4 + 1];
            float b = row[x * 4 + 2];
            out[y * w + x] = 0.299f * r + 0.587f * g + 0.114f * b;
        }
    }
    return out;
}

// Extract UIImage pixels as RGBA buffer (caller frees). Sets w/h.
static uint8_t *uiimage_to_rgba(UIImage *img, int *out_w, int *out_h) {
    *out_w = (int)img.size.width;
    *out_h = (int)img.size.height;
    size_t bytes = (size_t)(*out_w * *out_h * 4);
    uint8_t *px = malloc(bytes);
    if (!px) return NULL;

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(
        px, *out_w, *out_h, 8, *out_w * 4, cs,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big
    );
    CGColorSpaceRelease(cs);
    if (!ctx) { free(px); return NULL; }
    CGContextDrawImage(ctx, CGRectMake(0, 0, *out_w, *out_h), img.CGImage);
    CGContextRelease(ctx);
    return px;
}

// Compute NCC score between normalized template and a screen patch at (sx, sy).
// norm_tmpl: template with mean subtracted; tmpl_sq_sum: Σ(T - meanT)²
static float ncc_at(const float *screen_gray, int sw,
                    const float *norm_tmpl, int tw, int th,
                    float tmpl_sq_sum,
                    int sx, int sy)
{
    float patch_sum = 0, patch_sq_sum = 0, dot = 0;
    int n = tw * th;

    for (int y = 0; y < th; y++) {
        for (int x = 0; x < tw; x++) {
            float sv = screen_gray[(sy + y) * sw + (sx + x)];
            float tv = norm_tmpl[y * tw + x];
            patch_sum    += sv;
            patch_sq_sum += sv * sv;
            dot          += sv * tv;
        }
    }

    float patch_mean = patch_sum / n;
    // Σ(I - meanI)² = Σ(I²) - n*meanI²
    float patch_var = patch_sq_sum - (float)n * patch_mean * patch_mean;

    float denom = sqrtf(tmpl_sq_sum * patch_var);
    if (denom < 1e-6f) return 0.0f;

    // Correct for mean: dot already uses norm_tmpl (mean-subtracted),
    // but screen values are not; subtract n * patch_mean * 0 (tmpl mean = 0)
    return dot / denom;
}

ImageMatchResult find_image(const uint8_t *screen_pixels, int sw, int sh,
                            UIImage *tmpl, float threshold, CGRect region)
{
    ImageMatchResult not_found = {{-1, -1}, 0.0f};

    // Load template pixels
    int tw, th;
    uint8_t *tmpl_px = uiimage_to_rgba(tmpl, &tw, &th);
    if (!tmpl_px) return not_found;

    // Downscale 2x for performance — match at half resolution, report original coords
    int sw2 = sw / 2, sh2 = sh / 2;
    int tw2 = tw / 2, th2 = th / 2;
    if (tw2 < 1) tw2 = 1;
    if (th2 < 1) th2 = 1;

    // Build downscaled screen gray
    float *screen_gray = malloc((size_t)(sw2 * sh2) * sizeof(float));
    if (!screen_gray) { free(tmpl_px); return not_found; }
    for (int y = 0; y < sh2; y++) {
        for (int x = 0; x < sw2; x++) {
            const uint8_t *p = screen_pixels + (y * 2) * sw * 4 + (x * 2) * 4;
            screen_gray[y * sw2 + x] = 0.299f * p[0] + 0.587f * p[1] + 0.114f * p[2];
        }
    }

    // Build downscaled template gray
    float *tmpl_gray = malloc((size_t)(tw2 * th2) * sizeof(float));
    if (!tmpl_gray) { free(screen_gray); free(tmpl_px); return not_found; }
    for (int y = 0; y < th2; y++) {
        for (int x = 0; x < tw2; x++) {
            const uint8_t *p = tmpl_px + (y * 2) * tw * 4 + (x * 2) * 4;
            tmpl_gray[y * tw2 + x] = 0.299f * p[0] + 0.587f * p[1] + 0.114f * p[2];
        }
    }
    free(tmpl_px);

    // Normalize template (subtract mean)
    float tmpl_mean;
    vDSP_meanv(tmpl_gray, 1, &tmpl_mean, (vDSP_Length)(tw2 * th2));
    float neg_mean = -tmpl_mean;
    vDSP_vsadd(tmpl_gray, 1, &neg_mean, tmpl_gray, 1, (vDSP_Length)(tw2 * th2));

    float tmpl_sq_sum;
    vDSP_svesq(tmpl_gray, 1, &tmpl_sq_sum, (vDSP_Length)(tw2 * th2));

    // Determine search bounds
    int rx = 0, ry = 0, rw = sw2, rh = sh2;
    if (!CGRectIsEmpty(region) && !CGRectEqualToRect(region, CGRectZero)) {
        rx = (int)(region.origin.x / 2);
        ry = (int)(region.origin.y / 2);
        rw = (int)(region.size.width / 2);
        rh = (int)(region.size.height / 2);
    }

    float best_score = -1.0f;
    int best_x = -1, best_y = -1;

    for (int y = ry; y <= ry + rh - th2; y++) {
        for (int x = rx; x <= rx + rw - tw2; x++) {
            float score = ncc_at(screen_gray, sw2, tmpl_gray, tw2, th2,
                                 tmpl_sq_sum, x, y);
            if (score > best_score) {
                best_score = score;
                best_x = x;
                best_y = y;
                if (score > 0.99f) goto done;
            }
        }
    }
done:
    free(screen_gray);
    free(tmpl_gray);

    if (best_score < threshold) return not_found;

    // Map back to full-resolution coordinates, report center of template
    ImageMatchResult res;
    res.center = CGPointMake((best_x + tw2 / 2) * 2, (best_y + th2 / 2) * 2);
    res.score  = best_score;
    return res;
}
