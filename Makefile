THEOS_DEVICE_IP    ?= 192.168.1.100
THEOS_DEVICE_PORT  ?= 22

TARGET  := iphone:clang:16.5:15.0
ARCHS   := arm64

include $(THEOS)/makefiles/common.mk

TOOL_NAME = iosautotool-daemon

iosautotool-daemon_FILES = \
	daemon/main.m \
	daemon/runtime-paths.m \
	daemon/ipc-server.m \
	daemon/widget-service.m \
	daemon/script-runner.m \
	daemon/logger.m \
	daemon/scheduler.m \
	lua/lua-bridge.m \
	lua/bindings/bind-touch.m \
	lua/bindings/bind-screen.m \
	lua/bindings/bind-app.m \
	lua/bindings/bind-keyboard.m \
	lua/bindings/bind-system.m \
	engine/touch/touch-inject.m \
	engine/touch/gesture.m \
	engine/touch/recorder.m \
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
	webide/server/access-control.m \
	webide/server/api-handler.m \
	webide/server/claude-handler.m \
	deps/mongoose.c \
	mcp/mcp-server.m \
	mcp/stdio-bridge.m \
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
	spoof/device-profiles.m \
	lua/bindings/bind-spoof.m

iosautotool-daemon_CFLAGS = \
	-fobjc-arc \
	-Wno-unused-function \
	-Wno-unused-variable \
	-Wno-unused-but-set-variable \
	-Wno-deprecated-declarations \
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
	-framework Security \
	-framework QuartzCore \
	-framework MobileCoreServices \
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
	-framework NetworkExtension \
	-Wl,-undefined,dynamic_lookup

iosautotool-daemon_INSTALL_PATH = /Library/IOSAutoTool

iosautotool-daemon_CODESIGN_FLAGS = -Siosautotool-daemon.entitlements

include $(THEOS)/makefiles/tool.mk

TWEAK_NAME = iosautotool-spoof iosautotool-widget
iosautotool-spoof_FILES = spoof/spoof-config.m $(wildcard spoof/modules/*.xm)
iosautotool-spoof_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Ispoof
iosautotool-spoof_FRAMEWORKS = Foundation UIKit CoreTelephony CoreMotion CoreLocation WebKit AdSupport SystemConfiguration
iosautotool-spoof_LIBRARIES = substrate
iosautotool-widget_FILES = widget/widget-tweak.xm widget/floating-widget.m widget/widget-ipc.m
iosautotool-widget_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Iwidget
iosautotool-widget_FRAMEWORKS = Foundation UIKit QuartzCore
iosautotool-widget_LIBRARIES = substrate
ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
iosautotool-daemon_CFLAGS += -DIOSAT_ROOTLESS=1
iosautotool-spoof_CFLAGS += -DIOSAT_ROOTLESS=1
endif
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
iosautotool-daemon_CFLAGS += -DIOSAT_ROOTHIDE=1
iosautotool-spoof_CFLAGS += -DIOSAT_ROOTHIDE=1
iosautotool-widget_CFLAGS += -DIOSAT_ROOTHIDE=1
iosautotool-daemon_LDFLAGS += -lroothide
iosautotool-spoof_LDFLAGS += -lroothide
iosautotool-widget_LDFLAGS += -lroothide
endif
include $(THEOS)/makefiles/tweak.mk

after-install::
	install.exec "launchctl unload $(THEOS_PACKAGE_INSTALL_PREFIX)/Library/LaunchDaemons/com.iosautotool.daemon.plist 2>/dev/null; launchctl load $(THEOS_PACKAGE_INSTALL_PREFIX)/Library/LaunchDaemons/com.iosautotool.daemon.plist"
