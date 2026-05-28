#!/usr/bin/env bash
set -euo pipefail

# ── args ─────────────────────────────────────────────────────────────
WITH_MONACO=0
DO_CLEAN=0
DEBUG_BUILD=0
for arg in "$@"; do
    case "$arg" in
        --with-monaco) WITH_MONACO=1 ;;
        --clean)       DO_CLEAN=1 ;;
        --debug)       DEBUG_BUILD=1 ;;
        *) echo "Unknown flag: $arg (valid: --with-monaco, --clean, --debug)" >&2; exit 1 ;;
    esac
done

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

# ── pre-flight ────────────────────────────────────────────────────────
fail() { echo "ERROR: $*" >&2; exit 1; }

echo "==> Pre-flight checks"

[[ "$(uname -s)" == "Darwin" ]] \
    || fail "macOS required (this is a cross-compile for iOS ARM64)"

[[ -n "${THEOS:-}" ]] \
    || fail "THEOS not set. Run: export THEOS=~/theos  (see https://theos.dev/docs/installation-macos)"

[[ -d "$THEOS" ]] \
    || fail "THEOS directory not found at '$THEOS'"

xcrun -f clang &>/dev/null \
    || fail "Xcode Command Line Tools not found. Run: xcode-select --install"

command -v ldid &>/dev/null || [[ -x "$THEOS/bin/ldid" ]] \
    || fail "ldid not found. Install via: brew install ldid  (or let Theos install it)"

echo "   OK: macOS, THEOS=$THEOS, Xcode CLT, ldid"

# ── step 1: deps ─────────────────────────────────────────────────────
echo "==> Step 1: Dependencies"

if head -1 deps/mongoose.c 2>/dev/null | grep -q '#error'; then
    echo "   Downloading mongoose..."
    bash deps/download-mongoose.sh
else
    echo "   mongoose OK"
fi

if [[ ! -f "deps/luajit/lib/libluajit-5.1.a" ]]; then
    echo "   Cross-compiling LuaJIT arm64..."
    bash deps/build-luajit-arm64.sh
else
    echo "   LuaJIT OK"
fi

# ── step 2: spoof rename ─────────────────────────────────────────────
echo "==> Step 2: Spoof module rename (.m → .xm)"
bash spoof/rename-to-xm.sh

# ── step 3: Monaco (optional) ────────────────────────────────────────
if [[ "$WITH_MONACO" -eq 1 ]]; then
    echo "==> Step 3: Monaco editor"
    bash webide/download-monaco.sh
else
    echo "==> Step 3: Monaco skipped (use --with-monaco to include)"
fi

# ── step 4: daemon build ─────────────────────────────────────────────
echo "==> Step 4: Daemon build"
MAKE_ARGS=()
[[ "$DEBUG_BUILD" -eq 1 ]] && MAKE_ARGS+=(DEBUG=1)

if [[ "$DO_CLEAN" -eq 1 ]]; then
    make clean "${MAKE_ARGS[@]}"
fi
make package "${MAKE_ARGS[@]}"

# ── step 5: spoof tweak build ─────────────────────────────────────────
echo "==> Step 5: Spoof tweak build"
if [[ "$DO_CLEAN" -eq 1 ]]; then
    make -f Makefile.spoof clean "${MAKE_ARGS[@]}"
fi
make -f Makefile.spoof package "${MAKE_ARGS[@]}"

# ── summary ───────────────────────────────────────────────────────────
echo ""
echo "==> Build complete. Packages:"
ls -1 packages/*.deb 2>/dev/null | sed 's/^/   /' \
    || echo "   (no .deb found — check Theos packages/ output dir)"
echo ""
echo "Install to device:"
echo "   scp packages/*.deb root@<device-ip>:/tmp/"
echo "   ssh root@<device-ip> 'dpkg -i /tmp/iosautotool*.deb && killall -9 SpringBoard'"
