# iOS Auto Tool — core 1.1 beta

Công cụ tự động hóa cho iPhone jailbreak, có Web IDE, Lua, điều khiển touch, screenshot/OCR, MJPEG và MCP. Nguồn Sileo: **https://jmehiepp.github.io/ios-auto-tool/**.

Bản này được triển khai từ mã nguồn IOSAutoTool và kết quả nghiên cứu giao diện/chức năng trong workspace. Không đóng gói lại binary, UI nhúng hoặc pseudocode của iOSAutomate.

## Phạm vi

- iOS 15+, arm64; hai gói Rootful `iphoneos-arm` và Rootless `iphoneos-arm64`.
- 59 tên hàm Lua được kiểm kê từ source: [lua-api.json](docs/lua-api.json).
- Web IDE tại cổng **8890**: file manager, editor hoạt động không cần CDN, run/stop, log WebSocket, app controls và màn hình MJPEG tối đa 4 khung/giây mỗi viewer.
- Xác thực API và WebSocket bằng mã ngẫu nhiên 256-bit tạo trên từng thiết bị; không có token chung trong `.deb`.
- Một script chạy tại một thời điểm. Stop dùng Lua debug hook; code Lua chạy ở chế độ interpreter để hook hoạt động. Lời gọi native đang block cần trả về trước khi Lua tiếp tục dừng.
- MCP loopback cổng 8765 và bridge stdio tích hợp.

Đây là **bản beta**. Build, auth trên host và payload có kiểm tra tự động; hành vi touch/capture/private API trên từng iPhone cần kiểm thử thực tế. RootHide/`iphoneos-arm64e`, widget và addon spoof chưa nằm trong các gói core phát hành đợt này. Các module addon cũ vẫn giữ trong source, không được xem là đã kiểm thử hay đã cài cùng core.

## Cài qua Sileo

1. Sileo → Sources → thêm `https://jmehiepp.github.io/ios-auto-tool/`.
2. Tìm **iOS Auto Tool**, cài gói đúng kiến trúc bootstrap.
3. Dùng terminal root trên iPhone hoặc SSH để lấy mã kết nối:

```sh
# Rootless
/var/jb/Library/IOSAutoTool/iosautotool-daemon --access-code

# Rootful
/Library/IOSAutoTool/iosautotool-daemon --access-code
```

4. Mở `http://IP-IPHONE:8890` và nhập mã. Có thể dùng SSH tunnel `ssh -L 8890:127.0.0.1:8890 root@IP-IPHONE`, rồi mở `http://127.0.0.1:8890`.

Daemon được launchd khởi động sau cài đặt. Dữ liệu script và mã kết nối ở `/var/mobile/Library/IOSAutoTool`; logs ở `/var/log/iosautotool`. Gỡ gói giữ lại dữ liệu cá nhân. Cổng 8890 được chọn để tránh trùng cổng 8888 của các công cụ khác.

## Lua

Các hàm là **global**, không gọi qua namespace `touch` hay `screen`:

```lua
log('Bắt đầu')
sleep(500)
tap(180, 300)
swipe(180, 500, 180, 200, 400)
typeText('Xin chào')
local text = ocr()
log(text or 'Không đọc được ảnh')
```

Touch và tọa độ Web IDE dùng logical points của màn hình. Các phương thức native phụ thuộc phiên bản iOS và quyền jailbreak. Tệp `hello.lua` được tạo khi thư mục script còn trống; ví dụ này chỉ ghi log và sleep.

## MCP

Bridge không cần Python/Node trên iPhone. Ví dụ cấu hình client stdio cho Rootless:

```json
{
  "mcpServers": {
    "ios-auto-tool": {
      "command": "ssh",
      "args": ["root@IP-IPHONE", "/var/jb/Library/IOSAutoTool/iosautotool-daemon", "--mcp-stdio"]
    }
  }
}
```

Rootful dùng đường dẫn `/Library/IOSAutoTool/iosautotool-daemon`. SSH cần key/login được thiết lập sẵn. `lua_run` trả trạng thái nhận chạy; kết quả hoàn tất nằm trong log. Tool handler chỉ thực thi một lần cho mỗi request. HTTP API và MCP yêu cầu bearer token hoặc cookie đã xác thực; client stdio đọc token cục bộ và gửi qua loopback.

Chat AI trong Web IDE là tùy chọn: chỉ hoạt động nếu môi trường daemon trên thiết bị có `ANTHROPIC_API_KEY`. Core không cần key đó. Không nhúng key vào source hoặc gói cài.

## Build và kiểm tra

Dùng macOS, Xcode, Node, Python 3 và [Theos](https://theos.dev/docs/installation-macos). Windows có thể gửi build tới workflow macOS của repository.

```sh
export THEOS=~/theos
bash build.sh
```

Script dùng SDK 16.5 trong Theos, LuaJIT revision cố định và Mongoose 7.14 vendored. Hai `.deb` nằm trong `packages/`, đi cùng `validation.json`.

Các bước thực hiện:

1. Biên dịch/chạy test auth bằng Foundation/Security trên macOS.
2. Chạy Lua VM thật để kiểm tra lỗi, tái sử dụng state, dừng vòng lặp và dừng sleep.
3. Kiểm tra cú pháp JavaScript.
4. Render đúng layout và launchd path cho từng scheme, biên dịch/ký Mach-O arm64.
5. Đọc lại `.deb`: metadata, kiến trúc, binary thật, entitlements, frontend/stdlib/licenses, launchd, script permissions, không lặp `/var/jb`, không mang token thiết bị.

`scripts/validate-packages.py packages` kiểm tra lại payload. `scripts/export-lua-api.py` tạo inventory globals. Các lượt CI và log build là bằng chứng biên dịch, không thay thế test iPhone.

## Nguồn Sileo

`repo/` chứa landing page, depiction và metadata. Sau khi build/validate:

```sh
mkdir -p repo/pool/main
cp packages/*.deb repo/pool/main/
bash scripts/update-repo.sh
```

Workflow publish đưa `repo/` lên nhánh `gh-pages`. Chỉ cập nhật nguồn khi kiểm tra `.deb` đạt. Dependency mới và code tương ứng được ghi ở [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md); license texts nằm trong `licenses/` và trong gói.
