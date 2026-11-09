#import "runtime-paths.h"
#import <Security/Security.h>
#include <mach-o/dyld.h>
#include <sys/stat.h>
#include <unistd.h>

NSString *iat_resource_path(NSString *relative) {
    uint32_t size = 0;
    _NSGetExecutablePath(NULL, &size);
    char *buffer = calloc(1, size + 1);
    if (!buffer || _NSGetExecutablePath(buffer, &size) != 0) { free(buffer); return nil; }
    NSString *base = [[NSString stringWithUTF8String:buffer] stringByDeletingLastPathComponent];
    free(buffer);
    return [base stringByAppendingPathComponent:relative];
}
NSString *iat_data_directory(void) {
    const char *override = getenv("IAT_DATA_DIR");
    return override && override[0] ? @(override) : @"/var/mobile/Library/IOSAutoTool";
}
void iat_prepare_storage(void) {
    for (NSString *subdir in @[@"", @"scripts", @"accounts"]) {
        NSString *path = [iat_data_directory() stringByAppendingPathComponent:subdir];
        [NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES
                       attributes:@{NSFilePosixPermissions: @0700} error:nil];
        chmod(path.fileSystemRepresentation, 0700);
    }
}
NSString *iat_access_token(void) {
    static NSString *token;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        iat_prepare_storage();
        NSString *path = [iat_data_directory() stringByAppendingPathComponent:@"access-token"];
        NSString *saved = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        saved = [saved stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet];
        if (saved.length == 64 && [saved rangeOfCharacterFromSet:invalid].location == NSNotFound) {
            token = saved; chmod(path.fileSystemRepresentation, 0600); return;
        }
        unsigned char bytes[32];
        if (SecRandomCopyBytes(kSecRandomDefault, sizeof(bytes), bytes) != errSecSuccess) return;
        NSMutableString *generated = [NSMutableString string];
        for (size_t i = 0; i < sizeof(bytes); i++) [generated appendFormat:@"%02x", bytes[i]];
        if (![[generated dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path options:NSDataWritingAtomic error:nil]) return;
        chmod(path.fileSystemRepresentation, 0600);
        token = [generated copy];
    });
    return token;
}
