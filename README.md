# Orbit Hop (Quỹ Đạo)

Game một chạm chạy trên trình duyệt: phóng sao chổi qua từng hành tinh. Mỗi ngày một bản đồ mới, ai cũng chơi chung một bản đồ.

Chơi tại: https://vunguyenitcontact.github.io/quy-dao/

## Sửa game

- `game.html` là mã nguồn chính (một file, không cần cài gì).
- Chạy `./build.sh` để tạo lại `index.html` (bản đưa lên web và bản cho app iPhone).
- `assets-src/` chứa nguồn của icon và ảnh xem trước khi dán link.

## Bảng xếp hạng

- Điểm của Thử thách hôm nay được lưu trên Supabase (dự án `quy-dao`). Địa chỉ và khoá công khai nằm ở đầu phần script trong `game.html` (`SB_URL`, `SB_KEY`).
- Phần máy chủ là các file SQL trong `supabase/migrations/`. Sửa xong thì chạy `supabase db push --linked`.
- Trình duyệt không đọc/ghi thẳng vào bảng `scores`; mọi thứ đi qua 3 hàm `submit_score`, `leaderboard`, `hall_of_fame`.
- Muốn xoá một dòng điểm hay tên xấu: vào trang quản trị Supabase, mục Table Editor, bảng `scores`.
