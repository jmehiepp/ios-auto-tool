#!/usr/bin/env bash
# Run all Lua integration tests on a connected device via SSH + MCP bridge
# Usage: ./tests/run-tests-on-device.sh <device-ip>
set -euo pipefail

DEVICE_IP="${1:-}"
if [[ -z "$DEVICE_IP" ]]; then
    echo "Usage: $0 <device-ip>" >&2
    exit 1
fi

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
REMOTE_DIR="/Library/IOSAutoTool/tests"

echo "==> Syncing test files to $DEVICE_IP:$REMOTE_DIR"
ssh root@"$DEVICE_IP" "mkdir -p $REMOTE_DIR"
scp "$TESTS_DIR"/*.lua root@"$DEVICE_IP":"$REMOTE_DIR/"

echo "==> Running tests via MCP lua-run"
# Send run-all.lua content to daemon via curl (MCP HTTP endpoint)
SCRIPT=$(cat "$TESTS_DIR/run-all.lua")
PAYLOAD=$(printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"lua-run","arguments":{"code":"%s"}}}' \
    "$(echo "$SCRIPT" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read())[1:-1])')")

RESPONSE=$(ssh root@"$DEVICE_IP" \
    "curl -sf -X POST http://127.0.0.1:8765 -H 'Content-Type: application/json' -d '$PAYLOAD'")

echo "$RESPONSE" | python3 -c '
import sys, json
r = json.load(sys.stdin)
result = r.get("result", {})
for item in result.get("content", []):
    print(item.get("text",""))
' 2>/dev/null || echo "$RESPONSE"

echo "==> Done"
