#import "mcp-tools.h"
#import <Foundation/Foundation.h>

NSDictionary *mcp_text_result(NSString *text, BOOL is_error) {
    return @{
        @"content": @[@{@"type": @"text", @"text": text ?: @""}],
        @"isError": @(is_error),
    };
}

NSDictionary *mcp_error_result(NSString *message) {
    return mcp_text_result(message ?: @"Unknown error", YES);
}
