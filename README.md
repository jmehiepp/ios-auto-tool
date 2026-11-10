# iOS Auto Tool — ecosystem 1.2 beta

Công cụ tự động hóa iPhone jailbreak: Web IDE, Lua, touch, screenshot/OCR, MJPEG, MCP, widget chạy script và cấu hình theo từng ứng dụng. Nguồn Sileo: **https://jmehiepp.github.io/ios-auto-tool/**.

Đây là triển khai từ mã nguồn IOSAutoTool của dự án và kết quả nghiên cứu chức năng trong workspace. Gói cài không chứa binary, UI nhúng hoặc pseudocode của iOSAutomate. Bản beta chưa được xác nhận tương đương toàn bộ bản gốc; xem [ma trận phạm vi](docs/FEATURE_PARITY.md).

## Gói cài và kiểm thử

Một gói `com.iosautotool` chứa daemon, widget SpringBoard và addon cấu hình. Ba biến thể dành cho iOS 15+, mã máy arm64:

| Bootstrap | Architecture trong Sileo | Đường dẫn chương trình |
|---|---|---|
| Rootful | iphoneos-arm | /Library/IOSAutoTool/iosautotool-daemon |
| Rootless | iphoneos-arm64 | /var/jb/Library/IOSAutoTool/iosautotool-daemon |
| RootHide | iphoneos-arm64e | đường dẫn jbroot được RootHide quản lý |

`iphoneos-arm64e` ở đây là kiến trúc gói của RootHide, không phải tuyên bố rằng payload dùng CPU arm64e. Bản này được biên dịch arm64 cho iPhone 6s của chủ dự án. Hành vi injection trên các thiết bị arm64e khác cần kiểm thử riêng.

Build macOS kiểm tra xác thực, Lua thật và cancellation, lưu cấu hình/filter, giao tiếp widget, lịch chạy, profile và sao lưu ứng dụng bằng fixture tạm. Kiểm tra payload đọc lại metadata, Mach-O, entitlements, tài nguyên và bộ lọc injection. Các kiểm tra này không thay thế việc cài/chạy trên iPhone.

Đã kết nối SSH qua USB và cài trên iPhone 6s/iOS 15.8.4/RootHide. Kiểm thử đã phát hiện và sửa quyền IOSurface/capture/GPU, sender cảm ứng và giới hạn bộ nhớ Vision. Tap đã đổi tab Sileo, nút Home có tác dụng, screenshot có nội dung, OCR trả chữ/tọa độ, MJPEG có frame và profile lưu/áp dụng/xóa được. Xem [phạm vi kiểm thử thiết bị](docs/DEVICE_TESTING.md); chưa xác nhận toàn bộ hook hoặc thiết bị khác.

## Cài qua Sileo

1. Thêm nguồn `https://jmehiepp.github.io/ios-auto-tool/`.
2. Tìm **iOS Auto Tool**, chọn gói đúng bootstrap và cài. Widget cần SpringBoard nạp lại tweak sau cài đặt.
3. Lấy mã kết nối bằng terminal root hoặc SSH:

```sh
# Rootless
/var/jb/Library/IOSAutoTool/iosautotool-daemon --access-code
# Rootful; trên RootHide chạy trong shell bootstrap tương ứng
/Library/IOSAutoTool/iosautotool-daemon --access-code
```

4. Mở `http://IP-IPHONE:8890` và nhập mã. Có thể dùng SSH tunnel rồi mở localhost.

Daemon do launchd quản lý. Script, lịch, account snapshot và mã kết nối nằm trong `/var/mobile/Library/IOSAutoTool` (RootHide dùng `jbroot`); dữ liệu riêng của daemon có quyền 0700, token 0600. Gỡ gói giữ dữ liệu cá nhân. Log nằm trong `/var/log/iosautotool` của bootstrap tương ứng.

## Lua và widget

```lua
log('Bắt đầu')
sleep(500)
tap(180, 300)
swipe(180, 500, 180, 200, 400)
typeText('Xin chào')
log(ocr() or 'Chưa có văn bản')
```

Tọa độ dùng logical points. [Inventory API](docs/lua-api.json) được xuất từ source; phần touch/screen/app là các hàm global. Widget cho phép chọn tệp `.lua` đã lưu, chạy, yêu cầu dừng và xem trạng thái; không tự chạy script khi tải tweak. Xem [widget](widget/README.md), [account snapshot](docs/APP_ACCOUNTS.md).

## Cấu hình thiết bị và profile

Mở **Device profiles** trong Web IDE. Nhập bundle ID của ứng dụng, chọn trường cần đổi và bật cấu hình. Có model/tên/iOS, màn hình, ngôn ngữ/múi giờ, nhà mạng/Wi-Fi, GPS, IDFA/IDFV, user agent/WebGL/canvas và thông số cảm biến. Đóng rồi mở lại ứng dụng đã chọn để nạp hook. Quyền vị trí và tracking của ứng dụng được giữ theo hệ thống.

Mặc định master tắt và danh sách ứng dụng rỗng. Có thể lưu bộ cấu hình thành profile có tên, áp dụng lại hoặc xóa bản đã lưu. Xem [kiểu giá trị và giới hạn từng hook](spoof/README.md).

```lua
spoof.applyPreset('iphone13')
spoof.setSelectedApps({'com.example.MyTestApp'})
spoof.setMasterEnabled(true)
```

Preset chuẩn bị giá trị; ứng dụng và master được chọn riêng. Bộ cấu hình dùng một schema chung cho Web IDE, Lua và MCP. Việc đổi accessor không thay thế phần cứng, baseband hay phiên bản iOS thật.

## MCP

Bridge trên iPhone không cần Python/Node. Ví dụ stdio cho Rootless:

```json
{"mcpServers":{"ios-auto-tool":{"command":"ssh","args":["root@IP-IPHONE","/var/jb/Library/IOSAutoTool/iosautotool-daemon","--mcp-stdio"]}}}
```

MCP có 26 tool, gồm lấy/đặt cấu hình, chạy Lua, yêu cầu dừng và kiểm tra trạng thái. `lua_run` trả kết quả nhận chạy; hoàn tất nằm trong log. HTTP/MCP yêu cầu token hoặc cookie xác thực. Chat AI tùy chọn dùng `ANTHROPIC_API_KEY` trong môi trường daemon; không nhúng key vào source/gói.

## Build và xuất bản

Dùng macOS, Xcode, Node, Python 3 và Theos:

```sh
export THEOS=~/theos
bash build.sh
```

Script dùng SDK 16.5, LuaJIT revision cố định, Mongoose 7.14 và fork RootHide/Theos được ghim commit. Nó tạo ba `.deb` cùng `packages/validation.json`. Workflow publish chỉ chạy tiếp sau khi kiểm tra thành công, cập nhật chỉ mục APT và đưa `repo/` lên nhánh `gh-pages`.

License và dependency được ghi tại [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Mỗi gói mang thông báo GPL của Mongoose và MIT của LuaJIT.
