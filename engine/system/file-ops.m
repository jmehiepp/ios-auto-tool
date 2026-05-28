#import "file-ops.h"
#import <Foundation/Foundation.h>
#include <stdlib.h>
#include <string.h>

NSString *c_read_file(const char *path) {
    NSError *err = nil;
    NSString *s = [NSString stringWithContentsOfFile:@(path)
                                            encoding:NSUTF8StringEncoding
                                               error:&err];
    return err ? nil : s;
}

BOOL c_write_file(const char *path, const char *content) {
    NSString *p = @(path);
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [p stringByDeletingLastPathComponent];
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES
                   attributes:nil error:nil];
    NSString *s = content ? @(content) : @"";
    return [s writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

BOOL c_append_file(const char *path, const char *content) {
    NSString *p = @(path);
    NSFileManager *fm = [NSFileManager defaultManager];

    if (![fm fileExistsAtPath:p]) return c_write_file(path, content);

    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:p];
    if (!fh) return NO;
    [fh seekToEndOfFile];
    NSData *data = [@(content ?: "") dataUsingEncoding:NSUTF8StringEncoding];
    [fh writeData:data];
    [fh closeFile];
    return YES;
}

BOOL c_delete_file(const char *path) {
    NSError *err = nil;
    [[NSFileManager defaultManager] removeItemAtPath:@(path) error:&err];
    return err == nil;
}

BOOL c_file_exists(const char *path) {
    return [[NSFileManager defaultManager] fileExistsAtPath:@(path)];
}

BOOL c_make_dir(const char *path) {
    NSError *err = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:@(path)
                                withIntermediateDirectories:YES
                                               attributes:nil error:&err];
    return err == nil;
}

BOOL c_copy_file(const char *src, const char *dst) {
    NSError *err = nil;
    [[NSFileManager defaultManager] copyItemAtPath:@(src) toPath:@(dst) error:&err];
    return err == nil;
}

BOOL c_move_file(const char *src, const char *dst) {
    NSError *err = nil;
    [[NSFileManager defaultManager] moveItemAtPath:@(src) toPath:@(dst) error:&err];
    return err == nil;
}

long c_file_size(const char *path) {
    NSDictionary *attrs = [[NSFileManager defaultManager]
                           attributesOfItemAtPath:@(path) error:nil];
    return attrs ? [attrs[NSFileSize] longValue] : -1;
}

DirEntry *c_list_dir(const char *path, int *count) {
    *count = 0;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *err = nil;
    NSArray *items = [fm contentsOfDirectoryAtPath:@(path) error:&err];
    if (err || !items) return NULL;

    DirEntry *arr = calloc((size_t)items.count, sizeof(DirEntry));
    if (!arr) return NULL;

    for (NSString *name in items) {
        NSString *full = [@(path) stringByAppendingPathComponent:name];
        NSDictionary *attrs = [fm attributesOfItemAtPath:full error:nil];

        DirEntry *e = &arr[*count];
        strncpy(e->name, name.UTF8String, sizeof(e->name) - 1);
        e->is_dir   = [attrs[NSFileType] isEqual:NSFileTypeDirectory] ? 1 : 0;
        e->size     = [attrs[NSFileSize] longValue];
        e->modified = [attrs[NSFileModificationDate] timeIntervalSince1970];
        (*count)++;
    }
    return arr;
}
