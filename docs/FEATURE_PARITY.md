# Phạm vi so với iOSAutomate

Đây là ledger triển khai, không phải chứng nhận tương đương. Báo cáo gốc trong workspace `rea/reports/` phân biệt static evidence và quan sát runtime. Đã cài/chạy trên iPhone 6s/iOS 15.8.4/RootHide; phạm vi cụ thể trong [DEVICE_TESTING.md](DEVICE_TESTING.md).

| Nhóm | Triển khai trong dự án | Ranh giới còn lại |
|---|---|---|
| Lua, Web IDE, tệp, log | LuaJIT interpreter, editor offline, lưu/chạy/dừng, WebSocket log | 59 global + 10 hàm spoof; chưa có đủ 285 tên API gốc hay bảo đảm chạy script cũ nguyên trạng |
| Touch/keyboard | tap/swipe/multi-touch, phím hệ thống, nhập chữ | Đã xác nhận tap chuyển tab Sileo và nút Home; swipe/multi-touch/nhập chữ cần thêm phép thử |
| Screen/vision | screenshot, OCR/Vision, màu, template image, MJPEG | Chưa có relay H.264/UDP 9001 hay giao thức REMOTE gốc |
| Lịch và recorder | lịch một lần/theo phút/hằng ngày; record touch từ Web IDE | Chưa record mọi thao tác vật lý toàn hệ thống |
| Widget | floating picker, chạy/dừng/status qua daemon | Cần kiểm thử SpringBoard và respring trên máy thật |
| Device | 27 trường, whitelist app, preset/profile, API/Lua/MCP | Hook accessor trong app; thiếu identity daemon/MobileGestalt/sysctl, WebContent/WebCore và nhiều bề mặt khác của gói Device gốc |
| Dữ liệu ứng dụng | snapshot Documents/Library/tmp, restore có rollback | Không phải clone cài độc lập; không có toàn bộ workflow clone/snapshot/keychain của bản gốc |
| MCP | 26 tools, stdio bridge, auth | Protocol/giao diện riêng, chưa có compatibility layer cho client REMOTE gốc |
| Đóng gói | rootful/rootless/roothide, APT/Sileo | Biên dịch arm64; runtime/injection trên máy arm64e khác chưa xác minh |

Gói Device gốc riêng đã được thu thập và trace bổ sung bằng REA 6.8.0 cùng Ghidra được ghi rõ provenance. Bằng chứng cho thấy clone stub, daemon helper và các hook WebKit/identity có đường code riêng. Tên export hoặc cờ cấu hình đơn lẻ không đủ chứng minh tính năng hoạt động trên mọi iOS.

Các mục còn lại trong cột ranh giới vẫn đang mở; không gọi bản beta này là bản sao đầy đủ của iOSAutomateEcosystem.
