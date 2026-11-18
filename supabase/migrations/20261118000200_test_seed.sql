-- CHỈ ĐỂ KIỂM THỬ (sẽ bị xoá ở file kế tiếp): thêm hai báo cáo giả từ hai "mạng" khác nhau cho người chơi thử d1,
-- để kiểm tra việc tự ẩn khi đủ 3 mạng báo cáo (từ một máy thì không tạo được 3 mạng thật).
insert into public.name_reports (player, reporter, name, reporter_ip) values
  ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-4000-8000-0000000000f1', 'Test Target', 'test-net-a'),
  ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-4000-8000-0000000000f2', 'Test Target', 'test-net-b')
on conflict do nothing;
