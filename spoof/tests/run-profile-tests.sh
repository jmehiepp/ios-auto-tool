#!/usr/bin/env bash
set -euo pipefail
task_source_dir="$(cd "$(dirname "$0")/.." && pwd)"
task_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/iosautotool-device-test.XXXXXX")"
trap 'rm -rf -- "$task_test_dir"' EXIT
export IAT_DATA_DIR="$task_test_dir/data"
xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Werror \
  -framework Foundation -framework CoreFoundation \
  -DIOSAT_DEVICE_TESTING=1 \
  "-DSPOOF_CONFIG_PATH=@\"$task_test_dir/config/device.plist\"" \
  "-DSPOOF_FILTER_PATH=@\"$task_test_dir/filter/iosautotool-spoof.plist\"" \
  "$task_source_dir/spoof-config.m" "$task_source_dir/device-profiles.m" \
  "$task_source_dir/tests/profile-tests.m" -o "$task_test_dir/profile-tests"
"$task_test_dir/profile-tests"
