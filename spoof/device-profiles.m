#import "device-profiles.h"
#import "spoof-config.h"
#import "../daemon/runtime-paths.h"
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

NSString * const DeviceProfilesErrorDomain = @"IOSAutoTool.DeviceProfiles";
static const NSUInteger ProfileByteLimit = 256 * 1024;

typedef struct { int directory; int lock; } ProfileScope;

static BOOL ProfileError(NSError **error, NSInteger code, NSString *description) {
    if (error) *error = [NSError errorWithDomain:DeviceProfilesErrorDomain code:code
                                      userInfo:@{NSLocalizedDescriptionKey:description}];
    return NO;
}
static BOOL ProfilePOSIXError(NSError **error, NSString *operation, int number) {
    NSString *detail = [NSString stringWithUTF8String:strerror(number)] ?: @"unknown filesystem error";
    return ProfileError(error, number, [NSString stringWithFormat:@"%@: %@", operation, detail]);
}
static BOOL ValidProfileName(NSString *name, NSError **error) {
    if (![name isKindOfClass:NSString.class] || name.length < 1 || name.length > 64)
        return ProfileError(error, EINVAL, @"Profile name must have 1-64 ASCII letters, digits, '-' or '_'");
    NSCharacterSet *first = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"];
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"];
    if (![first characterIsMember:[name characterAtIndex:0]] ||
        [name rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound)
        return ProfileError(error, EINVAL, @"Profile name must be a safe ASCII basename, starting with a letter or digit");
    return YES;
}
static BOOL OwnedRegularFile(struct stat info, BOOL strictMode, NSError **error) {
    if (!S_ISREG(info.st_mode) || info.st_nlink != 1 || info.st_uid != geteuid())
        return ProfileError(error, EPERM, @"Profile storage must be a regular owned file, without links");
    if (strictMode && (info.st_mode & 0777) != 0600)
        return ProfileError(error, EPERM, @"Profile file permissions must be 0600");
    return YES;
}
static void CloseProfileScope(ProfileScope scope) {
    if (scope.lock >= 0) { flock(scope.lock, LOCK_UN); close(scope.lock); }
    if (scope.directory >= 0) close(scope.directory);
}
static ProfileScope OpenProfileScope(NSError **error) {
    ProfileScope scope = {-1, -1};
#ifndef IOSAT_DEVICE_TESTING
    if (geteuid() != 0) {
        ProfileError(error, EPERM, @"Device profiles must be accessed through the root daemon");
        return scope;
    }
#endif
    NSString *base = iat_data_directory();
    if (![base isKindOfClass:NSString.class] || !base.isAbsolutePath) {
        ProfileError(error, EINVAL, @"Device profile data directory must be an absolute trusted path");
        return scope;
    }
    // iat_prepare_storage normally creates this base. Reject a symlink at its
    // final component; standard OS ancestor aliases such as /var are permitted.
    struct stat info;
    if (lstat(base.fileSystemRepresentation, &info) != 0) {
        if (errno != ENOENT || mkdir(base.fileSystemRepresentation, 0700) != 0) {
            ProfilePOSIXError(error, @"Open profile data directory", errno); return scope;
        }
    }
    int baseFD = open(base.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (baseFD < 0) { ProfilePOSIXError(error, @"Open profile data directory", errno); return scope; }
    if (fstat(baseFD, &info) != 0 || !S_ISDIR(info.st_mode) || info.st_uid != geteuid() ||
        (info.st_mode & 0022) != 0) {
        close(baseFD);
        ProfileError(error, EPERM, @"Profile data directory must be owned by the daemon and not writable by other users");
        return scope;
    }
    if (mkdirat(baseFD, "device-profiles", 0700) != 0 && errno != EEXIST) {
        int number = errno; close(baseFD); ProfilePOSIXError(error, @"Create device-profiles directory", number); return scope;
    }
    scope.directory = openat(baseFD, "device-profiles", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    close(baseFD);
    if (scope.directory < 0) { ProfilePOSIXError(error, @"Open device-profiles directory", errno); return scope; }
    if (fstat(scope.directory, &info) != 0 || !S_ISDIR(info.st_mode) || info.st_uid != geteuid() ||
        fchmod(scope.directory, 0700) != 0) {
        CloseProfileScope(scope);
        ProfileError(error, EPERM, @"Device profile directory must be owned by the daemon with mode 0700");
        return (ProfileScope){-1, -1};
    }
    scope.lock = openat(scope.directory, ".lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (scope.lock < 0) {
        int number = errno; CloseProfileScope(scope); ProfilePOSIXError(error, @"Open profile lock", number);
        return (ProfileScope){-1, -1};
    }
    if (fstat(scope.lock, &info) != 0 || !OwnedRegularFile(info, NO, error) ||
        fchmod(scope.lock, 0600) != 0 || flock(scope.lock, LOCK_EX) != 0) {
        int number = errno;
        CloseProfileScope(scope);
        if (!error || !*error) ProfilePOSIXError(error, @"Lock device profiles", number ?: EIO);
        return (ProfileScope){-1, -1};
    }
    return scope;
}
static NSString *ProfileFilename(NSString *name) { return [name stringByAppendingString:@".plist"]; }

static BOOL ValidateExistingTarget(int directory, NSString *filename, BOOL required, NSError **error) {
    struct stat info;
    if (fstatat(directory, filename.fileSystemRepresentation, &info, AT_SYMLINK_NOFOLLOW) == 0)
        return OwnedRegularFile(info, NO, error);
    if (errno == ENOENT && !required) return YES;
    return ProfilePOSIXError(error, @"Inspect named device profile", errno);
}
static BOOL WriteProfile(int directory, NSString *filename, NSData *data, NSError **error) {
    if (!ValidateExistingTarget(directory, filename, NO, error)) return NO;
    char temporary[80];
    int fd = -1;
    for (int attempt=0; attempt<8; attempt++) {
        snprintf(temporary, sizeof(temporary), ".tmp-%ld-%08x", (long)getpid(), arc4random());
        fd = openat(directory, temporary, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, 0600);
        if (fd >= 0 || errno != EEXIST) break;
    }
    if (fd < 0) return ProfilePOSIXError(error, @"Create atomic profile temporary file", errno);
    BOOL ok = YES;
    NSUInteger written = 0;
    while (written < data.length) {
        ssize_t amount = write(fd, (const char *)data.bytes + written, data.length - written);
        if (amount < 0 && errno == EINTR) continue;
        if (amount <= 0) { ok = ProfilePOSIXError(error, @"Write device profile", amount < 0 ? errno : EIO); break; }
        written += (NSUInteger)amount;
    }
    if (ok && (fchmod(fd, 0600) != 0 || fsync(fd) != 0))
        ok = ProfilePOSIXError(error, @"Flush device profile", errno);
    if (close(fd) != 0 && ok) ok = ProfilePOSIXError(error, @"Close device profile", errno);
    if (ok && renameat(directory, temporary, directory, filename.fileSystemRepresentation) != 0)
        ok = ProfilePOSIXError(error, @"Commit device profile", errno);
    if (!ok) unlinkat(directory, temporary, 0);
    return ok;
}
static NSDictionary *ReadProfile(int directory, NSString *filename, NSError **error) {
    int fd = openat(directory, filename.fileSystemRepresentation,
                    O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
    if (fd < 0) { ProfilePOSIXError(error, @"Read device profile", errno); return nil; }
    struct stat info;
    if (fstat(fd, &info) != 0) {
        int number=errno; close(fd); ProfilePOSIXError(error, @"Inspect opened profile", number); return nil;
    }
    if (!OwnedRegularFile(info, YES, error)) { close(fd); return nil; }
    if (info.st_size <= 0 || (uint64_t)info.st_size > ProfileByteLimit) {
        close(fd); ProfileError(error, EFBIG, @"Device profile must contain 1-262144 bytes"); return nil;
    }
    NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)info.st_size];
    NSUInteger received=0;
    while (received < data.length) {
        ssize_t amount=read(fd, (char *)data.mutableBytes + received, data.length-received);
        if (amount < 0 && errno == EINTR) continue;
        if (amount <= 0) {
            int number=amount < 0 ? errno : EIO; close(fd);
            ProfilePOSIXError(error, @"Read complete device profile", number); return nil;
        }
        received += (NSUInteger)amount;
    }
    char extra;
    ssize_t remaining;
    do { remaining=read(fd, &extra, 1); } while (remaining < 0 && errno == EINTR);
    close(fd);
    if (remaining != 0) { ProfileError(error, EIO, @"Profile changed size while reading"); return nil; }
    id profile = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable
                                                          format:NULL error:error];
    if (!profile) return nil;
    if (![SpoofConfig validateConfiguration:profile error:error]) return nil;
    return profile;
}

@implementation DeviceProfiles
+ (NSArray<NSString *> *)namesWithError:(NSError **)error {
    if (error) *error = nil;
    ProfileScope scope=OpenProfileScope(error);
    if (scope.directory < 0) return nil;
    int scanFD=dup(scope.directory);
    DIR *scan=scanFD >= 0 ? fdopendir(scanFD) : NULL;
    if (!scan) {
        int number=errno; if (scanFD >= 0) close(scanFD); CloseProfileScope(scope);
        ProfilePOSIXError(error, @"List device profiles", number); return nil;
    }
    NSMutableArray<NSString *> *names=[NSMutableArray array];
    BOOL ok=YES;
    struct dirent *entry;
    errno=0;
    while ((entry=readdir(scan)) != NULL) {
        NSString *filename=[NSString stringWithUTF8String:entry->d_name];
        if (!filename || ![filename hasSuffix:@".plist"]) { errno=0; continue; }
        NSString *name=[filename stringByDeletingPathExtension];
        if (!ValidProfileName(name, NULL)) { errno=0; continue; }
        struct stat info;
        if (fstatat(scope.directory, entry->d_name, &info, AT_SYMLINK_NOFOLLOW) != 0) {
            ok=ProfilePOSIXError(error, @"Inspect profile while listing", errno); break;
        }
        if (!OwnedRegularFile(info, YES, error)) { ok=NO; break; }
        [names addObject:name];
        errno=0;
    }
    if (ok && errno != 0) ok=ProfilePOSIXError(error, @"Finish profile listing", errno);
    closedir(scan);
    CloseProfileScope(scope);
    return ok ? [names sortedArrayUsingSelector:@selector(compare:)] : nil;
}
+ (BOOL)saveCurrentAs:(NSString *)name error:(NSError **)error {
    if (error) *error=nil;
    if (!ValidProfileName(name, error)) return NO;
    NSDictionary *configuration=[[SpoofConfig shared] getAll];
    if (![SpoofConfig validateConfiguration:configuration error:error]) return NO;
    NSData *data=[NSPropertyListSerialization dataWithPropertyList:configuration
        format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    if (!data) return NO;
    if (data.length > ProfileByteLimit)
        return ProfileError(error, EFBIG, @"Serialized device profile exceeds 256 KiB");
    ProfileScope scope=OpenProfileScope(error);
    if (scope.directory < 0) return NO;
    BOOL ok=WriteProfile(scope.directory, ProfileFilename(name), data, error);
    CloseProfileScope(scope);
    return ok;
}
+ (BOOL)applyNamed:(NSString *)name error:(NSError **)error {
    if (error) *error=nil;
    if (!ValidProfileName(name, error)) return NO;
    ProfileScope scope=OpenProfileScope(error);
    if (scope.directory < 0) return NO;
    NSDictionary *configuration=ReadProfile(scope.directory, ProfileFilename(name), error);
    CloseProfileScope(scope);
    if (!configuration) return NO;
    return [[SpoofConfig shared] setConfiguration:configuration error:error];
}
+ (BOOL)deleteNamed:(NSString *)name error:(NSError **)error {
    if (error) *error=nil;
    if (!ValidProfileName(name, error)) return NO;
    ProfileScope scope=OpenProfileScope(error);
    if (scope.directory < 0) return NO;
    NSString *filename=ProfileFilename(name);
    BOOL ok=ValidateExistingTarget(scope.directory, filename, YES, error);
    if (ok && unlinkat(scope.directory, filename.fileSystemRepresentation, 0) != 0)
        ok=ProfilePOSIXError(error, @"Delete device profile", errno);
    CloseProfileScope(scope);
    return ok;
}
+ (BOOL)renameNamed:(NSString *)name to:(NSString *)newName error:(NSError **)error {
    if (error) *error=nil;
    if (!ValidProfileName(name, error) || !ValidProfileName(newName, error)) return NO;
    ProfileScope scope=OpenProfileScope(error);
    if (scope.directory < 0) return NO;
    NSString *source=ProfileFilename(name), *destination=ProfileFilename(newName);
    BOOL ok=ReadProfile(scope.directory, source, error) != nil;
    if (ok && ![name isEqual:newName] &&
        renameatx_np(scope.directory, source.fileSystemRepresentation, scope.directory,
                     destination.fileSystemRepresentation, RENAME_EXCL) != 0)
        ok=ProfilePOSIXError(error, @"Rename device profile without replacing another profile", errno);
    CloseProfileScope(scope); return ok;
}
@end
