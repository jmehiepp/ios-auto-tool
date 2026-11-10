#import "widget-service.h"
#import "runtime-paths.h"
#import "script-runner.h"
#import "platform-paths.h"
#import <Foundation/Foundation.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <poll.h>
#include <errno.h>
#include <string.h>

extern int proc_pidpath(int pid, void *buffer, uint32_t buffersize);
#ifndef LOCAL_PEERPID
#define LOCAL_PEERPID 0x002
#endif

static NSString *Scripts(void) { return [iat_data_directory() stringByAppendingPathComponent:@"scripts"]; }
static BOOL ValidName(id name) {
    return [name isKindOfClass:NSString.class] && [name length] > 4 && [name lengthOfBytesUsingEncoding:NSUTF8StringEncoding] < 256 &&
        [name hasSuffix:@".lua"] && ![name hasPrefix:@"."] &&
        [name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location == NSNotFound &&
        [name rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/\\\n\r"]].location == NSNotFound;
}
static NSArray *Names(void) {
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:Scripts() error:nil]) {
        struct stat info;
        NSString *path = [Scripts() stringByAppendingPathComponent:name];
        if (ValidName(name) && lstat(path.fileSystemRepresentation, &info) == 0 && S_ISREG(info.st_mode)) [names addObject:name];
    }
    return [names sortedArrayUsingSelector:@selector(compare:)];
}
static NSDictionary *Handle(NSDictionary *request) {
    id identifier = [request[@"id"] isKindOfClass:NSString.class] ? request[@"id"] : @"";
    NSString *action = request[@"action"];
    if (![action isKindOfClass:NSString.class]) return @{@"id":identifier, @"ok":@NO, @"error":@"Missing action"};
    if ([action isEqual:@"list_scripts"])
        return @{@"id":identifier, @"ok":@YES, @"scripts":Names(), @"running":@(script_is_running())};
    if ([action isEqual:@"script_status"])
        return @{@"id":identifier, @"ok":@YES, @"running":@(script_is_running())};
    if ([action isEqual:@"stop_script"]) {
        script_stop_current();
        return @{@"id":identifier, @"ok":@YES, @"running":@(script_is_running())};
    }
    if ([action isEqual:@"run_saved_script"] && ValidName(request[@"name"])) {
        NSString *path = [Scripts() stringByAppendingPathComponent:request[@"name"]];
        int source = open(path.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW);
        struct stat info;
        if (source < 0) return @{@"id":identifier, @"ok":@NO, @"error":@"Script not found"};
        NSMutableData *data = [NSMutableData data];
        BOOL valid = fstat(source, &info) == 0 && S_ISREG(info.st_mode) && info.st_size <= 1024 * 1024;
        char buffer[8192]; ssize_t count;
        while (valid && (count = read(source, buffer, sizeof(buffer))) > 0) {
            [data appendBytes:buffer length:(NSUInteger)count];
            if (data.length > 1024 * 1024) valid = NO;
        }
        close(source);
        NSString *code = valid ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
        if (!code || [code rangeOfString:[NSString stringWithFormat:@"%C", (unichar)0]].location != NSNotFound)
            return @{@"id":identifier, @"ok":@NO, @"error":@"Invalid script"};
        BOOL accepted = script_run(-1, "widget", code.UTF8String);
        return accepted ? @{@"id":identifier, @"ok":@YES, @"running":@YES} :
            @{@"id":identifier, @"ok":@NO, @"error":@"A script is already running"};
    }
    return @{@"id":identifier, @"ok":@NO, @"error":@"Unsupported request"};
}
static BOOL AllowedPeer(int client) {
    uid_t uid; gid_t gid;
    if (getpeereid(client, &uid, &gid) != 0) return NO;
    if (uid == 0) return YES;
    if (uid != 501) return NO;
    pid_t pid = 0; socklen_t size = sizeof(pid); char path[4096] = {0};
    return getsockopt(client, SOL_LOCAL, LOCAL_PEERPID, &pid, &size) == 0 && pid > 0 &&
        proc_pidpath(pid, path, sizeof(path)) > 0 &&
        strcmp(path, "/System/Library/CoreServices/SpringBoard.app/SpringBoard") == 0;
}
static void Serve(int client) {
    @autoreleasepool {
        struct timeval deadline = {3, 0};
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &deadline, sizeof(deadline));
        setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &deadline, sizeof(deadline));
        NSMutableData *frame = [NSMutableData data];
        BOOL complete = NO;
        // A fixed total deadline also bounds clients that trickle bytes.
        NSTimeInterval end = NSDate.timeIntervalSinceReferenceDate + 3;
        while (frame.length < 65536 && NSDate.timeIntervalSinceReferenceDate < end) {
            struct pollfd wait = {client, POLLIN, 0};
            int ms = (int)((end - NSDate.timeIntervalSinceReferenceDate) * 1000);
            if (ms <= 0 || poll(&wait, 1, ms) <= 0) break;
            char byte; if (read(client, &byte, 1) != 1) break;
            if (byte == '\n') { complete = YES; break; }
            [frame appendBytes:&byte length:1];
        }
        id request = complete ? [NSJSONSerialization JSONObjectWithData:frame options:0 error:nil] : nil;
        NSDictionary *result = [request isKindOfClass:NSDictionary.class] ? Handle(request) : @{@"ok":@NO, @"error":@"Invalid frame"};
        NSMutableData *response = [[NSJSONSerialization dataWithJSONObject:result options:0 error:nil] mutableCopy];
        [response appendBytes:"\n" length:1];
        const char *bytes = response.bytes; size_t sent = 0;
        while (sent < response.length) {
            ssize_t n = send(client, bytes + sent, response.length - sent, 0);
            if (n <= 0) break;
            sent += (size_t)n;
        }
        close(client);
    }
}
void widget_service_start(void) {
    const char *path = IAT_PATH("/var/run/iosautotool-widget.sock");
    int server = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server < 0) return;
    struct sockaddr_un address = {0}; address.sun_family = AF_UNIX;
    strlcpy(address.sun_path, path, sizeof(address.sun_path)); unlink(path);
    if (bind(server, (struct sockaddr *)&address, sizeof(address)) || chown(path, 0, 501) || chmod(path, 0660) || listen(server, 8)) {
        close(server); unlink(path); return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        while (1) {
            int client = accept(server, NULL, NULL);
            if (client < 0) continue;
            if (!AllowedPeer(client)) { close(client); continue; }
            // Requests are tiny and bounded; serialize to prevent unbounded worker creation.
            Serve(client);
        }
    });
}
