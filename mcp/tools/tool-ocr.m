#import "../mcp-tools.h"
#import "../../engine/screen/screenshot.h"
#import "../../engine/screen/ocr.h"
#import <UIKit/UIKit.h>

static CGRect region_from_dict(NSDictionary *d) {
    if (!d) return CGRectZero;
    return CGRectMake([d[@"x"] doubleValue], [d[@"y"] doubleValue],
                      [d[@"w"] doubleValue], [d[@"h"] doubleValue]);
}

NSDictionary *tool_ocr_screen(NSDictionary *args) {
    CGRect region = region_from_dict(args[@"region"]);
    UIImage *img = capture_screen(region);
    if (!img) return mcp_error_result(@"Screenshot failed");

    char *text = ocr_image(img, NULL);
    NSString *result = text ? [NSString stringWithUTF8String:text] : @"";
    free(text);
    return mcp_text_result(result, NO);
}
