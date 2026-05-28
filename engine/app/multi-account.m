#import "multi-account.h"
#import "app-control.h"
#import "../../engine/system/shell-exec.h"
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <unistd.h>
#import <string.h>
#import <stdlib.h>

#define ACCOUNTS_BASE "/Library/IOSAutoTool/accounts"

// MCMContainer private framework
extern id MCMContainerCreate(NSString *type, NSString *bundleId);

NSString *get_container_path(NSString *bundle_id) {
    // iOS 8+ MCMContainer approach
    Class MCMAppContainer = NSClassFromString(@"MCMAppContainer");
    if (MCMAppContainer) {
        id container = [MCMAppContainer performSelector:
                        @selector(containerWithBundleIdentifier:)
                        withObject:bundle_id];
        if (container) {
            NSURL *url = [container performSelector:@selector(url)];
            return url.path;
        }
    }
    // Fallback: glob the container UUID directories
    NSString *base = @"/private/var/mobile/Containers/Data/Application";
    NSArray *uuids = [[NSFileManager defaultManager]
                      contentsOfDirectoryAtPath:base error:nil];
    for (NSString *uuid in uuids) {
        NSString *meta = [NSString stringWithFormat:
            @"%@/%@/.com.apple.mobile_container_manager.metadata.plist",
            base, uuid];
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:meta];
        if ([d[@"MCMMetadataIdentifier"] isEqualToString:bundle_id]) {
            return [NSString stringWithFormat:@"%@/%@", base, uuid];
        }
    }
    return nil;
}

static NSString *slot_dir(const char *bundle_id, int slot) {
    return [NSString stringWithFormat:@"%s/%s", ACCOUNTS_BASE, bundle_id];
}

static NSString *slot_archive(const char *bundle_id, int slot) {
    return [NSString stringWithFormat:@"%s/%s/slot_%d.tar.gz",
            ACCOUNTS_BASE, bundle_id, slot];
}

static NSString *slot_meta(const char *bundle_id, int slot) {
    return [NSString stringWithFormat:@"%s/%s/slot_%d.json",
            ACCOUNTS_BASE, bundle_id, slot];
}

static void ensure_slot_dir(const char *bundle_id) {
    NSString *dir = slot_dir(bundle_id, 0);
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                      withIntermediateDirectories:YES attributes:nil error:nil];
}

void save_account(const char *bundle_id, int slot) {
    NSString *bid = [NSString stringWithUTF8String:bundle_id];
    NSString *src = get_container_path(bid);
    if (!src) return;

    ensure_slot_dir(bundle_id);
    NSString *archive = slot_archive(bundle_id, slot);

    NSString *cmd = [NSString stringWithFormat:
        @"tar -czf '%@' -C '%@' .", archive, src];
    c_shell_exec(cmd.UTF8String);

    // Write metadata
    NSDictionary *meta = @{
        @"bundleId":  bid,
        @"slot":      @(slot),
        @"savedAt":   @([[NSDate date] timeIntervalSince1970]),
        @"name":      [NSString stringWithFormat:@"Account %d", slot],
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:meta options:0 error:nil];
    [json writeToFile:slot_meta(bundle_id, slot) atomically:YES];
}

void switch_account(const char *bundle_id, int slot) {
    NSString *bid = [NSString stringWithUTF8String:bundle_id];
    NSString *archive = slot_archive(bundle_id, slot);

    if (![[NSFileManager defaultManager] fileExistsAtPath:archive]) return;

    c_app_kill(bundle_id);
    usleep(600000); // 600ms for app to fully die

    NSString *container = get_container_path(bid);
    if (!container) return;

    // Restore to temp dir first, then atomic rename to avoid corrupt state
    NSString *tmp = [container stringByAppendingString:@"__restore_tmp"];
    [[NSFileManager defaultManager] createDirectoryAtPath:tmp
                      withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *cmd = [NSString stringWithFormat:
        @"tar -xzf '%@' -C '%@'", archive, tmp];
    int rc = c_shell_exec(cmd.UTF8String);
    if (rc != 0) {
        [[NSFileManager defaultManager] removeItemAtPath:tmp error:nil];
        return;
    }

    // Atomic swap
    [[NSFileManager defaultManager] removeItemAtPath:container error:nil];
    [[NSFileManager defaultManager] moveItemAtPath:tmp toPath:container error:nil];

    clear_keychain_for_app(bundle_id);
    usleep(300000);
    c_app_run(bundle_id);
}

void delete_account(const char *bundle_id, int slot) {
    [[NSFileManager defaultManager] removeItemAtPath:slot_archive(bundle_id, slot) error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:slot_meta(bundle_id, slot)    error:nil];
}

void name_account(const char *bundle_id, int slot, const char *label) {
    NSString *meta_path = slot_meta(bundle_id, slot);
    NSData *data = [NSData dataWithContentsOfFile:meta_path];
    if (!data) return;
    NSMutableDictionary *d = [[NSJSONSerialization JSONObjectWithData:data
                               options:NSJSONReadingMutableContainers error:nil] mutableCopy];
    d[@"name"] = [NSString stringWithUTF8String:label];
    NSData *json = [NSJSONSerialization dataWithJSONObject:d options:0 error:nil];
    [json writeToFile:meta_path atomically:YES];
}

AccountSlot *list_accounts(const char *bundle_id, int *count) {
    *count = 0;
    NSString *dir = slot_dir(bundle_id, 0);
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
    if (!files) return NULL;

    NSMutableArray *slots = [NSMutableArray array];
    for (NSString *f in files) {
        if (![f hasSuffix:@".json"]) continue;
        NSString *path = [dir stringByAppendingPathComponent:f];
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (!data) continue;
        NSDictionary *d = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (d) [slots addObject:d];
    }

    AccountSlot *arr = calloc((size_t)slots.count, sizeof(AccountSlot));
    if (!arr) return NULL;

    for (NSUInteger i = 0; i < slots.count; i++) {
        NSDictionary *d = slots[i];
        arr[i].slot     = [d[@"slot"]    intValue];
        arr[i].saved_at = [d[@"savedAt"] doubleValue];
        NSString *name  = d[@"name"] ?: @"";
        strncpy(arr[i].name, name.UTF8String, sizeof(arr[i].name) - 1);
        (*count)++;
    }
    return arr;
}

void clear_keychain_for_app(const char *bundle_id) {
    NSString *bid = [NSString stringWithUTF8String:bundle_id];

    // Generic password entries
    NSDictionary *q = @{
        (__bridge id)kSecClass:       (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: bid,
    };
    SecItemDelete((__bridge CFDictionaryRef)q);

    // Internet password entries
    NSDictionary *q2 = @{
        (__bridge id)kSecClass:  (__bridge id)kSecClassInternetPassword,
        (__bridge id)kSecAttrServer: bid,
    };
    SecItemDelete((__bridge CFDictionaryRef)q2);
}
