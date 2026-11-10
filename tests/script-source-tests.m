#import <Foundation/Foundation.h>
#import "../webide/server/script-source.h"
#include <assert.h>
#include <string.h>
static NSString *parse(const char *json) { return iat_script_source_json(json,strlen(json),@"code"); }
int main(void) {
    @autoreleasepool {
        assert([parse("{\"code\":\"log('xin ch\\u00e0o \\ud83d\\ude80')\"}") isEqual:@"log('xin chào 🚀')"]);
        assert([parse("{\"code\":\"log('xin chào')\"}") isEqual:@"log('xin chào')"]);
        assert([parse("{\"code\":\"print('a\\\\0b')\"}") isEqual:@"print('a\\0b')"]);
        assert(parse("{\"code\":\"a\\u0000b\"}")==nil);
        assert(parse("{\"code\":42}")==nil && parse("[]")==nil && parse("bad")==nil);
        assert([parse("{\"code\":\"\"}") isEqual:@""]);
        NSString *large=[@"x" stringByPaddingToLength:1024*1024+1 withString:@"x" startingAtIndex:0];
        NSData *body=[NSJSONSerialization dataWithJSONObject:@{@"code":large} options:0 error:nil];
        assert(iat_script_source_json(body.bytes,body.length,@"code")==nil);
        puts("Script JSON Unicode, size and NUL contract tests passed");
    }
    return 0;
}
