-- Chủ game yêu cầu gỡ tên "ma thuật mỹ đen" khỏi bảng xếp hạng (cụm "mỹ đen" có thể bị coi là miệt thị).
-- Cách làm: đưa người chơi đó vào danh sách ẩn. Dòng điểm vẫn còn trong cơ sở dữ liệu, nên hoàn tác được
-- bằng cách xoá dòng tương ứng trong hidden_players.
insert into public.hidden_players (player, reason)
select distinct s.player, 'chủ game ẩn: tên "ma thuật mỹ đen"'
from public.scores s
where lower(s.name) = 'ma thuật mỹ đen'
on conflict (player) do nothing;

-- Chặn luôn cụm này trong bộ lọc tên để không ai đặt lại được.
create or replace function public.qd_name_ok(p_name text)
returns boolean language plpgsql immutable
as $$
declare
  v text := lower(coalesce(p_name, ''));
  flat text;
begin
  flat := translate(v, '0134578@$!', 'oieastbasi');
  flat := regexp_replace(flat, '[^[:alpha:]]', '', 'g');
  if flat ~ '(fuck|shit|bitch|cunt|nigg|faggot|nazi|hitler|porn|pussy|whore|slut|địt|đụm|lồn|cặc|buồi|đéo|mỹđen|myden)' then return false; end if;
  if v ~ '(^|[^[:alnum:]])(vcl|vkl|dmm|đmm|dcm|đcm|clm|đm)([^[:alnum:]]|$)' then return false; end if;
  return true;
end;
$$;
