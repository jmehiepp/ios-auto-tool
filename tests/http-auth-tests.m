#import <Foundation/Foundation.h>
#import "../daemon/runtime-paths.h"
#import "../webide/server/access-control.h"
#include <sys/stat.h>

static void check(BOOL value, NSString *label) {
    if (!value) { fprintf(stderr, "FAIL: %s\n", label.UTF8String); exit(1); }
}
static BOOL authorized(NSString *headers) {
    NSString *request = [NSString stringWithFormat:@"GET /api/files HTTP/1.1\r\nHost: localhost:8888\r\n%@\r\n", headers];
    NSData *data = [request dataUsingEncoding:NSUTF8StringEncoding];
    struct mg_http_message message;
    check(mg_http_parse(data.bytes, data.length, &message) > 0, @"valid HTTP fixture");
    return iat_request_authorized(&message);
}
int main(void) {
    @autoreleasepool {
        NSString *temporary = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        setenv("IAT_DATA_DIR", temporary.UTF8String, 1);
        NSString *token = iat_access_token();
        check(token.length == 64, @"random token created");
        NSString *path = [temporary stringByAppendingPathComponent:@"access-token"];
        struct stat metadata;
        check(stat(path.fileSystemRepresentation, &metadata) == 0 && (metadata.st_mode & 0777) == 0600, @"token owner-only permissions");
        check(!authorized(@""), @"anonymous request denied");
        check(!authorized(@"Authorization: Bearer wrong\r\n"), @"bad bearer denied");
        check(authorized([NSString stringWithFormat:@"Authorization: Bearer %@\r\n", token]), @"bearer accepted");
        check(authorized([NSString stringWithFormat:@"Cookie: unrelated=hello; iat_session=%@\r\n", token]), @"session cookie accepted");
        check(!authorized([NSString stringWithFormat:@"Authorization: Bearer %@\r\nOrigin: https://untrusted.example\r\n", token]), @"cross-origin request denied even with a credential");
        check(authorized([NSString stringWithFormat:@"Cookie: iat_session=%@\r\nOrigin: http://localhost:8888\r\n", token]), @"same-origin session accepted");
        check(!authorized([NSString stringWithFormat:@"Cookie: iat_session=%@x\r\n", token]), @"overlong token denied");
        check(!authorized([NSString stringWithFormat:@"Cookie: iat_session=%@\r\nOrigin: null\r\n", token]), @"opaque origin denied");
        check([token isEqualToString:iat_access_token()], @"token stable in process");
        [NSFileManager.defaultManager removeItemAtPath:temporary error:nil];
        puts("HTTP auth tests passed");
    }
    return 0;
}
