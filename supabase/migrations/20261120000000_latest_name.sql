-- Hiện TÊN MỚI NHẤT của mỗi người chơi trên mọi bảng xếp hạng.
-- Trước đây bảng Kỷ lục lấy tên lưu ở dòng có điểm cao nhất, nên người đổi tên (ví dụ Omg → Sato)
-- vẫn hiện tên cũ ở bảng Kỷ lục nhưng tên mới ở bảng Hôm nay, trông như hai người khác nhau.
-- Tên mới nhất = tên ở dòng của ngày gần nhất (đổi tên luôn ghi vào dòng của hôm nay).

create or replace function public.qd_current_name(p uuid)
returns text language sql stable security definer set search_path = public, pg_temp
as $$ select s.name from public.scores s where s.player = p order by s.day desc, s.created_at desc limit 1 $$;
revoke all on function public.qd_current_name(uuid) from public, anon, authenticated;

create or replace function public.leaderboard(p_day integer, p_player uuid default null, p_limit integer default 20)
returns json
language sql stable security definer set search_path = public, pg_temp
as $$
  with ranked as (
    select public.qd_current_name(s.player) as name, s.score, s.planets, s.player,
           row_number() over (order by s.score desc, s.updated_at asc) as rank
    from public.scores s
    where s.day = p_day
      and (s.player = p_player or not exists (select 1 from public.hidden_players h where h.player = s.player))
  )
  select json_build_object(
    'day', p_day,
    'total', (select count(*) from ranked),
    'top', coalesce((
      select json_agg(json_build_object(
               'rank', rank, 'name', name, 'score', score, 'planets', planets,
               'me', coalesce(player = p_player, false), 'key', public.qd_key(player)) order by rank)
      from ranked
      where rank <= least(greatest(coalesce(p_limit, 20), 1), 100)), '[]'::json),
    'me', (select json_build_object('rank', rank, 'name', name, 'score', score, 'planets', planets)
           from ranked where player = p_player)
  );
$$;

create or replace function public.hall_of_fame(p_player uuid default null, p_limit integer default 20)
returns json
language sql stable security definer set search_path = public, pg_temp
as $$
  with best as (
    select distinct on (s.player) s.player, s.score, s.planets, s.day, s.updated_at
    from public.scores s
    where s.player = p_player or not exists (select 1 from public.hidden_players h where h.player = s.player)
    order by s.player, s.score desc, s.updated_at asc
  ),
  ranked as (
    select b.*, public.qd_current_name(b.player) as name,
           row_number() over (order by b.score desc, b.updated_at asc) as rank
    from best b
  )
  select json_build_object(
    'total', (select count(*) from ranked),
    'top', coalesce((
      select json_agg(json_build_object(
               'rank', rank, 'name', name, 'score', score, 'planets', planets, 'day', day,
               'me', coalesce(player = p_player, false), 'key', public.qd_key(player)) order by rank)
      from ranked
      where rank <= least(greatest(coalesce(p_limit, 20), 1), 100)), '[]'::json),
    'me', (select json_build_object('rank', rank, 'name', name, 'score', score, 'planets', planets, 'day', day)
           from ranked where player = p_player)
  );
$$;
