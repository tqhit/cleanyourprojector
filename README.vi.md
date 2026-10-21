# cleanyourprojector

Dọn app rác, chặn backdoor và tăng tốc máy chiếu Android giá rẻ qua Wi-Fi. Không cần root cho phần cơ bản, không gỡ app nào,
mọi thứ đều hoàn tác được.

Máy chiếu Android giá rẻ (T950S, dòng HY300, các mẫu "4K Smart Projector") thường chạy firmware còn tệ hơn cả cài app rác.
Máy đầu tiên được kiểm tra ở đây, **KAW K670**, mỗi lần kết nối Wi-Fi lại tải script qua HTTP không mã hoá rồi chạy bằng quyền
root. Server của hãng đã dùng kênh đó để cài app quảng cáo, đẩy thêm một su-daemon vào `/system` và gỡ app của đối thủ.
Máy còn báo khống RAM 2 GB trong khi thực tế chỉ có 1 GB. Chi tiết: [docs/JM-FIRMWARE-BACKDOOR.md](docs/JM-FIRMWARE-BACKDOOR.md).

## Công cụ

| Lệnh | |
|---|---|
| `tools/scan.sh <ip>` | Quét **chỉ đọc** cho mọi máy chiếu Android: code root do init chạy, script tự tải và chạy, file chèn qua overlay, RAM báo khống, ADB root/mở, SELinux, app cài ngầm, chỉ dấu đã biết, cổng mở và kết nối theo từng app, app chưa biên dịch |
| `tools/backup.sh <ip>` | Sao lưu package, prop, settings, Home trước khi thay đổi |
| `tools/inventory.sh <ip>` | Phân loại mọi package (giữ / rác / xem xét / tuỳ chọn, kèm quyền, RAM, leanback, Home) để lập danh sách cho máy mới |
| `tools/disable.sh <ip> <list>` | Tắt (`pm disable-user`) các app trong danh sách của máy |
| `tools/restore.sh <ip> <list>` | Bật lại tất cả, trả DNS và launcher gốc |
| `tools/harden.sh <ip> [--dns adguard]` | Tắt app độc hại trên mọi máy; với firmware JM còn chặn backdoor và mọi đường quay lại, tự áp lại mỗi lần khởi động |
| `tools/optimize.sh <ip>` | Giảm tiến trình nền, hiệu ứng nhanh hơn, biên dịch AOT các app chưa từng được biên dịch |
| `tools/install-launcher.sh <ip> devices/<model>` | Build và cài launcher kiểu Apple TV của [cleanyourtv](https://github.com/Gathin23/cleanyourtv) với cấu hình riêng cho từng máy, xử lý được bộ định tuyến Home của hãng |

Các chỉ dấu (package, domain, IP, file, prop, dòng init) nằm trong [data/indicators.tsv](data/indicators.tsv): thêm một dòng
firmware mới chỉ là thêm dữ liệu.

## Bắt đầu nhanh

Trên máy chiếu: bật Developer options và USB debugging (máy JM: *Projector → Other Setting → Developer Options*).
Trên máy tính cùng mạng:

```sh
git clone --recurse-submodules https://github.com/tqhit/cleanyourprojector
cd cleanyourprojector
tools/scan.sh 192.168.1.50
```

Cách dễ nhất: mở Claude Code trong thư mục này và dán [PROMPT.md](PROMPT.md), AI sẽ làm từng bước trên máy của bạn, giống
cleanyourtv làm với TV. Làm tay: đọc kết quả quét rồi theo `devices/<model>/README.md`; với máy chưa có trong danh sách thì
dùng `tools/inventory.sh` và `devices/_template/`. Gặp lỗi: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

**Làm xong thì tắt USB debugging.** Trên firmware JM, ADB chạy quyền root và không cần xác nhận, nên ai trong mạng nhà bạn
kết nối được tới cổng 5555 cũng chiếm toàn quyền máy chiếu.

## Giới hạn

- Factory reset sẽ khôi phục backdoor. Chạy lại `tools/harden.sh` trước khi cho máy kết nối Wi-Fi.
- Phần kích hoạt nằm trong framework Android, không gỡ được nếu không flash lại firmware. Cách triệt để duy nhất là không
  cho máy chiếu vào mạng và dùng một Android TV stick qua HDMI. Đó cũng là cách tăng tốc nhiều nhất.
- Netflix trên các máy này thường là bản điện thoại; cần app chuột ảo của hãng thì mới điều khiển được bằng remote.

## Ghi công

Dựa trên [cleanyourtv](https://github.com/Gathin23/cleanyourtv) của Gathin (MIT), dùng làm submodule cho launcher và làm mẫu
cho cách tiếp cận. cleanyourprojector là dự án độc lập, không liên kết với cleanyourtv.
