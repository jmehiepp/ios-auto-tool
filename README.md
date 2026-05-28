# IOSAutoTool

Jailbreak automation daemon for iOS 14–17. Runs as root, exposes Lua scripting, Web IDE, and an MCP server so Claude (or any AI agent) can control the device directly.

---

## Prerequisites

- **macOS** host (Apple Silicon or Intel)
- **Xcode Command Line Tools**: `xcode-select --install`
- **Theos**: [theos.dev/docs/installation-macos](https://theos.dev/docs/installation-macos) — install to `~/theos`
- **ldid**: bundled with Theos, or `brew install ldid`
- **Jailbroken iOS 14.0+ device** with OpenSSH + root access

---

## Build

```bash
export THEOS=~/theos

./build.sh                # daemon .deb + spoof tweak .deb
./build.sh --with-monaco  # also bundle Monaco editor in Web IDE
./build.sh --clean        # clean rebuild from scratch
./build.sh --debug        # debug build (symbols, no optimization)
```

Output: `packages/iosautotool-daemon_*.deb` and `packages/iosautotool-spoof_*.deb`

The script handles dependencies automatically on first run:
- Downloads `mongoose.c` r7.13 from GitHub
- Cross-compiles LuaJIT 2.1 ARM64 using the iPhoneOS SDK
- Renames `spoof/modules/*.m` → `*.xm` for the Logos preprocessor

---

## Install to Device

```bash
scp packages/*.deb root@<device-ip>:/tmp/
ssh root@<device-ip> 'dpkg -i /tmp/iosautotool*.deb && killall -9 SpringBoard'
```

Verify daemon is running:
```bash
ssh root@<device-ip> 'launchctl list | grep iosautotool'
```

Logs:
```bash
ssh root@<device-ip> 'tail -f /var/log/iosautotool/stdout.log'
```

---

## Lua Scripting

Scripts live at `/Library/IOSAutoTool/scripts/` on the device.

```lua
-- example: tap a button, read the screen, type text
touch.tap(200, 400)
sleep(500)

local img = screen.capture()
local result = screen.ocr(img, "en-US")
log(result)

keyboard.type("hello world")
app.launch("com.example.app")
```

Run via Web IDE, MCP tool `lua-run`, or IPC client:
```bash
ssh root@<device-ip> '/Library/IOSAutoTool/iosautotool-daemon --run /path/to/script.lua'
```

---

## Web IDE

Open in a browser (same WiFi network):
```
http://<device-ip>:8888/
```

Features: file manager, script editor (Monaco if `--with-monaco` was used, otherwise textarea), live log viewer, run/stop controls.

---

## MCP Setup (Claude Desktop)

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "iosautotool": {
      "command": "ssh",
      "args": ["root@<device-ip>", "/Library/IOSAutoTool/mcp-bridge"]
    }
  }
}
```

Restart Claude Desktop. The following tools will appear: `lua-run`, `screenshot`, `ocr`, `tap`, `double-tap`, `long-press`, `swipe`, `type-text`, `press-key`, `find-color`, `find-image`, `get-color`, `shell-exec`, `read-file`, `write-file`, `http-request`, `app-run`, `app-kill`, `get-front-app`, `device-info`, `get-clipboard`, `set-clipboard`.

---

## Device Spoof (Paid Add-on)

Install `iosautotool-spoof_*.deb` separately. Requires a valid license key at `/Library/IOSAutoTool/license.key`.

Control via Lua:
```lua
spoof.enable("device_model", "iPhone15,3")
spoof.enable("gps", { lat = 21.0285, lon = 105.8542 })
spoof.enable("idfa", "00000000-0000-0000-0000-000000000000")
spoof.applyPreset("iphone14_pro_max")
spoof.reset()
```

---

## Troubleshooting

**`THEOS not set`** → `export THEOS=~/theos` before running `build.sh`.

**LuaJIT cross-compile fails on Apple Silicon:**
```bash
export MACOSX_DEPLOYMENT_TARGET=11.0
bash deps/build-luajit-arm64.sh
```

**Daemon not launching after install:**
```bash
ssh root@<device-ip> 'launchctl load /Library/LaunchDaemons/com.iosautotool.daemon.plist'
ssh root@<device-ip> 'tail -20 /var/log/iosautotool/stdout.log'
```

**Entitlements stripped (private API crashes):**
```bash
ldid -e /Library/IOSAutoTool/iosautotool-daemon
```
Should list all 6 entitlement keys. If empty, re-run `build.sh` with `$THEOS >= 2019`.

**MCP bridge hangs:** Ensure `socat` is installed on the device (`apt install socat` via Sileo/Cydia).

---

## License

For use on jailbroken devices only. The daemon runs as root with private-API entitlements — use responsibly. Not affiliated with Apple.
