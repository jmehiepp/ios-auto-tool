#import "../mcp-tools.h"
#import "../../engine/touch/gesture.h"

NSDictionary *tool_tap(NSDictionary *args) {
    double x = [args[@"x"] doubleValue];
    double y = [args[@"y"] doubleValue];
    c_tap(x, y);
    return mcp_text_result([NSString stringWithFormat:@"tap at (%.0f, %.0f)", x, y], NO);
}

NSDictionary *tool_double_tap(NSDictionary *args) {
    double x = [args[@"x"] doubleValue];
    double y = [args[@"y"] doubleValue];
    c_double_tap(x, y);
    return mcp_text_result([NSString stringWithFormat:@"doubleTap at (%.0f, %.0f)", x, y], NO);
}

NSDictionary *tool_long_press(NSDictionary *args) {
    double x   = [args[@"x"] doubleValue];
    double y   = [args[@"y"] doubleValue];
    int    dur = args[@"duration_ms"] ? [args[@"duration_ms"] intValue] : 1000;
    c_long_press(x, y, dur);
    return mcp_text_result(
        [NSString stringWithFormat:@"longPress at (%.0f, %.0f) for %dms", x, y, dur], NO);
}

NSDictionary *tool_swipe(NSDictionary *args) {
    double x1  = [args[@"x1"] doubleValue];
    double y1  = [args[@"y1"] doubleValue];
    double x2  = [args[@"x2"] doubleValue];
    double y2  = [args[@"y2"] doubleValue];
    int    dur = args[@"duration_ms"] ? [args[@"duration_ms"] intValue] : 300;
    c_swipe(x1, y1, x2, y2, dur);
    return mcp_text_result(
        [NSString stringWithFormat:@"swipe (%.0f,%.0f)→(%.0f,%.0f) %dms",
         x1, y1, x2, y2, dur], NO);
}
