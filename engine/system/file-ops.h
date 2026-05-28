#pragma once
#import <Foundation/Foundation.h>

typedef struct {
    char   name[256];
    int    is_dir;
    long   size;
    double modified;  // Unix timestamp
} DirEntry;

NSString   *c_read_file(const char *path);
BOOL        c_write_file(const char *path, const char *content);
BOOL        c_append_file(const char *path, const char *content);
BOOL        c_delete_file(const char *path);
BOOL        c_file_exists(const char *path);
BOOL        c_make_dir(const char *path);
BOOL        c_copy_file(const char *src, const char *dst);
BOOL        c_move_file(const char *src, const char *dst);
long        c_file_size(const char *path);

// Returns heap-allocated array; caller frees. count set to length.
DirEntry   *c_list_dir(const char *path, int *count);
