#import <Foundation/Foundation.h>
#import "../daemon/runtime-paths.h"
#include <assert.h>
#include <sys/stat.h>
#include <unistd.h>
int main(void) {
    @autoreleasepool {
        NSString *base=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        setenv("IAT_DATA_DIR",base.fileSystemRepresentation,1);
        NSString *directory=iat_temporary_directory(); assert(directory);
        NSString *first=iat_create_temporary_file(), *second=iat_create_temporary_file();
        assert(first && second && ![first isEqual:second]);
        assert([[first stringByDeletingLastPathComponent] isEqual:directory]);
        struct stat info; assert(lstat(first.fileSystemRepresentation,&info)==0);
        assert(S_ISREG(info.st_mode) && (info.st_mode&0777)==0600 && info.st_size==0);
        assert(unlink(first.fileSystemRepresentation)==0 && unlink(second.fileSystemRepresentation)==0);
        assert([NSFileManager.defaultManager removeItemAtPath:base error:nil]);
        puts("Runtime private temporary path tests passed");
    }
    return 0;
}
