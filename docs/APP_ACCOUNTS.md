# App control and saved account data

The app APIs now return real status. Lua app/account commands return `true` on success and raise a Lua error with the underlying reason on failure. MCP app handlers return `isError:true` for missing APIs, rejected launches, invalid arguments and process errors. Existing C function names remain; commands that previously returned `void` now return `BOOL`. `c_app_last_error()` and `account_last_error()` are thread-local and must be copied before another operation on that thread.

## Guarded app operations

Private frameworks are loaded with `dlopen`; exported launch/list/front-app functions are resolved with `dlsym` and checked before use. Launch prefers `LSApplicationWorkspace` after selector checks. Its `BOOL` means the launch request was accepted, not proof the app became foreground. The fallback uses the five-argument `SBSLaunchApplicationWithIdentifierAndURLAndLaunchOptions` declaration. PID lookup uses guarded `FBSSystemService.sharedService/pidForApplication:` instead of guessing a legacy `SBSProcessIDForDisplayIdentifier` ABI.

These declarations were checked against the upstream [Frida SpringBoard header](https://github.com/frida/frida-core/blob/main/src/darwin/springboard.h) and [framework-loading implementation](https://github.com/frida/frida-core/blob/main/src/darwin/springboard.m). They are private APIs; these sources do not establish support on every iOS build or supply missing entitlements. This implementation does not patch bootstrap/XPC lookup or bypass platform authorization. Absent/denied APIs return an error.

App termination refuses PID1, the daemon itself and SpringBoard. A successful termination request is followed by exit checks for up to three seconds. An app already stopped counts as success. Kill-all filters the returned identifiers to live app PIDs and stops at the first failure; it cannot undo apps already terminated. `getRunningApps()` returns the bundle identifier as its fallback display name. Foreground returns an empty string when there is no foreground identifier; unavailable APIs return an error.

`clearSwitcher()` currently returns an explicit unsupported error from the daemon. It does not mutate SpringBoard preferences or claim that killing processes clears the recents UI. This remains a functional gap pending a verified SpringBoard-side implementation.

## Snapshot format and validation

Snapshots are directories under `iat_data_directory()/accounts/<bundle-id>/slot_<n>`, normally `/var/mobile/Library/IOSAutoTool/accounts`. Runtime storage is honored; there is no hardcoded alternative account root. Storage directories must belong to the daemon and be private. Production account operations require the root daemon; restored app content is assigned UID501/GID501. Container root ownership is preserved.

Bundle identifiers must contain at least two nonempty ASCII alphanumeric/hyphen components separated by dots, with alphanumeric component ends, maximum255 bytes. Slots are integers1...9999. Labels are nonempty UTF-8 strings of at most127 bytes without control characters. Lua/MCP reject embedded NUL instead of silently truncating the identifier.

A snapshot contains `metadata.json` (format version1, bundle identifier, slot, timestamp, label and present-directory list) and `data/` with only `Documents`, `Library` and `tmp`. The source container is resolved through a guarded MobileContainerManager selector or matched metadata scan; its MCM identifier must match the requested bundle. Production paths are restricted to the app data-container location. Symlinks, special files, malformed metadata and unexpected snapshot data are rejected. The previous tar archives are not automatically imported or extracted by this version.

## Save and restore behavior

`saveAccount(bundle, slot)` resolves the container and confirms the app is stopped before copying. It stages actual `NSFileManager` copies of the three allowed data directories, writes metadata, then commits the snapshot by directory rename. When replacing a slot, the old snapshot is moved aside first and restored if the new commit fails. No shell command, interpolated tar invocation or app-container UUID copy is used. Save leaves the app stopped.

`switchAccount(bundle, slot)` validates the snapshot before stopping the app. It copies the saved data into a private workspace **inside the existing container**, updates restored content ownership, then renames individual data directories. Original directories move into a rollback area. If a copy fails, live data is untouched. If a later rename fails, the implementation restores the directories already changed. The container directory itself, its inode/UUID, owner, MCM metadata and unrelated root files are preserved.

The app is relaunched only after all three data directories have been restored successfully. If launch is rejected, the operation returns an error explicitly stating that the data was restored but launch failed; it does not swap data again after a potentially accepted launch. If rollback itself fails, the workspace containing recoverable original data is retained and its path is included in the error. No automatic cleanup deletes that retained recovery data.

This is rollback for reported file-operation failures, not a filesystem-wide atomic transaction across all three directories or a crash/power-loss recovery journal. Concurrent external launches/writers and background agents can still affect consistency. Shared app-group containers, app bundles, Keychain, iCloud/server state and other container-root entries are outside the snapshot. A restored data directory therefore does not guarantee a restored authenticated account session. Check this behavior with disposable fixture data on each supported jailbreak before using personal app data.

## Limited explicit Keychain operation

Neither save nor switch calls `clearKeychain`. The explicit `clearKeychain(bundle)` API issues two narrow queries: generic-password `service == bundle`, and internet-password `server == bundle`. They affect only items accessible to the daemon's current Keychain entitlements/access groups. This does not identify every item belonging to that application and is not an all-device clear or Keychain backup. The operation returns actual Security status errors; `errSecItemNotFound` is an idempotent success. A failure can follow partial deletion by the first query and is reported as such through its two status codes.

## Host fixture tests

On macOS, from `tool`:

```sh
mkdir -p .build-evidence
xcrun clang -fobjc-arc -fblocks \
  -DIAT_APP_CONTROL_TESTING -DIAT_ACCOUNT_TESTING \
  tests/app-account-tests.m engine/app/app-control.m engine/app/multi-account.m \
  mcp/mcp-tools-common.m mcp/tools/tool-app.m \
  -framework Foundation -framework Security \
  -o .build-evidence/app-account-tests
.build-evidence/app-account-tests
```

The tests compile the real app/account implementation. Framework symbols/classes, process termination, the container resolver and Keychain deletion are compile-time stubs. Filesystem copies, metadata writes, directory moves and rollback happen for real in a new temporary fixture; no host application, personal container or host Keychain is touched. Fault injection fails a restore rename after Documents has already been replaced, and fails a replacement snapshot commit. Tests assert that original live data/previous snapshot recover, MCM metadata/root inode/owner remain unchanged, symlinks/invalid input are rejected, and save/switch never invoke Keychain deletion. MCP error propagation and private-API absence/rejection are exercised. Host ownership tests use the current fixture user/group; UID501 restoration and UIKit/device private APIs still require device tests.

The Windows authoring session cannot run this macOS executable. CI must supply the actual compile/test result; source review alone is not a pass. Lua wrapper propagation has been updated in source, but this fixture executable does not embed Lua. Device tests must also verify API entitlement errors, actual app shutdown, MCM resolution and restored permissions with a disposable app before testing real data.
