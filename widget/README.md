# Floating widget

Widget chỉ inject vào SpringBoard qua `iosautotool-widget.plist`. Startup hook hiện nút sau 2 giây; không chạy macro khi load tweak. `show`/`hide` giữ nguyên public signatures. UI được tạo bằng UIKit, không phụ thuộc đường dẫn bundle/asset cố định nên không cần prefix `/var/jb` cho resource.

Chạm nút để mở/đóng menu; kéo để di chuyển và lưu vị trí. Menu đọc tên macro từ daemon, chọn tên để chạy, và có nút dừng. ACK chạy chỉ xác nhận daemon đã nhận; trạng thái `running` được poll mỗi giây. ACK dừng chỉ xác nhận yêu cầu dừng, widget giữ trạng thái đang chạy cho tới khi `script_status` báo false. Các request chạy trên serial background queue; timeout không chặn SpringBoard main thread.

## IPC contract

Socket riêng: `/var/run/iosautotool-widget.sock`, do root daemon sở hữu `root:mobile`, mode0660. Core socket0600 không dùng bởi widget và không đổi quyền. Daemon phải kiểm tra UID501 và executable SpringBoard qua peer PID trước khi dispatch. Widget không đọc access-token, không đọc source script và không gửi code/shell/path tùy ý.

Một JSON object UTF-8 trên mỗi dòng, `id` là UUID. Client gửi đủ bytes và newline trước khi đọc; chờ ACK có cùng id, `ok` kiểu boolean/number. Connect/send/read dùng chung deadline3 giây, response tối đa64KiB; EOF thiếu newline, sai shape/id hoặc lỗi daemon đều không được xem là thành công.

| Action | Request bổ sung | ACK |
|---|---|---|
| `list_scripts` | Không | `{id,ok:true,scripts:["hello.lua"],running:false}` |
| `script_status` | Không | `{id,ok:true,running:false}` |
| `run_saved_script` | `name:"hello.lua"` | `{id,ok:true,running:true}` hoặc `{id,ok:false,error:"..."}` |
| `stop_script` | Không | `{id,ok:true}` khi yêu cầu được nhận |

Tên là basename `.lua`, UTF-8 tối đa255 byte, không dấu phân cách/control character. Daemon là nơi xác thực lại tên, chỉ mở file đã có trong `/var/mobile/Library/IOSAutoTool/scripts`, từ chối symlink/path escape và chịu trách nhiệm kiểm tra peer. Widget lấy danh sách qua IPC vì thư mục dữ liệu0700 của root không được mở cho mobile. Không có fallback gửi source vào core socket.

Darwin notifications `com.iosautotool.widget.show` và `.hide` chỉ đổi visibility. Hide không dừng macro. Các notification không mang code hoặc gây chạy macro; có thể dùng để khôi phục nút bị ẩn mà không restart macro/service.

## Kiểm tra

Transport test dùng chính header C được production Objective-C include. Trên macOS, từ thư mục `tool`:

```sh
mkdir -p .build-evidence
xcrun clang -std=c11 -Wall -Wextra -Werror tests/widget-transport-tests.c -o .build-evidence/widget-transport-tests
.build-evidence/widget-transport-tests
```

Tám trường hợp: fragmented request reads/ACK, ACK rồi peer close, EOF thiếu newline, daemon không ACK, response quá64KiB, partial response kéo dài vượt tổng deadline, request thiếu newline và socket path quá dài. Test không dùng core socket hay quyền root.

Host Windows hiện tại chưa có compiler POSIX/macOS, vì vậy không tự gán trạng thái pass cho lượt test này. Parent build sẽ chạy lệnh trên và build UIKit/Logos. Cần kiểm tra trên iPhone: startup không tự chạy; chọn macro có ACK và chạy1 lần; stop cooperative rồi statusfalse; script tự kết thúc cập nhật nút; daemon offline hiển thị lỗi trong3 giây; danh sách tên Unicode; kéo nút và rotation không lệch; menu đóng/mở; hide/show không thay runtime; core socket vẫn0600 và widget0660, peer app thường bị từ chối.
