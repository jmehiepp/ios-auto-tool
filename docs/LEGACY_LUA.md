# Chạy script iOSAutomate core

Beta5 thêm chế độ tương thích **một phần**. Chọn **iOSAutomate core · pixel / s** trong thanh Run, hoặc thêm dòng đầu sau vào tệp:

```lua
--!iosautomate
sleep(1)                -- giây
tap(300, 600)           -- pixel
mSleep(200)             -- mili giây
local rgb = getColor(300, 600) -- một số 0xRRGGBB hoặc nil
```

Dấu đầu tệp được lưu cùng script, nên IDE, CLI, lịch và widget dùng cùng chế độ. Bỏ dấu này để dùng API Native với point và mili giây. Không đoán đơn vị theo độ lớn của tham số. Mỗi lần chạy legacy có môi trường global riêng; đổi chế độ không thay global Native.

## Phần đã triển khai

- `sleep`/`delay` dùng giây, hỗ trợ khoảng ngẫu nhiên; `usleep` dùng microsecond, `mSleep`/`msleep`/`msleep_ms` dùng mili giây. Chờ được chia đoạn để nhận yêu cầu dừng.
- Tap, doubleTap, longPress, swipe đổi pixel sang point. `touchDown`/`touchMove` hỗ trợ dạng hai hoặc ba tham số theo wrapper gốc; `touchUp` dùng vị trí đã lưu khi có ít hơn ba tham số. `handReset`/`touchReset` nhả các contact do tool giữ.
- `screenSize`, `screenWidth`, `screenHeight`, `getScreenResolution` trả pixel. `getColor`/`getPixelColor` trả packed RGB. `getColors` dùng một frame cho cả batch, trả 0 cho điểm lỗi.
- `keepScreen` giữ ảnh cho các phép phân tích; `releaseScreen` bỏ giữ. `screenshot` luôn chụp mới và trả userdata ảnh của dự án có width/height/crop/save; đây không phải ABI userdata của sản phẩm gốc.
- `findColor` trả danh sách `{x,y}` với sai số mỗi kênh 8. `findColors` nhận pattern `{dx,dy,rgb}` với sai số 25; hỗ trợ tối đa 256 điểm pattern và 10.000 kết quả. Region là `{x,y,w,h}` theo pixel.
- `findImage(path,arg2,similarity,region)` trả danh sách chứa tối đa một kết quả `{x,y,score}`. Arg2 được chấp nhận nhưng chưa có hợp đồng đầy đủ; thuật toán NCC, thứ tự chọn kết quả và hiệu năng không được coi là giống bản gốc.
- `ocr`/`orc`/`recognizeText` trả observations và văn bản ghép. Observation có `rectangle` gồm bốn góc `{x,y}`. `findText`, `waitForText`, `waitForImage`, `waitForColor` dùng tọa độ pixel; wait dùng deadline đơn điệu và chụp mới ngay cả khi đang giữ screen.
- Adapter appRun/appKill và các alias, apps dạng danh sách bundle ID, foreground/SpringBoard dạng chuỗi rỗng, clipboard, shell một kết quả, màu RGB và random. Backend nhập chữ/launch/gesture vẫn là của dự án.
- `httpGet` nhận bảng header; `httpPost` nhận chuỗi hoặc bảng JSON và bảng header. Kiểu response/status vẫn theo HTTP backend của dự án; chưa xác nhận toàn bộ lỗi, cookie hoặc options của sản phẩm gốc.

`require('json')`, `require('base64')`, `require('plist')`, `require('lfs')`, `require('md5')` dùng native bindings. JSON giữ boolean, Unicode và null qua `json.null`; mảng rỗng cần `json.array()`, `{}` là object. Lỗi conversion trả `nil,error`; không mô phỏng chính xác mọi wrapper lỗi gốc. Base64 giữ byte NUL. Plist hỗ trợ read/write/load/dump XML và đọc binary; không hỗ trợ đầy đủ tùy chọn output format. Lfs có mkdir/rmdir/attributes/currentdir/dir; `dir` trả iterator trên snapshot tên, không giữ descriptor mở. MD5 có `sumhexa` cho tương thích dữ liệu, không dùng làm cơ chế xác thực.

`tmpDir()` và `os.tmpname()` dùng thư mục tạm riêng của dự án (0700), mỗi tệp được tạo bằng mkstemp (0600). `scriptDir()` trả đường dẫn scripts đã resolve, gồm đường dẫn bootstrap thực khi dùng RootHide. Script tự dọn tệp tạm sau khi sử dụng.

Lua Device có `spoof.listProfiles()`, `saveProfile(name)`, `applyProfile(name)`, `deleteProfile(name)`, `renameProfile(old,new)`. Đổi tên từ chối ghi đè đích. Chúng quản lý schema của dự án; không tự alias ResetDevice/RestoreDevice hoặc workflow clone của sản phẩm khác.

## Giới hạn còn mở

Chưa phải drop-in cho 285 tên đăng ký gốc. Async/timer/dialog/overlay, pinch/rotate, recorder thao tác vật lý, account/Crane/clone và một số API hệ thống chưa có hợp đồng tương đương. Swipe chạy đồng bộ và đường nội suy khác; khác biệt blocking còn tồn tại. Rotation, màn hình scale khác và script bên thứ ba cần kiểm thử riêng. Module do script tự `require`/`dofile` nạp không tự chuyển môi trường legacy; header chỉ áp dụng chunk chính.

Xem [phạm vi sản phẩm](FEATURE_PARITY.md) và [bằng chứng trên iPhone](DEVICE_TESTING.md). Số binding, alias hoặc assertion không phải tỷ lệ hoàn thiện chức năng.
