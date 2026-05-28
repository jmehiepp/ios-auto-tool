#!/usr/bin/env bash
set -euo pipefail

MONGOOSE_VERSION="7.13"
BASE="https://raw.githubusercontent.com/cesanta/mongoose/${MONGOOSE_VERSION}"
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

echo "Downloading mongoose ${MONGOOSE_VERSION}..."
curl -fSL "${BASE}/mongoose.c" -o mongoose.c
curl -fSL "${BASE}/mongoose.h" -o mongoose.h

# Verify version matches
if ! grep -q "\"7\.13\"" mongoose.h; then
    echo "ERROR: Version mismatch in mongoose.h — expected 7.13" >&2
    exit 1
fi

echo "mongoose ${MONGOOSE_VERSION} ready (mongoose.c + mongoose.h)"
