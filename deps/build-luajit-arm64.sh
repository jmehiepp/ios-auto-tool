#!/usr/bin/env bash
set -euo pipefail

LUAJIT_REPO="${LUAJIT_REPO:-https://luajit.org/git/luajit.git}"
LUAJIT_BRANCH="v2.1"
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

# macOS only
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "ERROR: This script must run on macOS (requires Xcode + iPhoneOS SDK)" >&2
    exit 1
fi

# Xcode CLT check
if ! xcrun -f clang &>/dev/null; then
    echo "ERROR: Xcode Command Line Tools not found." >&2
    echo "  Run: xcode-select --install" >&2
    exit 1
fi

# iPhoneOS SDK
ISDKP="$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)"
if [[ -z "$ISDKP" ]]; then
    echo "ERROR: iPhoneOS SDK not found. Install Xcode from the App Store." >&2
    exit 1
fi
echo "Using SDK: $ISDKP"

# Clone or update LuaJIT
if [[ ! -d "luajit-src/.git" ]]; then
    echo "Cloning LuaJIT ${LUAJIT_BRANCH}..."
    git clone --depth 1 -b "$LUAJIT_BRANCH" "$LUAJIT_REPO" luajit-src
else
    echo "Updating LuaJIT..."
    git -C luajit-src fetch origin
    git -C luajit-src checkout "$LUAJIT_BRANCH"
    git -C luajit-src pull --ff-only
fi

# Cross-compile for iOS arm64
ICC="$(xcrun --sdk iphoneos --find clang)"
ISDKF="-arch arm64 -isysroot $ISDKP -mios-version-min=14.0"

cd luajit-src
make clean
make HOST_CC="clang -m64" \
     CROSS="$(dirname "$ICC")/" \
     TARGET_FLAGS="$ISDKF" \
     TARGET_SYS=iOS \
     TARGET=arm64 \
     BUILDMODE=static \
     -j"$(sysctl -n hw.ncpu)"
cd ..

# Stage outputs
mkdir -p luajit/lib luajit/include
cp luajit-src/src/libluajit.a luajit/lib/libluajit-5.1.a
cp luajit-src/src/lua.h luajit-src/src/lualib.h luajit-src/src/lauxlib.h \
   luajit-src/src/luaconf.h luajit-src/src/luajit.h luajit/include/

# Sanity checks
echo "Verifying output..."
file luajit/lib/libluajit-5.1.a
lipo -info luajit/lib/libluajit-5.1.a | grep -q arm64 \
    || { echo "ERROR: arm64 slice not found in libluajit-5.1.a" >&2; exit 1; }

echo "LuaJIT 2.1 arm64 static lib ready at deps/luajit/"
