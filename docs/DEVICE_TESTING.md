# Kiểm thử iPhone qua USB

Ngày 10/11/2026: iPhone 6s (`iPhone8,1`), iOS 15.8.4, RootHide/Dopamine. Cài bằng SSH qua USB đã ghép đôi. Mật khẩu và mã kết nối không được ghi trong source hay báo cáo.

## Các phép thử đã quan sát

- API không có mã bị từ chối HTTP 401; có mã truy cập được. MCP `device_info` trả đúng model và kích thước 375×667, scale 2.
- Lua thực thi và ghi log. HTTP screenshot trả PNG 750×1334, quan sát đúng nội dung Sileo. MJPEG trả multipart/frame.
- Tap qua API chuyển Sileo từ Nguồn sang Đặc sắc. Thử trước đó với prototype HID chuyển ngược lại. Nút Home đưa máy về màn hình chính.
- OCR trả chữ và bounding box của màn hình Nguồn. Tiếng Việt chưa chính xác hoàn toàn trên Vision của iOS 15; không suy ra hỗ trợ ngôn ngữ từ tên cấu hình.
- Profile thử `usb-smoke` được tạo, liệt kê, áp dụng và xóa; master Device vẫn tắt, danh sách app trống.
- SpringBoard đã được nạp lại để thử widget. Phần chọn/chạy/dừng macro bằng widget đang chờ mở khóa máy để quan sát.

## Lỗi phát hiện trên máy thật

1. `IOSurfaceCreate` bị từ chối user client. Cấp `IOSurfaceRootUserClient` giúp tạo surface; `com.apple.QuartzCore.global-capture` giúp thu được nội dung thay vì frame đen.
2. Digitizer thiếu sender và sai khai báo ABI/field. Bản sửa đọc registry ID của touchscreen service, giữ 64 bit và gắn vào event; không dùng ID cố định lấy từ thiết bị khác.
3. Vision bị giới hạn 18 MiB và crash trong `CI::GLContext`. Đặt giới hạn hữu hạn 256 MiB cho chính daemon; cấp `AGXDeviceUserClient` theo deny log của kernel. `usesCPUOnly` không loại bỏ nhu cầu Core Image preprocessing. Phép thử sau cấp quyền đã trả kết quả OCR.
4. Foundation trên RootHide xử lý đường dẫn có leaf chưa tồn tại khác đường dẫn thư mục đã tồn tại. Bản sửa resolve thư mục trước khi thêm tên script đã được xác nhận: tạo, đọc đúng nội dung và xóa `USB-created.lua` đều HTTP 200.

Các quan sát sửa lỗi ban đầu dùng gói candidate và ký lại daemon chẩn đoán tại chỗ. Sau đó đã cài lại gói RootHide build từ `a11d4a4` (Actions `42750700103`, SHA-256 `.deb` `a440eaa0a7639af99c341d37d82ff9525a702f52a8c3341c1ddb50e6e14329be`), không ký lại/chỉnh quyền tại chỗ: daemon tự báo active/inactive 256 MiB, file API tạo/đọc/xóa thành công, screenshot có nội dung màn hình khóa và OCR đọc được giờ/ngày. Tap đã kiểm thử ở candidate trước với cùng mã HID; sau respring máy cần chủ máy mở khóa để tiếp tục kiểm tra giao diện.

Chưa kiểm thử restore dữ liệu trên app cá nhân, clone, toàn bộ hook Device, multi-touch, thiết bị/iOS khác hoặc tính tương thích toàn bộ script cũ. Host fixture tests chỉ xác nhận hợp đồng và rollback trên dữ liệu thử.

## Xác nhận gói công khai beta2

Đã tải lại và cài gói RootHide từ nguồn công khai, build `91d2d9994428d90d9519de5cf2429a959402bb51`, SHA-256 `.deb` `c4147acd6d8e663080c59929fe0033450b5e6f3603ee5092ac4ac7cb69790303`. Sau cài, phần Mach-O `__text` và toàn bộ XML entitlements khớp payload; hash toàn file thay đổi sau quá trình cài của bootstrap. Không ký lại bản công khai để thử.

Trên bản công khai: screenshot có nội dung, OCR đọc giờ/ngày, MJPEG có frame, API tạo/đọc/xóa script mới đều HTTP 200. Master Device tắt và danh sách ứng dụng trống. Lua chặn chạy chồng HTTP 409, dừng được vòng lặp và chạy lại sau stop (cùng source engine ở candidate trước đó).

Nguồn đã được thêm vào APT trên iPhone. Trang 404 riêng sửa lỗi HTTP 503 khi thiếu metadata tùy chọn; `Release` có Date và hash trong cùng một paragraph Deb822. Sau sửa, APT update hoàn tất không cảnh báo và nhận `1.2.0~beta2` từ nguồn ở priority 500. Widget còn chờ chủ máy mở khóa trực tiếp sau respring.
