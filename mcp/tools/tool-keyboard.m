#import "../mcp-tools.h"
#import "../../engine/keyboard/text-input.h"
#import "../../engine/keyboard/key-press.h"
#import <Foundation/Foundation.h>

NSDictionary *tool_type_text(NSDictionary *args) {
    NSString *text = args[@"text"];
    if (!text.length) return mcp_error_result(@"'text' is required");
    c_type_text(text);
    return mcp_text_result(
        [NSString stringWithFormat:@"typed %lu chars", (unsigned long)text.length], NO);
}

NSDictionary *tool_press_key(NSDictionary *args) {
    NSString *key = [args[@"key"] lowercaseString];
    if (!key.length) return mcp_error_result(@"'key' is required");

    if ([key isEqualToString:@"home"])          c_press_home();
    else if ([key isEqualToString:@"lock"])     c_press_lock();
    else if ([key isEqualToString:@"volume_up"])   c_press_volume(true);
    else if ([key isEqualToString:@"volume_down"]) c_press_volume(false);
    else if ([key isEqualToString:@"mute"])     c_press_mute();
    else return mcp_error_result(
        [NSString stringWithFormat:@"Unknown key '%@'. Use: home, lock, volume_up, volume_down, mute", key]);

    return mcp_text_result([NSString stringWithFormat:@"pressed '%@'", key], NO);
}
