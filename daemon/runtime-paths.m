#import "runtime-paths.h"
#import "platform-paths.h"
#import <Security/Security.h>
#include <mach-o/dyld.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

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
    return override && override[0] ? @(override) : IAT_PATH(@"/var/mobile/Library/IOSAutoTool");
}
NSString *iat_temporary_directory(void) {
    iat_prepare_storage();
    NSString *path=[iat_data_directory() stringByAppendingPathComponent:@"tmp"];
    if (![NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:NO
            attributes:@{NSFilePosixPermissions:@0700} error:nil]) return nil;
    path=path.stringByResolvingSymlinksInPath;
    struct stat info;
    if (lstat(path.fileSystemRepresentation,&info)!=0 || !S_ISDIR(info.st_mode) ||
        info.st_uid!=geteuid() || (info.st_mode & 0077)!=0) return nil;
    return path;
}
NSString *iat_create_temporary_file(void) {
    NSString *directory=iat_temporary_directory(); if (!directory) return nil;
    char *pattern=strdup([[directory stringByAppendingPathComponent:@"lua-XXXXXX"] fileSystemRepresentation]);
    if (!pattern) return nil;
    int fd=mkstemp(pattern);
    if (fd<0) { free(pattern); return nil; }
    fcntl(fd,F_SETFD,FD_CLOEXEC); close(fd);
    NSString *path=@(pattern); free(pattern); return path;
}
void iat_prepare_storage(void) {
    for (NSString *subdir in @[@"", @"scripts", @"accounts"]) {
        NSString *path = [iat_data_directory() stringByAppendingPathComponent:subdir];
        [NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES
                       attributes:@{NSFilePosixPermissions: @0700} error:nil];
        chmod(path.fileSystemRepresentation, 0700);
    }
    NSString *scripts = [iat_data_directory() stringByAppendingPathComponent:@"scripts"];
    if ([NSFileManager.defaultManager contentsOfDirectoryAtPath:scripts error:nil].count == 0) {
        [@"log('iOS Auto Tool ready')\nsleep(250)\nlog('Finished')\n" writeToFile:
            [scripts stringByAppendingPathComponent:@"hello.lua"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
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
