#import "script-source.h"
#include <string.h>
NSString *iat_script_source_json(const char *bytes, size_t length, NSString *field) {
    if (!bytes || !length || length>8*1024*1024) return nil;
    NSData *data=[NSData dataWithBytes:bytes length:length];
    id body=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![body isKindOfClass:NSDictionary.class]) return nil;
    id source=body[field];
    if (![source isKindOfClass:NSString.class]) return nil;
    NSData *utf8=[source dataUsingEncoding:NSUTF8StringEncoding];
    if (!utf8 || utf8.length>1024*1024 || (utf8.length && memchr(utf8.bytes,0,utf8.length))) return nil;
    return source;
}
