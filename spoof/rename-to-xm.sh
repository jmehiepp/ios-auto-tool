#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
MODULES_DIR="$DIR/modules"

if [[ ! -d "$MODULES_DIR" ]]; then
    echo "ERROR: $MODULES_DIR not found" >&2
    exit 1
fi

count=0
for f in "$MODULES_DIR"/*.m; do
    [[ -f "$f" ]] || continue
    # Only rename files that actually contain Logos macros
    if grep -qE '%hook|%hookf|%ctor|%init' "$f"; then
        xm="${f%.m}.xm"
        if [[ "$f" == "$xm" ]]; then
            continue  # already .xm
        fi
        if git -C "$MODULES_DIR" rev-parse --git-dir &>/dev/null 2>&1; then
            git -C "$MODULES_DIR" mv "$(basename "$f")" "$(basename "$xm")"
        else
            mv "$f" "$xm"
        fi
        echo "  renamed: $(basename "$f") → $(basename "$xm")"
        ((count++)) || true
    fi
done

echo "Renamed $count file(s) (.m → .xm)"
