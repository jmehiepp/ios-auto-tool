#import "stdio-bridge.h"
#import "../daemon/runtime-paths.h"
#import <Foundation/Foundation.h>
#include <stdio.h>

int iat_stdio_bridge(void) {
    char *line = NULL;
    size_t capacity = 0;
    while (getline(&line, &capacity, stdin) > 0) {
        @autoreleasepool {
            if (strlen(line) > 1024 * 1024) { free(line); return 1; }
            NSData *body = [NSData dataWithBytes:line length:strlen(line)];
            id parsed = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
            if (![parsed isKindOfClass:NSDictionary.class]) continue;
            NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:
                [NSURL URLWithString:@"http://127.0.0.1:8765/"] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:120];
            request.HTTPMethod = @"POST";
            request.HTTPBody = body;
            [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
            [request setValue:[@"Bearer " stringByAppendingString:iat_access_token() ?: @""] forHTTPHeaderField:@"Authorization"];
            NSError *error = nil;
            NSURLResponse *response = nil;
            NSData *result = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
            if (!parsed[@"id"]) continue;
            if (error || !result.length) {
                result = [NSJSONSerialization dataWithJSONObject:@{@"jsonrpc": @"2.0", @"id": parsed[@"id"],
                    @"error": @{@"code": @(-32603), @"message": @"Cannot reach the on-device MCP daemon"}} options:0 error:nil];
            }
            fwrite(result.bytes, 1, result.length, stdout);
            fputc('\n', stdout); fflush(stdout);
        }
    }
    free(line);
    return 0;
}
