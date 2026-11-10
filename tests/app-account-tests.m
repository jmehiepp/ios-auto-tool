#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import "../engine/app/app-control.h"
#import "../engine/app/multi-account.h"
#import "../mcp/mcp-tools.h"
#include <sys/stat.h>
#include <signal.h>
#include <errno.h>
#include <unistd.h>
#include <string.h>
#include <assert.h>
#include <stdbool.h>

// No real app process, device container or host keychain is contacted.
static NSString *fixture_root, *fixture_container;
static const char *fixture_id = "com.example.fixture";
static BOOL symbols_available = YES, workspace_available = NO, launch_accepted = YES;
static BOOL kill_denied = NO;
static pid_t fixture_pid = 0;
static int launch_calls, keychain_calls;
static OSStatus keychain_status = errSecSuccess;
static NSMutableArray *keychain_queries;
enum fault_kind { NoFault, RestoreLibraryMove, SnapshotCommitMove, StageCopy };
static enum fault_kind fault;

NSString *iat_data_directory(void) { return [fixture_root stringByAppendingPathComponent:@"data"]; }
NSString *iat_test_account_container(NSString *identifier) {
    return [identifier isEqualToString:@(fixture_id)] ? fixture_container : nil;
}
static uint32_t launch_stub(NSString *identifier, NSURL *url, NSDictionary *params, NSDictionary *options, BOOL suspended) {
    assert([identifier isEqualToString:@(fixture_id)]);
    assert(!url && params.count == 0 && options.count == 0 && !suspended);
    launch_calls++; return launch_accepted ? 0 : 13;
}
static CFArrayRef apps_stub(bool front, bool suspended) {
    (void)front; (void)suspended;
    return CFBridgingRetain(@[@(fixture_id), @"com.apple.springboard", @"bad"]);
}
static CFStringRef front_stub(void) { return CFRetain(CFSTR("com.example.fixture")); }
void *iat_test_app_symbol(const char *name) {
    if (!symbols_available) return NULL;
    if (!strcmp(name, "SBSLaunchApplicationWithIdentifierAndURLAndLaunchOptions")) return (void *)launch_stub;
    if (!strcmp(name, "SBSCopyApplicationDisplayIdentifiers")) return (void *)apps_stub;
    if (!strcmp(name, "SBSCopyFrontmostApplicationDisplayIdentifier")) return (void *)front_stub;
    return NULL;
}
@interface FixtureWorkspace : NSObject
+ (id)defaultWorkspace;
- (BOOL)openApplicationWithBundleID:(NSString *)identifier;
@end
@implementation FixtureWorkspace
+ (id)defaultWorkspace { return [self new]; }
- (BOOL)openApplicationWithBundleID:(NSString *)identifier {
    assert([identifier isEqualToString:@(fixture_id)]); launch_calls++; return launch_accepted;
}
@end
Class iat_test_app_workspace_class(void) { return workspace_available ? FixtureWorkspace.class : Nil; }
@interface FixtureSystemService : NSObject
+ (id)sharedService;
- (pid_t)pidForApplication:(NSString *)identifier;
@end
@implementation FixtureSystemService
+ (id)sharedService { return [self new]; }
- (pid_t)pidForApplication:(NSString *)identifier {
    return [identifier isEqualToString:@(fixture_id)] ? fixture_pid : 1;
}
@end
Class iat_test_app_system_service_class(void) { return symbols_available ? FixtureSystemService.class : Nil; }
int iat_test_app_kill(pid_t pid, int signal_number) {
    assert(pid > 1 && pid != getpid());
    if (kill_denied) { errno = EPERM; return -1; }
    if (signal_number == SIGKILL && pid == fixture_pid) { fixture_pid = 0; return 0; }
    errno = ESRCH; return -1;
}
static BOOL injected_error(NSError **error) {
    if (error) *error = [NSError errorWithDomain:@"FixtureFailure" code:99
        userInfo:@{NSLocalizedDescriptionKey:@"injected file operation failure"}];
    return NO;
}
BOOL iat_test_account_copy(NSString *source, NSString *destination, NSError **error) {
    if (fault == StageCopy && [destination.lastPathComponent isEqual:@"Library"]) {
        fault = NoFault; return injected_error(error);
    }
    return [NSFileManager.defaultManager copyItemAtPath:source toPath:destination error:error];
}
BOOL iat_test_account_move(NSString *source, NSString *destination, NSError **error) {
    if ((fault == RestoreLibraryMove && [source containsString:@"/incoming/"] && [destination.lastPathComponent isEqual:@"Library"]) ||
        (fault == SnapshotCommitMove && [source.lastPathComponent hasPrefix:@".stage-"] && [destination.lastPathComponent isEqual:@"slot_1"])) {
        fault = NoFault; return injected_error(error);
    }
    return [NSFileManager.defaultManager moveItemAtPath:source toPath:destination error:error];
}
OSStatus iat_test_account_keychain_delete(CFDictionaryRef query) {
    keychain_calls++; [keychain_queries addObject:[(__bridge NSDictionary *)query copy]];
    return keychain_status;
}
static void make_directory(NSString *path) {
    NSError *error = nil;
    assert([NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error]);
}
static void put(NSString *relative, NSString *text) {
    NSString *path = [fixture_container stringByAppendingPathComponent:relative];
    make_directory(path.stringByDeletingLastPathComponent);
    assert([text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]);
}
static NSString *get(NSString *relative) {
    return [NSString stringWithContentsOfFile:[fixture_container stringByAppendingPathComponent:relative] encoding:NSUTF8StringEncoding error:nil];
}
static void live_version(NSString *text) {
    put(@"Documents/marker.txt", text); put(@"Library/settings.txt", text); put(@"tmp/session.txt", text);
}
static void assert_live(NSString *text) {
    assert([get(@"Documents/marker.txt") isEqual:text]);
    assert([get(@"Library/settings.txt") isEqual:text]);
    assert([get(@"tmp/session.txt") isEqual:text]);
}
static NSString *snapshot(int slot) {
    return [[iat_data_directory() stringByAppendingPathComponent:@"accounts/com.example.fixture"]
        stringByAppendingPathComponent:[NSString stringWithFormat:@"slot_%d", slot]];
}

int main(void) { @autoreleasepool {
    assert(c_app_valid_bundle_id(fixture_id));
    for (NSString *bad in @[@"../escape", @"com..example", @"com.example';touch", @"/com.example", @"com.example/other", @"com.example_underscore", @"com.example-"])
        assert(!c_app_valid_bundle_id(bad.UTF8String));
    symbols_available = NO;
    assert(!c_app_run(fixture_id)); assert(strlen(c_app_last_error()));
    assert(c_get_front_app() == NULL);
    int count = 0; assert(c_get_running_apps(&count) == NULL && count == -1);
    assert([tool_app_run(@{@"bundle_id":@(fixture_id)})[@"isError"] boolValue]);
    assert([tool_get_front_app(@{})[@"isError"] boolValue]);
    symbols_available = YES;
    launch_accepted = NO; assert(!c_app_run(fixture_id));
    workspace_available = YES; assert(!c_app_run(fixture_id));
    launch_accepted = YES; assert(c_app_run(fixture_id)); workspace_available = NO;
    assert(c_app_run(fixture_id));
    assert(!c_app_kill("com.apple.springboard"));
    fixture_pid = getpid(); assert(!c_app_kill(fixture_id));
    fixture_pid = 424242; kill_denied = YES; assert(!c_app_kill(fixture_id));
    kill_denied = NO; assert(c_app_kill(fixture_id)); assert(fixture_pid == 0);
    fixture_pid = 424242;
    AppInfo *apps = c_get_running_apps(&count); assert(count == 1); free(apps);
    assert(c_app_kill_all()); assert(fixture_pid == 0);
    assert(!c_clear_switcher()); // Explicit unsupported status, never edit real prefs.
    assert(strcmp(c_get_front_app(), fixture_id) == 0);
    assert([tool_app_run(@{@"bundle_id":@123})[@"isError"] boolValue]);
    unichar nul_identifier[] = {'c','o','m','.','x',0,'x'};
    NSString *embedded_nul = [NSString stringWithCharacters:nul_identifier length:7];
    assert([tool_app_run(@{@"bundle_id":embedded_nul})[@"isError"] boolValue]);

    fixture_root = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"iat-account-fixture-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    fixture_container = [fixture_root stringByAppendingPathComponent:@"containers/fixture-UUID"];
    make_directory(fixture_container);
    NSString *metadata_path = [fixture_container stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"];
    assert([@{@"MCMMetadataIdentifier":@(fixture_id), @"sentinel":@"preserve"} writeToFile:metadata_path atomically:YES]);
    NSData *mcm_before = [NSData dataWithContentsOfFile:metadata_path];
    struct stat before, after;
    assert(lstat(fixture_container.fileSystemRepresentation, &before) == 0);
    put(@"container-sentinel.txt", @"preserve outside Documents/Library/tmp");
    live_version(@"saved-A"); keychain_queries = [NSMutableArray array];
    assert(!save_account("../escape", 1)); assert(!save_account(fixture_id, 0)); assert(!save_account(fixture_id, 10000));
    assert(save_account(fixture_id, 1));
    assert(![NSFileManager.defaultManager fileExistsAtPath:[snapshot(1) stringByAppendingPathComponent:@"data/.com.apple.mobile_container_manager.metadata.plist"]]);
    live_version(@"live-B");
    assert(switch_account(fixture_id, 1)); assert_live(@"saved-A");
    assert([[NSData dataWithContentsOfFile:metadata_path] isEqual:mcm_before]);
    assert(lstat(fixture_container.fileSystemRepresentation, &after) == 0);
    assert(before.st_ino == after.st_ino && before.st_uid == after.st_uid && before.st_gid == after.st_gid);
    assert([get(@"container-sentinel.txt") hasPrefix:@"preserve"]);
    assert(keychain_calls == 0);

    live_version(@"live-B"); fault = RestoreLibraryMove;
    assert(!switch_account(fixture_id, 1)); assert_live(@"live-B");
    assert(strstr(account_last_error(), "original app data restored"));
    assert([[NSData dataWithContentsOfFile:metadata_path] isEqual:mcm_before]);
    fault = StageCopy; assert(!switch_account(fixture_id, 1)); assert_live(@"live-B");
    fault = SnapshotCommitMove; assert(!save_account(fixture_id, 1));
    assert(switch_account(fixture_id, 1)); assert_live(@"saved-A");
    live_version(@"live-B");
    NSString *link = [snapshot(1) stringByAppendingPathComponent:@"data/Documents/unsafe-link"];
    assert([NSFileManager.defaultManager createSymbolicLinkAtPath:link withDestinationPath:fixture_root error:nil]);
    assert(!switch_account(fixture_id, 1)); assert_live(@"live-B");
    assert([NSFileManager.defaultManager removeItemAtPath:link error:nil]);
    assert([NSFileManager.defaultManager createSymbolicLinkAtPath:snapshot(2) withDestinationPath:snapshot(1) error:nil]);
    assert(!switch_account(fixture_id, 2)); assert_live(@"live-B");
    assert([NSFileManager.defaultManager removeItemAtPath:snapshot(2) error:nil]);
    assert(name_account(fixture_id, 1, "Fixture account"));
    assert(!name_account(fixture_id, 1, "bad\nlabel"));
    AccountSlot *slots = list_accounts(fixture_id, &count);
    assert(slots && count == 1 && slots[0].slot == 1 && !strcmp(slots[0].name, "Fixture account")); free(slots);
    assert(list_accounts("../escape", &count) == NULL && count == -1);
    assert(keychain_calls == 0);
    keychain_status = errSecAuthFailed; assert(!clear_keychain_for_app(fixture_id));
    assert(keychain_calls == 2);
    assert([keychain_queries[0][(__bridge id)kSecAttrService] isEqual:@(fixture_id)]);
    assert([keychain_queries[1][(__bridge id)kSecAttrServer] isEqual:@(fixture_id)]);
    keychain_status = errSecItemNotFound; assert(clear_keychain_for_app(fixture_id));
    assert(delete_account(fixture_id, 1));
    slots = list_accounts(fixture_id, &count); assert(slots && count == 0); free(slots);
    assert([NSFileManager.defaultManager removeItemAtPath:fixture_root error:nil]);
    puts("App control and account snapshot/rollback tests passed (fixture data only)");
    return 0;
} }
