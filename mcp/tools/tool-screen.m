#import "../mcp-tools.h"
#import "../../engine/screen/screenshot.h"
#import "../../engine/screen/color-find.h"
#import "../../engine/screen/image-match.h"
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

static CGRect region_from_dict(NSDictionary *d) {
    if (!d) return CGRectZero;
    return CGRectMake([d[@"x"] doubleValue], [d[@"y"] doubleValue],
                      [d[@"w"] doubleValue], [d[@"h"] doubleValue]);
}

NSDictionary *tool_find_color(NSDictionary *args) {
    if (!args[@"color"]) return mcp_error_result(@"'color' is required");
    uint32_t color = (uint32_t)[args[@"color"] longLongValue];
    int      tol   = args[@"tolerance"] ? [args[@"tolerance"] intValue] : 5;
    CGRect   region = region_from_dict(args[@"region"]);

    if (!g_screen_cache.pixels) capture_screen(CGRectZero);
    CGPoint pt = find_color(g_screen_cache.pixels, g_screen_cache.width,
                            g_screen_cache.height, color, tol, region);
    if (pt.x < 0) return mcp_text_result(@"null", NO);

    NSString *result = [NSString stringWithFormat:@"{\"x\":%.0f,\"y\":%.0f}", pt.x, pt.y];
    return mcp_text_result(result, NO);
}

NSDictionary *tool_find_image(NSDictionary *args) {
    NSString *b64 = args[@"image_b64"];
    if (!b64.length) return mcp_error_result(@"'image_b64' is required");

    NSData *png = [[NSData alloc] initWithBase64EncodedString:b64 options:0];
    if (!png) return mcp_error_result(@"Invalid base64 image");

    UIImage *tmpl = [UIImage imageWithData:png];
    if (!tmpl) return mcp_error_result(@"Cannot decode image");

    float  threshold = args[@"threshold"] ? [args[@"threshold"] floatValue] : 0.85f;
    CGRect region    = region_from_dict(args[@"region"]);

    if (!g_screen_cache.pixels) capture_screen(CGRectZero);
    ImageMatchResult r = find_image(g_screen_cache.pixels,
                                    g_screen_cache.width,
                                    g_screen_cache.height,
                                    tmpl, threshold, region);
    if (r.center.x < 0) return mcp_text_result(@"null", NO);

    NSString *result = [NSString stringWithFormat:
        @"{\"x\":%.0f,\"y\":%.0f,\"score\":%.3f}", r.center.x, r.center.y, r.score];
    return mcp_text_result(result, NO);
}

NSDictionary *tool_get_color(NSDictionary *args) {
    int x = [args[@"x"] intValue];
    int y = [args[@"y"] intValue];

    if (!g_screen_cache.pixels) capture_screen(CGRectZero);
    uint32_t rgba = get_pixel_color(g_screen_cache.pixels,
                                    g_screen_cache.width,
                                    g_screen_cache.height, x, y);
    NSString *result = [NSString stringWithFormat:
        @"{\"r\":%d,\"g\":%d,\"b\":%d,\"a\":%d}",
        (rgba >> 24) & 0xFF, (rgba >> 16) & 0xFF,
        (rgba >>  8) & 0xFF, (rgba      ) & 0xFF];
    return mcp_text_result(result, NO);
}
