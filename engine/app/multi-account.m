#import "multi-account.h"
#import "app-control.h"
#import "../../daemon/runtime-paths.h"
#import <Security/Security.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <sys/stat.h>
#include <unistd.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <stdlib.h>

static __thread char account_error[1024];
static NSArray<NSString *> *data_names(void) { return @[@"Documents", @"Library", @"tmp"]; }
const char *account_last_error(void) { return account_error; }
BOOL account_valid_slot(int slot) { return slot >= 1 && slot <= 9999; }
static BOOL fail(NSString *message) {
    strlcpy(account_error, message.UTF8String ?: "Account operation failed", sizeof(account_error));
    return NO;
}
static BOOL fail_error(NSString *operation, NSError *error) {
    return fail([NSString stringWithFormat:@"%@: %@", operation, error.localizedDescription ?: @"failed"]);
}
static NSRecursiveLock *account_lock(void) {
    static NSRecursiveLock *lock; static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [NSRecursiveLock new]; }); return lock;
}
static BOOL validate(const char *bundle_id, int slot) {
    return c_app_valid_bundle_id(bundle_id) && account_valid_slot(slot) ? YES :
        fail(@"Invalid bundle identifier or account slot (expected 1...9999)");
}
static BOOL exists(NSString *path) { return [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil] != nil; }
static BOOL ordinary_directory(NSString *path) {
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    return [attributes[NSFileType] isEqualToString:NSFileTypeDirectory];
}
static BOOL mkdir_private(NSString *path) {
    NSFileManager *fm = NSFileManager.defaultManager;
    if (exists(path) && !ordinary_directory(path)) return fail(@"Account directory must not be a symlink or non-directory");
    NSDictionary *old = [fm attributesOfItemAtPath:path error:nil];
    if (old && [old[NSFileOwnerAccountID] unsignedIntValue] != geteuid()) return fail(@"Account storage directory has an unexpected owner");
    NSError *error = nil;
    NSDictionary *permissions = @{NSFilePosixPermissions:@0700,
        NSFileOwnerAccountID:@(geteuid()), NSFileGroupOwnerAccountID:@(getegid())};
    if (![fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:permissions error:&error] ||
        ![fm setAttributes:permissions ofItemAtPath:path error:&error])
        return fail_error(@"Create private account directory", error);
    return YES;
}
static NSString *bundle_store(const char *bundle_id, BOOL create) {
    // Canonicalize the trusted runtime base (/var may itself be an OS symlink),
    // then reject symlinks at the accounts/bundle components we control.
    NSString *base = [iat_data_directory() stringByResolvingSymlinksInPath];
    if (![base isAbsolutePath]) { fail(@"Data directory must be absolute"); return nil; }
#ifndef IAT_ACCOUNT_TESTING
    if (geteuid() != 0) { fail(@"Account operations require the root daemon"); return nil; }
#endif
    NSString *accounts = [base stringByAppendingPathComponent:@"accounts"];
    NSString *bundle = [accounts stringByAppendingPathComponent:@(bundle_id)];
    for (NSString *path in @[base, accounts, bundle]) {
        if (exists(path) && !ordinary_directory(path)) { fail(@"Unsafe account storage path"); return nil; }
        NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
        if (attributes && ([attributes[NSFileOwnerAccountID] unsignedIntValue] != geteuid() ||
            (!create && ([attributes[NSFilePosixPermissions] unsignedIntValue] & 0077)))) {
            fail(@"Account storage must be private and owned by the daemon"); return nil;
        }
        if (create && !mkdir_private(path)) return nil;
    }
    return bundle;
}
static NSString *slot_path(NSString *bundle, int slot) {
    return [bundle stringByAppendingPathComponent:[NSString stringWithFormat:@"slot_%d", slot]];
}

#ifdef IAT_ACCOUNT_TESTING
extern NSString *iat_test_account_container(NSString *bundle_id);
extern BOOL iat_test_account_copy(NSString *source, NSString *destination, NSError **error);
extern BOOL iat_test_account_move(NSString *source, NSString *destination, NSError **error);
extern OSStatus iat_test_account_keychain_delete(CFDictionaryRef query);
#define copy_item iat_test_account_copy
#define move_item iat_test_account_move
#define delete_keychain iat_test_account_keychain_delete
#else
static BOOL copy_item(NSString *source, NSString *destination, NSError **error) {
    return [NSFileManager.defaultManager copyItemAtPath:source toPath:destination error:error];
}
static BOOL move_item(NSString *source, NSString *destination, NSError **error) {
    return [NSFileManager.defaultManager moveItemAtPath:source toPath:destination error:error];
}
#define delete_keychain SecItemDelete
#endif

NSString *get_container_path(NSString *bundle_id) {
    if (!c_app_valid_bundle_id(bundle_id.UTF8String)) { fail(@"Invalid bundle identifier"); return nil; }
    NSString *found = nil;
#ifdef IAT_ACCOUNT_TESTING
    found = iat_test_account_container(bundle_id);
#else
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlopen("/System/Library/PrivateFrameworks/MobileContainerManager.framework/MobileContainerManager", RTLD_LAZY | RTLD_LOCAL);
    });
    @try {
        Class cls = NSClassFromString(@"MCMAppDataContainer");
        SEL selector = sel_registerName("containerWithIdentifier:createIfNecessary:existed:error:");
        if ([cls respondsToSelector:selector]) {
            BOOL existed = NO; NSError *error = nil;
            id container = ((id (*)(id, SEL, NSString *, BOOL, BOOL *, NSError **))objc_msgSend)
                (cls, selector, bundle_id, NO, &existed, &error);
            if ([container respondsToSelector:@selector(url)]) {
                NSURL *url = ((id (*)(id, SEL))objc_msgSend)(container, @selector(url));
                if ([url isKindOfClass:NSURL.class] && url.isFileURL) found = url.path;
            }
        }
    } @catch (__unused NSException *exception) { found = nil; }
    if (!found) {
        NSString *base = @"/private/var/mobile/Containers/Data/Application";
        for (NSString *entry in [NSFileManager.defaultManager contentsOfDirectoryAtPath:base error:nil]) {
            NSString *candidate = [base stringByAppendingPathComponent:entry];
            if (!ordinary_directory(candidate)) continue;
            NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:[candidate stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"]];
            if ([metadata[@"MCMMetadataIdentifier"] isEqual:bundle_id]) { found = candidate; break; }
        }
    }
#endif
    if (!found.isAbsolutePath || !ordinary_directory(found)) { fail(@"App data container not found"); return nil; }
    NSString *canonical = found.stringByResolvingSymlinksInPath;
#ifndef IAT_ACCOUNT_TESTING
    if (![canonical.stringByDeletingLastPathComponent isEqualToString:@"/private/var/mobile/Containers/Data/Application"]) {
        fail(@"Unexpected app container location"); return nil;
    }
#endif
    NSString *metadata_path = [canonical stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"];
    if (![[NSFileManager.defaultManager attributesOfItemAtPath:metadata_path error:nil][NSFileType] isEqual:NSFileTypeRegular]) {
        fail(@"Container metadata must be a regular file"); return nil;
    }
    NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:metadata_path];
    if (![metadata[@"MCMMetadataIdentifier"] isEqual:bundle_id]) { fail(@"Container metadata does not match bundle identifier"); return nil; }
    return canonical;
}

static BOOL safe_tree(NSString *root) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableArray *pending = [NSMutableArray arrayWithObject:root];
    while (pending.count) {
        NSString *path = pending.lastObject; [pending removeLastObject];
        NSError *error = nil;
        NSDictionary *attributes = [fm attributesOfItemAtPath:path error:&error];
        NSString *type = attributes[NSFileType];
        if ([type isEqualToString:NSFileTypeDirectory]) {
            NSArray *children = [fm contentsOfDirectoryAtPath:path error:&error];
            if (!children) return fail_error(@"Read snapshot directory", error);
            for (NSString *name in children) [pending addObject:[path stringByAppendingPathComponent:name]];
        } else if (![type isEqualToString:NSFileTypeRegular]) {
            return fail(@"Snapshot data contains a symlink, special file or unreadable item");
        }
    }
    return YES;
}
static BOOL mobile_ownership(NSString *root) {
    NSMutableArray *pending = [NSMutableArray arrayWithObject:root];
#ifdef IAT_ACCOUNT_TESTING
    uid_t uid = geteuid(); gid_t gid = getegid(); // Tests never require host root/mobile IDs.
#else
    uid_t uid = 501; gid_t gid = 501;
#endif
    NSFileManager *fm = NSFileManager.defaultManager;
    while (pending.count) {
        NSString *path = pending.lastObject; [pending removeLastObject];
        NSDictionary *attributes = [fm attributesOfItemAtPath:path error:nil];
        NSString *type = attributes[NSFileType];
        if (![type isEqualToString:NSFileTypeDirectory] && ![type isEqualToString:NSFileTypeRegular]) return fail(@"Unsafe item during restore ownership update");
        if (lchown(path.fileSystemRepresentation, uid, gid) != 0) return fail(@"Could not assign restored data to mobile owner");
        if ([type isEqualToString:NSFileTypeDirectory]) {
            NSError *error = nil; NSArray *children = [fm contentsOfDirectoryAtPath:path error:&error];
            if (!children) return fail_error(@"Read restored directory", error);
            for (NSString *name in children) [pending addObject:[path stringByAppendingPathComponent:name]];
        }
    }
    return YES;
}
static NSDictionary *read_snapshot(NSString *path, const char *bundle_id, int slot) {
    if (!ordinary_directory(path)) { fail(@"Saved account snapshot not found or unsafe"); return nil; }
    NSString *metadata_path = [path stringByAppendingPathComponent:@"metadata.json"];
    if (!exists(metadata_path)) { fail(@"Snapshot metadata is missing"); return nil; }
    if (!safe_tree(path)) return nil;
    NSData *data = [NSData dataWithContentsOfFile:metadata_path];
    id value = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![value isKindOfClass:NSDictionary.class] || ![value[@"bundleId"] isEqual:@(bundle_id)] ||
        ![value[@"slot"] isKindOfClass:NSNumber.class] || [value[@"slot"] intValue] != slot ||
        [value[@"slot"] doubleValue] != slot ||
        ![value[@"version"] isKindOfClass:NSNumber.class] || [value[@"version"] doubleValue] != 1 ||
        ![value[@"savedAt"] isKindOfClass:NSNumber.class] || ![value[@"name"] isKindOfClass:NSString.class] ||
        ![value[@"directories"] isKindOfClass:NSArray.class]) {
        fail(@"Invalid account snapshot metadata"); return nil;
    }
    if ([value[@"name"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 127 ||
        [value[@"name"] rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) {
        fail(@"Invalid snapshot label"); return nil;
    }
    NSArray *names = value[@"directories"];
    NSMutableSet *seen = [NSMutableSet set];
    for (id name in names) {
        if (![name isKindOfClass:NSString.class] || ![data_names() containsObject:name] || [seen containsObject:name]) {
            fail(@"Invalid snapshot data directory list"); return nil;
        }
        [seen addObject:name];
    }
    NSString *contents = [path stringByAppendingPathComponent:@"data"];
    NSArray *actual = [NSFileManager.defaultManager contentsOfDirectoryAtPath:contents error:nil];
    if (!ordinary_directory(contents) || !actual || ![[NSSet setWithArray:actual] isEqualToSet:seen]) {
        fail(@"Snapshot data does not match metadata"); return nil;
    }
    for (NSString *name in names) if (!ordinary_directory([contents stringByAppendingPathComponent:name])) {
        fail(@"Snapshot app data must contain directories"); return nil;
    }
    return value;
}
static BOOL write_metadata(NSDictionary *metadata, NSString *path) {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:metadata options:0 error:&error];
    if (!data || ![data writeToFile:path options:NSDataWritingAtomic error:&error]) return fail_error(@"Write snapshot metadata", error);
    return YES;
}
static void cleanup(NSString *path) { if (path) [NSFileManager.defaultManager removeItemAtPath:path error:nil]; }

BOOL save_account(const char *bundle_id, int slot) {
    [account_lock() lock]; @try {
        account_error[0] = 0;
        if (!validate(bundle_id, slot)) return NO;
        NSString *container = get_container_path(@(bundle_id));
        if (!container) return NO;
        if (!c_app_kill(bundle_id)) return fail([NSString stringWithFormat:@"Cannot stop app for snapshot: %s", c_app_last_error()]);
        NSString *bundle = bundle_store(bundle_id, YES); if (!bundle) return NO;
        NSString *target = slot_path(bundle, slot);
        if (exists(target) && !ordinary_directory(target)) return fail(@"Unsafe existing snapshot path");
        NSString *stage = [bundle stringByAppendingPathComponent:[@".stage-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        NSString *data = [stage stringByAppendingPathComponent:@"data"];
        if (!mkdir_private(data)) { cleanup(stage); return NO; }
        NSMutableArray *present = [NSMutableArray array];
        for (NSString *name in data_names()) {
            NSString *source = [container stringByAppendingPathComponent:name];
            if (!exists(source)) continue;
            if (!ordinary_directory(source) || !safe_tree(source)) { cleanup(stage); return fail(@"App data contains unsafe or unreadable directories"); }
            NSError *error = nil;
            if (!copy_item(source, [data stringByAppendingPathComponent:name], &error)) { cleanup(stage); return fail_error(@"Copy app snapshot", error); }
            [present addObject:name];
        }
        NSDictionary *metadata = @{@"version":@1, @"bundleId":@(bundle_id), @"slot":@(slot),
            @"savedAt":@([NSDate.date timeIntervalSince1970]), @"name":[NSString stringWithFormat:@"Account %d", slot], @"directories":present};
        if (!write_metadata(metadata, [stage stringByAppendingPathComponent:@"metadata.json"])) { cleanup(stage); return NO; }
        if (!safe_tree(stage)) { cleanup(stage); return NO; }
        NSString *previous = [bundle stringByAppendingPathComponent:[@".previous-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        BOOL had_previous = exists(target); NSError *error = nil;
        if (had_previous && !move_item(target, previous, &error)) { cleanup(stage); return fail_error(@"Preserve previous snapshot", error); }
        if (!move_item(stage, target, &error)) {
            NSError *rollback_error = nil;
            BOOL rolled_back = !had_previous || move_item(previous, target, &rollback_error);
            cleanup(stage);
            if (!rolled_back) return fail([NSString stringWithFormat:@"Snapshot commit and rollback failed; previous snapshot preserved at %@", previous]);
            return fail_error(@"Commit snapshot (previous restored)", error);
        }
        cleanup(previous);
        return YES;
    } @finally { [account_lock() unlock]; }
}

BOOL switch_account(const char *bundle_id, int slot) {
    [account_lock() lock]; @try {
        account_error[0] = 0;
        if (!validate(bundle_id, slot)) return NO;
        NSString *bundle = bundle_store(bundle_id, NO); if (!bundle) return NO;
        NSString *snapshot = slot_path(bundle, slot);
        NSDictionary *metadata = read_snapshot(snapshot, bundle_id, slot); if (!metadata) return NO;
        NSString *container = get_container_path(@(bundle_id)); if (!container) return NO;
        if (!c_app_kill(bundle_id)) return fail([NSString stringWithFormat:@"Cannot stop app before restore: %s", c_app_last_error()]);
        for (NSString *name in data_names()) {
            NSString *live = [container stringByAppendingPathComponent:name];
            if (exists(live) && (!ordinary_directory(live) || !safe_tree(live))) return fail(@"Current app data contains unsafe items");
        }
        NSString *workspace = [container stringByAppendingPathComponent:[@".iosautotool-restore-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        NSString *incoming = [workspace stringByAppendingPathComponent:@"incoming"];
        NSString *rollback = [workspace stringByAppendingPathComponent:@"rollback"];
        if (!mkdir_private(incoming) || !mkdir_private(rollback)) { cleanup(workspace); return NO; }
        for (NSString *name in metadata[@"directories"]) {
            NSString *target = [incoming stringByAppendingPathComponent:name]; NSError *error = nil;
            if (!copy_item([[snapshot stringByAppendingPathComponent:@"data"] stringByAppendingPathComponent:name], target, &error)) {
                cleanup(workspace); return fail_error(@"Stage restore", error);
            }
            if (!safe_tree(target) || !mobile_ownership(target)) { cleanup(workspace); return NO; }
        }
        NSMutableArray *touched = [NSMutableArray array]; NSError *failure = nil; BOOL restore_failed = NO;
        for (NSString *name in data_names()) {
            NSString *live = [container stringByAppendingPathComponent:name];
            NSString *old = [rollback stringByAppendingPathComponent:name];
            if (exists(live) && !move_item(live, old, &failure)) { restore_failed = YES; break; }
            [touched addObject:name];
            NSString *staged = [incoming stringByAppendingPathComponent:name];
            if (exists(staged) && !move_item(staged, live, &failure)) { restore_failed = YES; break; }
        }
        if (restore_failed) {
            BOOL recovered = YES;
            for (NSString *name in touched.reverseObjectEnumerator) {
                NSString *live = [container stringByAppendingPathComponent:name];
                NSString *old = [rollback stringByAppendingPathComponent:name]; NSError *error = nil;
                if (exists(live) && ![NSFileManager.defaultManager removeItemAtPath:live error:&error]) { recovered = NO; continue; }
                if (exists(old) && !move_item(old, live, &error)) recovered = NO;
            }
            if (!recovered) return fail([NSString stringWithFormat:@"Restore failed and rollback is incomplete; original data preserved at %@", workspace]);
            cleanup(workspace); return fail_error(@"Restore failed (original app data restored)", failure);
        }
        NSError *cleanup_error = nil;
        if (![NSFileManager.defaultManager removeItemAtPath:workspace error:&cleanup_error]) return fail_error(@"Data restored but rollback cleanup failed", cleanup_error);
        if (!c_app_run(bundle_id)) return fail([NSString stringWithFormat:@"Data restored, but app launch failed: %s", c_app_last_error()]);
        return YES;
    } @finally { [account_lock() unlock]; }
}

BOOL delete_account(const char *bundle_id, int slot) {
    [account_lock() lock]; @try {
        account_error[0] = 0; if (!validate(bundle_id, slot)) return NO;
        NSString *bundle = bundle_store(bundle_id, NO); if (!bundle) return NO;
        NSString *path = slot_path(bundle, slot);
        if (!read_snapshot(path, bundle_id, slot)) return NO;
        NSError *error = nil;
        return [NSFileManager.defaultManager removeItemAtPath:path error:&error] ? YES : fail_error(@"Delete snapshot", error);
    } @finally { [account_lock() unlock]; }
}
BOOL name_account(const char *bundle_id, int slot, const char *label) {
    [account_lock() lock]; @try {
        account_error[0] = 0; if (!validate(bundle_id, slot)) return NO;
        NSString *name = label ? [NSString stringWithUTF8String:label] : nil;
        if (!name.length || [name lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 127 ||
            [name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) return fail(@"Invalid account label (maximum 127 UTF-8 bytes)");
        NSString *bundle = bundle_store(bundle_id, NO); if (!bundle) return NO;
        NSString *path = slot_path(bundle, slot);
        NSMutableDictionary *metadata = [read_snapshot(path, bundle_id, slot) mutableCopy]; if (!metadata) return NO;
        metadata[@"name"] = name;
        return write_metadata(metadata, [path stringByAppendingPathComponent:@"metadata.json"]);
    } @finally { [account_lock() unlock]; }
}
AccountSlot *list_accounts(const char *bundle_id, int *count) {
    [account_lock() lock]; @try {
        account_error[0] = 0;
        if (!count) { fail(@"Missing account count output"); return NULL; }
        *count = -1; if (!c_app_valid_bundle_id(bundle_id)) { fail(@"Invalid bundle identifier"); return NULL; }
        NSString *bundle = bundle_store(bundle_id, NO); if (!bundle) return NULL;
        NSMutableArray *metadata = [NSMutableArray array];
        NSError *listing_error = nil;
        NSArray *entries = exists(bundle) ? [NSFileManager.defaultManager contentsOfDirectoryAtPath:bundle error:&listing_error] : @[];
        if (!entries) { fail_error(@"List account snapshots", listing_error); return NULL; }
        for (NSString *entry in entries) {
            if (![entry hasPrefix:@"slot_"]) continue;
            NSString *suffix = [entry substringFromIndex:5];
            NSScanner *scanner = [NSScanner scannerWithString:suffix]; int slot;
            if (![scanner scanInt:&slot] || !scanner.isAtEnd || !account_valid_slot(slot) || ![entry isEqualToString:[NSString stringWithFormat:@"slot_%d", slot]]) continue;
            NSDictionary *value = read_snapshot([bundle stringByAppendingPathComponent:entry], bundle_id, slot);
            if (!value) return NULL;
            [metadata addObject:value];
        }
        [metadata sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"slot"] compare:b[@"slot"]]; }];
        AccountSlot *slots = calloc(MAX((NSUInteger)1, metadata.count), sizeof(AccountSlot));
        if (!slots) { fail(@"Out of memory"); return NULL; }
        for (NSUInteger index = 0; index < metadata.count; index++) {
            NSDictionary *value = metadata[index];
            slots[index].slot = [value[@"slot"] intValue]; slots[index].saved_at = [value[@"savedAt"] doubleValue];
            NSString *name = [value[@"name"] isKindOfClass:NSString.class] ? value[@"name"] : @"";
            strlcpy(slots[index].name, name.UTF8String, sizeof(slots[index].name));
        }
        *count = (int)metadata.count; return slots;
    } @finally { [account_lock() unlock]; }
}
BOOL clear_keychain_for_app(const char *bundle_id) {
    account_error[0] = 0;
    if (!c_app_valid_bundle_id(bundle_id)) return fail(@"Invalid bundle identifier");
    NSDictionary *generic = @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService:@(bundle_id)};
    NSDictionary *internet = @{(__bridge id)kSecClass:(__bridge id)kSecClassInternetPassword,
        (__bridge id)kSecAttrServer:@(bundle_id)};
    OSStatus first = delete_keychain((__bridge CFDictionaryRef)generic);
    OSStatus second = delete_keychain((__bridge CFDictionaryRef)internet);
    if ((first != errSecSuccess && first != errSecItemNotFound) || (second != errSecSuccess && second != errSecItemNotFound))
        return fail([NSString stringWithFormat:@"Limited keychain deletion failed (%d, %d); app access groups were not enumerated", (int)first, (int)second]);
    return YES;
}
