-- Xoá hai dòng điểm thử tạo ra khi kiểm tra máy chủ lần đầu (mã người chơi giả, không phải người thật).
delete from public.scores
where player in ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000a2');
