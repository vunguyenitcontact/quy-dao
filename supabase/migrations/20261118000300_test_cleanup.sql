-- Xoá toàn bộ dữ liệu kiểm thử của phần kiểm duyệt (người chơi giả d1, d2 và mọi báo cáo về họ).
delete from public.name_reports   where player in ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-4000-8000-0000000000d2');
delete from public.hidden_players where player in ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-4000-8000-0000000000d2');
delete from public.scores         where player in ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-4000-8000-0000000000d2');
