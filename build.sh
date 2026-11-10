#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ "$(uname -s)" != Darwin ]]; then echo 'Build on macOS with Xcode and Theos.' >&2; exit 1; fi
: "${THEOS:?Set THEOS to your Theos installation}"
if ! command -v dpkg-deb >/dev/null; then brew install dpkg; fi
if ! command -v ldid >/dev/null; then brew install ldid; fi
if [[ ! -f deps/luajit/lib/libluajit-5.1.a ]]; then bash deps/build-luajit-arm64.sh; fi
if [[ ! -f deps/luajit/lib/libluajit-host.a ]] || ! lipo -info deps/luajit/lib/libluajit-host.a | grep -q "$(uname -m)"; then bash deps/build-luajit-arm64.sh; fi
if ! grep -q 'MG_VERSION "7.14"' deps/mongoose.h; then bash deps/download-mongoose.sh; fi
mkdir -p .build-evidence
mkdir -p .build-evidence/lua/stdlib
cp lua/stdlib/*.lua .build-evidence/lua/stdlib/
xcrun clang -fobjc-arc -fblocks tests/http-auth-tests.m daemon/runtime-paths.m webide/server/access-control.m deps/mongoose.c -framework Foundation -framework Security -o .build-evidence/http-auth-tests
.build-evidence/http-auth-tests
xcrun clang -fobjc-arc -fblocks -Ideps/luajit/include tests/lua-runtime-tests.m lua/lua-bridge.m daemon/runtime-paths.m deps/luajit/lib/libluajit-host.a -framework Foundation -framework Security -o .build-evidence/lua-runtime-tests
.build-evidence/lua-runtime-tests
xcrun clang -fobjc-arc -fblocks -Ideps/luajit/include tests/data-bindings-tests.m lua/bindings/bind-data.m deps/luajit/lib/libluajit-host.a -framework Foundation -o .build-evidence/data-bindings-tests
.build-evidence/data-bindings-tests
bash spoof/tests/run-config-tests.sh
bash spoof/tests/run-profile-tests.sh
xcrun clang -fobjc-arc -fblocks tests/web-script-preservation-tests.m spoof/web-script-update.m -framework Foundation -framework WebKit -o .build-evidence/web-script-preservation-tests
.build-evidence/web-script-preservation-tests
xcrun clang -fobjc-arc -fblocks -DIAT_APP_CONTROL_TESTING -DIAT_ACCOUNT_TESTING tests/app-account-tests.m engine/app/app-control.m engine/app/multi-account.m mcp/mcp-tools-common.m mcp/tools/tool-app.m -framework Foundation -framework Security -o .build-evidence/app-account-tests
.build-evidence/app-account-tests
xcrun clang -std=c11 -Wall -Wextra -Werror tests/widget-transport-tests.c -o .build-evidence/widget-transport-tests
.build-evidence/widget-transport-tests
xcrun clang -std=c11 -Wall -Wextra -Werror tests/widget-late-wakeup-tests.c -o .build-evidence/widget-late-wakeup-tests
.build-evidence/widget-late-wakeup-tests
xcrun clang -fobjc-arc -fblocks tests/scheduler-tests.m daemon/runtime-paths.m -framework Foundation -framework Security -o .build-evidence/scheduler-tests
.build-evidence/scheduler-tests
for file in webide/frontend/*.js; do node --check "$file"; done
node tests/admin-device-ui-tests.cjs
mkdir -p packages
python3 -c "from pathlib import Path; [p.unlink() for p in Path('packages').glob('*.deb')]"
python3 scripts/prepare-logos.py
for scheme in rootful rootless roothide; do
    echo "Building automation ecosystem: $scheme"
    if [[ "$scheme" == roothide ]]; then
        # Keep the ordinary cached Theos intact; pin the RootHide toolchain fork.
        base_theos="$THEOS"
        task_theos="$PWD/.build-theos-roothide"
        if [[ ! -f "$task_theos/makefiles/common.mk" ]]; then
            git init "$task_theos"
            git -C "$task_theos" remote add origin https://github.com/roothide/theos.git
            git -C "$task_theos" fetch --depth 1 origin 958fea4f779943505b15b93c88bb4db8d97b346d
            git -C "$task_theos" checkout --detach FETCH_HEAD
            git -C "$task_theos" submodule update --init --recursive --depth 1
            mkdir -p "$task_theos/sdks"
            for sdk in "$base_theos"/sdks/*.sdk; do ln -s "$sdk" "$task_theos/sdks/$(basename "$sdk")"; done
        fi
        export THEOS="$task_theos"
    fi
    python3 scripts/render-layout.py --scheme "$scheme"
    package_scheme="$scheme"
    [[ "$scheme" == rootful ]] && package_scheme=''
    make clean THEOS_PACKAGE_SCHEME="$package_scheme"
    make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME="$package_scheme"
done
python3 scripts/validate-packages.py packages --rename
echo 'Automation ecosystem packages are ready. Device smoke tests are still required.'
ls -lh packages/*.deb
