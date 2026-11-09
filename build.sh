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
xcrun clang -fobjc-arc -fblocks tests/http-auth-tests.m daemon/runtime-paths.m webide/server/access-control.m deps/mongoose.c -framework Foundation -framework Security -o .build-evidence/http-auth-tests
.build-evidence/http-auth-tests
xcrun clang -fobjc-arc -fblocks -Ideps/luajit/include tests/lua-runtime-tests.m lua/lua-bridge.m daemon/runtime-paths.m deps/luajit/lib/libluajit-host.a -framework Foundation -framework Security -o .build-evidence/lua-runtime-tests
.build-evidence/lua-runtime-tests
for file in webide/frontend/*.js; do node --check "$file"; done
mkdir -p packages
python3 -c "from pathlib import Path; [p.unlink() for p in Path('packages').glob('*.deb')]"
for scheme in rootful rootless; do
    echo "Building core daemon: $scheme"
    python3 scripts/render-layout.py --scheme "$scheme"
    package_scheme="$scheme"
    [[ "$scheme" == rootful ]] && package_scheme=''
    make clean THEOS_PACKAGE_SCHEME="$package_scheme"
    make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME="$package_scheme"
done
python3 scripts/validate-packages.py packages --rename
echo 'Core daemon packages are ready. Device smoke tests are still required.'
ls -lh packages/*.deb
