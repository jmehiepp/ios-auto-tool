# Device configuration addon

This project's addon has no license/key server. It does not read or imitate an iOSAutomate key. `spoof_license_verify()` is retained only as a compatibility symbol and returns YES; activation is controlled by local configuration.

The stored schema is:

```json
{"enabled":false,"selectedApps":[],"modules":{}}
```

Each module entry is `{ "enabled": true, "value": ... }`. Values are type/range checked. Unknown module names and malformed configuration are rejected. A missing/unreadable/invalid file restores the disabled defaults. `getAll`, `getString/getNumber/getDict`, `isEnabled`, `setEnabled`, `setValue`, `reset`, `reload` remain available. Typed getters and `isEnabled` describe a stored module; `shouldApplyInCurrentProcess` is the separate effective process gate. `setValue` enables that module, but never enables the master switch or selects applications.

`setConfiguration:error:` is the preferred write API: validates a deep immutable snapshot, requires root in production, writes the injection filter atomically, commits the plist atomically, and posts a Darwin notification. It returns a real error on failure. Legacy void setters retain their signatures; callers needing error feedback should use the full configuration method. `setMasterEnabled:`, `setSelectedApps:`, `selectedApps` are available for integration. Per-module native mutations are serialized within the process. A whole-config API replacement is deliberately a replacement, so clients should submit their latest revision.

Paths and injection lifecycle:

| Build | Config | Substrate filter |
|---|---|---|
| Rootful | `/var/mobile/Library/Preferences/com.iosautotool.device.plist` | `/Library/MobileSubstrate/DynamicLibraries/iosautotool-spoof.plist` |
| Rootless (`IOSAT_ROOTLESS` or `ROOTLESS`) | same shared mobile preferences path | `/var/jb/Library/MobileSubstrate/DynamicLibraries/iosautotool-spoof.plist` |
| RootHide (`IOSAT_ROOTHIDE`) | `jbroot(@"/var/mobile/Library/Preferences/com.iosautotool.device.plist")` | `jbroot(@"/Library/MobileSubstrate/DynamicLibraries/iosautotool-spoof.plist")` |

RootHide uses the host build's `<roothide.h>`; its runtime/packaging and arm64e ABI must be verified by that build. `SPOOF_CONFIG_PATH` and `SPOOF_FILTER_PATH` support compile-time overrides for isolated host tests. No environment-controlled path is used in production.

Filter shape is `{Filter:{Bundles: enabled ? selectedApps : []}}`, with no UIKit/global class filter. Every Logos source has an explicit group and initializes it only if master is enabled and the main `.app` bundle is selected. SpringBoard, protected daemon IDs, WebKit service processes and extensions are excluded. A daemon executable is not an eligible `.app` bundle. Configuration changes use a Darwin notification and a retained one-second fallback reload timer, including atomic replacement/removal. Selecting a new app/enabling a previously uninitialized group requires terminating/relaunching that app. Native reads stop substituting values after master/module/selection is disabled; existing JavaScript documents and a previously set WKWebView custom user-agent require navigation/reload. No process is killed by this addon.

Filter and configuration are separate files: if config commit fails after filter write, the new filter may exist while the prior config remains. The caller receives failure; constructor/runtime gates continue to use the prior committed config. No two-file atomic transaction is claimed. Current-process serial mutation plus a cross-process file lock protects writer commits; external tools replacing a whole config may still overwrite a newer revision.

## Implemented surfaces and limits

The original reverse report established a Remote configuration loader and feature flags, **not complete working Device hooks**. See `rea/reports/REMOTE_NATIVE.md`, especially its Device boundary. These hooks are newly implemented source in this project, not recovered original source or proof of behavioral equivalence.

| Module keys | Implemented surface | Limits |
|---|---|---|
| `device_model`, `device_family`, `ios_version`, `device_name` | `uname.machine`, UIDevice family/model, systemVersion/name | No hardware alteration; no sysctl/MobileGestalt/serial/IMEI hook. Hardware identifier and generic device family have distinct meanings. |
| `idfa`, `idfv` | UUID accessors | Invalid UUIDs rejected. IDFA preserves the original zero/unavailable result; tracking consent/authorization is never changed. |
| `carrier_name`, `mcc`, `mnc`, `iso_country`, `wifi` | CTCarrier accessors, available CaptiveNetwork dictionary | No SIM/baseband change, IP/VPN/routing changes, or recovery of permission-denied Wi-Fi data. |
| `gps`, `gps_accuracy` | CLLocation coordinate/altitude/horizontalAccuracy accessors | CLLocationManager delivery/permissions remain intact; no location generation when the system delivers none. |
| `screen_resolution`, `screen_scale` | main UIScreen bounds/nativeBounds/scale/nativeScale metadata | No physical resolution change; applications may lay out differently. External screens preserve original metadata. |
| `battery_level`, `battery_state`, `proximity`, `accelerometer`, `gyroscope` | typed UIDevice/sample-object accessors | No sensor driver change, invented availability or permissions. Read-only CoreMotion data is not mutated using private KVC. |
| `locale`, `timezone` | NSLocale and NSTimeZone queries | No OS setting change; cached/app-specific formatters may retain their old settings. |
| `user_agent` | WKWebView custom user-agent at construction/loadRequest/loadHTMLString | No global NSURLSession/other browser engine rewriting. Original custom value is restored on next intercepted navigation after disable. |
| `canvas`, `webgl_vendor`, `webgl_renderer` | owned WKUserScript for canvas getImageData and WebGL getParameter | One owned script/controller; preserves app scripts, JSON-quotes values. No claim to cover toDataURL, OffscreenCanvas, WebRTC, GPU or every fingerprint surface. Existing pages need reload. |
| `app_list` | filter LSApplicationWorkspace allApplications/allInstalledApplications results inside selected app | No uninstall, global application-list change or jailbreak hiding policy. Missing selectors preserve entries. |

Value shapes: `screen_resolution={w,h,scale?}`; `gps={lat,lon,altitude?,accuracy?}`; `wifi={ssid?,bssid?}`; `accelerometer/gyroscope={x,y,z}`; `app_list={hide:[bundleIDs]}`. Battery level is `-1..1`, battery state an integer `0..3`, scale `0.25..8`. UUID strings use the canonical NSUUID parser. `canvas` may be a switch-only enabled entry; a stored false value suppresses the noise script.

Lua retains `spoof.enable/disable/reset/reload/isEnabled/applyPreset` and adds `getAll`, `setMasterEnabled`, `setSelectedApps`, `selectedApps`. Nested dictionaries/arrays and booleans are preserved, sparse/mixed/cyclic or excessively deep tables are rejected. A preset only stages module values. The master and selected-app consent remain separate.

## Validation

Beta5 adds app-scoped `sysctlbyname` reads for `hw.machine` and `kern.osproductversion`, the `CTL_HW/HW_MACHINE` MIB, and selected readable MobileGestalt keys (ProductType/ProductVersion/DeviceName/UserAssignedDeviceName/DeviceClass). These map to the existing typed modules and retain the master, module and application gates. No serial/UDID or system-daemon spoofing is claimed. The sysctl replacement honors size queries, NUL termination and short-buffer failure; writes and unknown keys pass to the original function.

Lua also exposes `spoof.listProfiles/saveProfile/applyProfile/deleteProfile/renameProfile`. Rename uses an exclusive operation and rejects an existing destination. The HTTP profile route accepts `action:"rename", name, newName`. These are project profiles rather than the original product's ResetDevice/clone workflows. See [device testing](../docs/DEVICE_TESTING.md) for actual iPhone accessor/identity observations and limits.

On macOS run `bash spoof/tests/run-config-tests.sh` from `tool/`. It compiles only the Foundation config implementation, uses isolated temporary paths and a test-only root-check exemption, and verifies defaults, validation, protected process exclusions, filter/config persistence, immutable snapshots, concurrent module updates, and write-failure behavior. This is not a Logos/UIKit hook test. Theos/Logos compilation and an explicitly selected on-device probe app are required to verify ABI, injection, accessor results, callbacks and WebKit behavior. No on-device success is claimed before those checks.
