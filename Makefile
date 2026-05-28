THEOS_DEVICE_IP    ?= 192.168.1.100
THEOS_DEVICE_PORT  ?= 22

TARGET  := iphone:clang:latest:14.0
ARCHS   := arm64

include $(THEOS)/makefiles/common.mk

TOOL_NAME = iosautotool-daemon

iosautotool-daemon_FILES = \
	daemon/main.m \
	daemon/ipc-server.m \
	daemon/script-runner.m \
	daemon/logger.m \
	lua/lua-bridge.m \
	lua/bindings/bind-touch.m \
	lua/bindings/bind-screen.m \
	lua/bindings/bind-app.m \
	lua/bindings/bind-keyboard.m \
	lua/bindings/bind-system.m \
	engine/touch/touch-inject.m \
	engine/touch/gesture.m \
	engine/screen/screenshot.m \
	engine/screen/color-find.m \
	engine/screen/image-match.m \
	engine/screen/ocr.m \
	engine/app/app-control.m \
	engine/app/multi-account.m \
	engine/keyboard/text-input.m \
	engine/keyboard/key-press.m \
	engine/system/shell-exec.m \
	engine/system/file-ops.m \
	engine/system/http-client.m \
	webide/server/webide-server.m \
	webide/server/api-handler.m \
	deps/mongoose.c \
	mcp/mcp-server.m \
	mcp/mcp-tools-common.m \
	mcp/tools/tool-lua-run.m \
	mcp/tools/tool-screenshot.m \
	mcp/tools/tool-ocr.m \
	mcp/tools/tool-tap.m \
	mcp/tools/tool-keyboard.m \
	mcp/tools/tool-system.m \
	mcp/tools/tool-screen.m \
	mcp/tools/tool-app.m \
	mcp/tools/tool-device.m \
	spoof/spoof-config.m \
	lua/bindings/bind-spoof.m

iosautotool-daemon_CFLAGS = \
	-fobjc-arc \
	-Ideps/luajit/include \
	-Idaemon \
	-Ilua \
	-Iengine \
	-Ideps \
	-Iwebide/server \
	-Ispoof

iosautotool-daemon_LDFLAGS = \
	-Ldeps/luajit/lib \
	-lluajit-5.1 \
	-lz \
	-framework Foundation \
	-framework UIKit \
	-framework IOKit \
	-framework IOSurface \
	-framework CoreGraphics \
	-framework Accelerate \
	-framework Vision \
	-framework CoreLocation \
	-framework CoreMotion \
	-framework CoreTelephony \
	-framework WebKit \
	-framework AdSupport \
	-framework NetworkExtension

iosautotool-daemon_INSTALL_PATH = /Library/IOSAutoTool

iosautotool-daemon_CODESIGN_FLAGS = -Siosautotool-daemon.entitlements

include $(THEOS)/makefiles/tool.mk

before-package::
	mkdir -p layout/Library/IOSAutoTool/webide/frontend
	rsync -a --delete webide/frontend/ layout/Library/IOSAutoTool/webide/frontend/

after-install::
	install.exec "launchctl unload /Library/LaunchDaemons/com.iosautotool.daemon.plist 2>/dev/null; launchctl load /Library/LaunchDaemons/com.iosautotool.daemon.plist"
