#!/usr/bin/env bash
set -euo pipefail

MONACO_VERSION="${MONACO_VERSION:-0.46.0}"
URL="https://registry.npmjs.org/monaco-editor/-/monaco-editor-${MONACO_VERSION}.tgz"
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

echo "Downloading Monaco Editor ${MONACO_VERSION}..."
curl -fSL "$URL" -o /tmp/monaco.tgz

mkdir -p frontend/monaco
tar -xzf /tmp/monaco.tgz -C frontend/monaco --strip-components=2 package/min
rm /tmp/monaco.tgz

if [[ ! -f "frontend/monaco/vs/loader.js" ]]; then
    echo "ERROR: Extract failed — frontend/monaco/vs/loader.js not found" >&2
    exit 1
fi

echo "Monaco ${MONACO_VERSION} ready at webide/frontend/monaco/"
