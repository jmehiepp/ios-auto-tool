#import "../mcp-tools.h"
#import "../../engine/screen/screenshot.h"
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

static CGRect region_from_dict(NSDictionary *d) {
    if (!d) return CGRectZero;
    return CGRectMake([d[@"x"] doubleValue], [d[@"y"] doubleValue],
                      [d[@"w"] doubleValue], [d[@"h"] doubleValue]);
}

NSDictionary *tool_screenshot(NSDictionary *args) {
    CGRect region = region_from_dict(args[@"region"]);
    UIImage *img = capture_screen(region);
    if (!img) return mcp_error_result(@"Screenshot failed");

    NSData *png = UIImagePNGRepresentation(img);
    if (!png) return mcp_error_result(@"PNG encoding failed");

    NSString *b64 = [png base64EncodedStringWithOptions:0];
    NSDictionary *item = @{
        @"type":     @"image",
        @"data":     b64,
        @"mimeType": @"image/png",
    };
    return @{@"content": @[item], @"isError": @NO};
}
