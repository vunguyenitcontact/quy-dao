-- Kiểm duyệt tên trên bảng xếp hạng (Apple yêu cầu với nội dung do người dùng tạo):
--   1. Lọc tên phản cảm ngay lúc gửi.
--   2. Người chơi báo cáo được tên phản cảm.
--   3. Tên bị đủ 3 người (từ 3 mạng khác nhau) báo cáo sẽ tự ẩn khỏi bảng, chờ chủ game xem lại.
-- Chủ game xem báo cáo ở bảng name_reports, và gỡ ẩn bằng cách xoá dòng trong hidden_players.

create table if not exists public.name_reports (
  id          bigint generated always as identity primary key,
  player      uuid        not null,      -- người bị báo cáo
  reporter    uuid        not null,      -- người báo cáo
  name        text        not null,      -- tên tại thời điểm bị báo cáo
  reporter_ip text,                      -- băm của IP người báo cáo, để đếm số mạng khác nhau
  created_at  timestamptz not null default now(),
  unique (player, reporter)
);
create index if not exists name_reports_reporter_idx on public.name_reports (reporter, created_at);

create table if not exists public.hidden_players (
  player     uuid primary key,
  reason     text,
  created_at timestamptz not null default now()
);

alter table public.name_reports   enable row level security;
alter table public.hidden_players enable row level security;
revoke all on public.name_reports, public.hidden_players from anon, authenticated;

-- Mã ngắn đại diện cho một người chơi trên bảng: đủ để báo cáo đúng người, không lộ mã người chơi thật.
create or replace function public.qd_key(p uuid)
returns text language sql immutable
as $$ select substr(md5(p::text || ':qd-row'), 1, 16) $$;

-- Tên có được phép không. Bỏ dấu cách, ký hiệu và đổi số/ký hiệu giả chữ (0→o, 1→i, 3→e, 4→a, 5→s, @→a, $→s) trước khi so.
create or replace function public.qd_name_ok(p_name text)
returns boolean language plpgsql immutable
as $$
declare
  v text := lower(coalesce(p_name, ''));
  flat text;
begin
  flat := translate(v, '0134578@$!', 'oieastbasi');
  flat := regexp_replace(flat, '[^[:alpha:]]', '', 'g');
  if flat ~ '(fuck|shit|bitch|cunt|nigg|faggot|nazi|hitler|porn|pussy|whore|slut|địt|đụm|lồn|cặc|buồi|đéo|đĩđ)' then return false; end if;
  -- viết tắt tục tĩu tiếng Việt, chỉ chặn khi đứng riêng thành một từ
  if v ~ '(^|[^[:alnum:]])(vcl|vkl|dmm|đmm|dcm|đcm|clm|đm|dm|cc)([^[:alnum:]]|$)' then return false; end if;
  return true;
end;
$$;

-- Bảng xếp hạng: bỏ người chơi đã bị ẩn (trừ chính họ, để họ không biết mình bị ẩn), thêm mã "key" cho từng dòng.
create or replace function public.leaderboard(p_day integer, p_player uuid default null, p_limit integer default 20)
returns json
language sql stable security definer set search_path = public, pg_temp
as $$
  with ranked as (
    select s.name, s.score, s.planets, s.player,
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
    select distinct on (s.player) s.player, s.name, s.score, s.planets, s.day, s.updated_at
    from public.scores s
    where s.player = p_player or not exists (select 1 from public.hidden_players h where h.player = s.player)
    order by s.player, s.score desc, s.updated_at asc
  ),
  ranked as (
    select *, row_number() over (order by score desc, updated_at asc) as rank from best
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

-- Báo cáo một tên trên bảng. p_key là mã dòng lấy từ bảng xếp hạng.
create or replace function public.report_name(p_key text, p_reporter uuid)
returns json
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_player uuid;
  v_name   text;
  v_ip     text := '';
  v_hash   text;
  v_today  integer;
  v_count  integer;
  v_hidden boolean := false;
begin
  if p_key is null or p_reporter is null then raise exception 'Thiếu dữ liệu' using errcode = '22023'; end if;
  select s.player, s.name into v_player, v_name
  from public.scores s where public.qd_key(s.player) = p_key order by s.updated_at desc limit 1;
  if v_player is null then raise exception 'Không tìm thấy người chơi này' using errcode = '22023'; end if;
  if v_player = p_reporter then raise exception 'Không thể báo cáo chính mình' using errcode = '22023'; end if;

  -- mỗi người báo cáo tối đa 20 lần mỗi ngày
  select count(*) into v_today from public.name_reports where reporter = p_reporter and created_at > now() - interval '24 hours';
  if v_today >= 20 then raise exception 'Bạn đã báo cáo quá nhiều hôm nay' using errcode = '54000'; end if;

  begin
    v_ip := split_part(coalesce(current_setting('request.headers', true)::json ->> 'x-forwarded-for', ''), ',', 1);
  exception when others then v_ip := '';
  end;
  v_hash := case when v_ip = '' then null else md5(v_ip || ':quydao-report') end;

  insert into public.name_reports (player, reporter, name, reporter_ip)
  values (v_player, p_reporter, v_name, v_hash)
  on conflict (player, reporter) do nothing;

  -- đủ 3 báo cáo từ 3 mạng khác nhau thì tự ẩn, chờ chủ game xem lại
  select count(distinct coalesce(reporter_ip, reporter::text)) into v_count from public.name_reports where player = v_player;
  if v_count >= 3 then
    insert into public.hidden_players (player, reason) values (v_player, 'tự ẩn: ' || v_count || ' báo cáo') on conflict (player) do nothing;
    v_hidden := true;
  end if;
  return json_build_object('ok', true, 'hidden', v_hidden);
end;
$$;

-- Gửi điểm: thêm bước lọc tên (mã lỗi QD001 để game báo đúng câu "tên không được phép").
create or replace function public.submit_score(
  p_day integer, p_player uuid, p_name text, p_score integer, p_planets integer, p_streak integer default 0)
returns json
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_name   text;
  v_ip     text := '';
  v_hash   text;
  v_others integer;
begin
  if p_day is null or p_player is null or p_score is null or p_planets is null then
    raise exception 'Thiếu dữ liệu' using errcode = '22023';
  end if;
  if p_day < public.qd_day(now() - interval '24 hours') or p_day > public.qd_day(now() + interval '1 hour') then
    raise exception 'Bản đồ ngày này đã đóng bảng xếp hạng. Tải lại trang để chơi bản đồ hôm nay' using errcode = '22023';
  end if;

  v_name := btrim(regexp_replace(regexp_replace(coalesce(p_name, ''), '[[:cntrl:]<>]', '', 'g'), '\s+', ' ', 'g'));
  if char_length(v_name) < 2 or char_length(v_name) > 16 then
    raise exception 'Tên phải dài từ 2 đến 16 ký tự' using errcode = '22023';
  end if;
  if not public.qd_name_ok(v_name) then
    raise exception 'Tên này không được phép. Hãy chọn tên khác' using errcode = 'QD001';
  end if;

  if p_planets < 0 or p_planets > 500 or p_score < 0 or p_score > p_planets * 6 + 5 then
    raise exception 'Điểm không hợp lệ' using errcode = '22023';
  end if;

  begin
    v_ip := split_part(coalesce(current_setting('request.headers', true)::json ->> 'x-forwarded-for', ''), ',', 1);
  exception when others then
    v_ip := '';
  end;
  if v_ip <> '' then
    v_hash := md5(v_ip || ':' || p_day::text || ':quydao');
    select count(*) into v_others from public.scores where day = p_day and ip_hash = v_hash and player <> p_player;
    if v_others >= 300 then
      raise exception 'Quá nhiều người chơi từ cùng một mạng hôm nay' using errcode = '54000';
    end if;
  end if;

  insert into public.scores as s (day, player, name, score, planets, streak, ip_hash)
  values (p_day, p_player, v_name, p_score, p_planets, greatest(coalesce(p_streak, 0), 0), v_hash)
  on conflict (day, player) do update set
    name       = excluded.name,
    planets    = case when excluded.score > s.score then excluded.planets else s.planets end,
    streak     = case when excluded.score > s.score then excluded.streak  else s.streak  end,
    updated_at = case when excluded.score > s.score then now()            else s.updated_at end,
    score      = greatest(s.score, excluded.score);

  return public.leaderboard(p_day, p_player, 20);
end;
$$;

revoke all on function public.report_name(text, uuid) from public;
grant execute on function public.report_name(text, uuid) to anon, authenticated;
grant execute on function public.qd_key(uuid)        to anon, authenticated;
grant execute on function public.qd_name_ok(text)    to anon, authenticated;
