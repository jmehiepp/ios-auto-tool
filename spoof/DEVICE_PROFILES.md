# Named Device profiles

`DeviceProfiles` saves this project's complete Device configuration under `iat_data_directory()/device-profiles`. It does not back up application containers, keychains, cloned apps or original iOSAutomate profile databases.

Objective-C API:

```objc
+ (NSArray<NSString *> *)namesWithError:(NSError **)error;
+ (BOOL)saveCurrentAs:(NSString *)name error:(NSError **)error;
+ (BOOL)applyNamed:(NSString *)name error:(NSError **)error;
+ (BOOL)deleteNamed:(NSString *)name error:(NSError **)error;
```

Listing returns a sorted array or nil with an error. The other operations return YES only on success and otherwise provide NSError. Missing profiles, malformed data, invalid schema, excessive size, unexpected file types/permissions and filesystem failures are errors. A corrupt regular file can be deleted without applying it.

Names match `[A-Za-z0-9][A-Za-z0-9_-]{0,63}`. The implementation adds `.plist`; user names cannot contain paths, extensions, whitespace, non-ASCII characters or traversal components. The storage directory is mode 0700 and owned by the effective root daemon. Files are mode 0600, regular, single-link files owned by that daemon. Production API calls require root; callers should access them through the daemon's authenticated API.

Storage uses directory-relative openat/fstatat/renameat/unlinkat calls, O_NOFOLLOW, a shared lock and exclusive temporary files. The final data directory and `device-profiles` directory cannot be symlinks. Standard trusted ancestor aliases such as `/var` are allowed; `iat_data_directory()` is a trusted process setting. Named file symlinks and hard links are rejected, including for save/delete. Listing reports a suspicious valid-name file as an error rather than silently hiding it. Unrelated names and temporary files are not listed.

Save validates the current immutable `SpoofConfig` snapshot, serializes a binary plist, enforces a maximum of **256 KiB**, writes/flushed data to a private temporary file and atomically renames it. Existing good profiles remain intact if validation/size/write fails. Rename provides atomic replacement; this does not claim a full power-loss transaction across profile, config and injection-filter files.

Apply uses bounded reads, parses an immutable property list, validates it through `SpoofConfig` and calls `setConfiguration:error:`. **The saved `enabled`, `selectedApps` and `modules` values are all restored.** Thus applying an enabled profile can enable its saved selection; user interfaces should label this action clearly. The existing config commit refreshes the injection filter and notification. A rejected profile does not mutate config. Config/filter failures retain the existing `SpoofConfig` error and its two-file commit semantics. App relaunch/navigation requirements remain as documented by the addon.

On macOS run `bash spoof/tests/run-profile-tests.sh` from `tool/`. Tests compile the real profile and config implementations and perform actual IO in an isolated temporary `IAT_DATA_DIR`, config path and filter path. A small test fixture supplies only the data-directory function; filesystem reads/writes and `SpoofConfig` are not mocked. The test-only root exemption is excluded from production builds. Coverage includes full-schema roundtrip/apply/filter refresh, safe names, schema/parse/read failures, byte bounds, file and directory symlinks, permissions, atomic preservation and deletion. Hook behavior and iPhone operation are not tested by this host suite.
