-- App đã được Apple duyệt: xoá người chơi giả "Demo Player" (chỉ tạo ra để quay video cho người duyệt).
delete from public.name_reports   where player = '00000000-0000-4000-8000-00000000de30';
delete from public.hidden_players where player = '00000000-0000-4000-8000-00000000de30';
delete from public.scores         where player = '00000000-0000-4000-8000-00000000de30';
