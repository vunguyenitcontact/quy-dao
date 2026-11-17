-- Bảng xếp hạng Quỹ Đạo
-- Chạy được nhiều lần (idempotent). Dán vào SQL Editor của Supabase rồi bấm Run, hoặc dùng `supabase db push`.
--
-- Cách hoạt động: trình duyệt KHÔNG đọc/ghi thẳng vào bảng. Mọi thứ đi qua 3 hàm bên dưới,
-- nên mã người chơi (player) không bao giờ lộ ra ngoài và điểm gửi lên luôn được kiểm tra.

create table if not exists public.scores (
  day        integer     not null,                 -- ngày của bản đồ, dạng yyyymmdd
  player     uuid        not null,                 -- mã ngẫu nhiên sinh trên máy người chơi
  name       text        not null,
  score      integer     not null,
  planets    integer     not null,
  streak     integer     not null default 0,
  ip_hash    text,                                 -- băm của IP theo ngày, chỉ để chặn spam
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (day, player),
  constraint scores_name_len      check (char_length(name) between 2 and 16),
  constraint scores_score_range   check (score between 0 and 3000),
  constraint scores_planets_range check (planets between 0 and 500)
);

create index if not exists scores_day_score_idx on public.scores (day, score desc, updated_at);
create index if not exists scores_day_ip_idx    on public.scores (day, ip_hash);

-- Khoá bảng: không ai (kể cả khoá công khai) đọc/ghi trực tiếp được.
alter table public.scores enable row level security;
revoke all on public.scores from anon, authenticated;

create or replace function public.qd_day(ts timestamptz)
returns integer language sql immutable
as $$ select to_char(ts at time zone 'UTC', 'YYYYMMDD')::integer $$;

-- Đọc bảng xếp hạng của một ngày: top N, tổng số người, và hạng của chính người gọi (nếu có).
create or replace function public.leaderboard(p_day integer, p_player uuid default null, p_limit integer default 20)
returns json
language sql stable security definer set search_path = public, pg_temp
as $$
  with ranked as (
    select name, score, planets, player,
           row_number() over (order by score desc, updated_at asc) as rank
    from public.scores
    where day = p_day
  )
  select json_build_object(
    'day', p_day,
    'total', (select count(*) from ranked),
    'top', coalesce((
      select json_agg(json_build_object(
               'rank', rank, 'name', name, 'score', score, 'planets', planets,
               'me', coalesce(player = p_player, false)) order by rank)
      from ranked
      where rank <= least(greatest(coalesce(p_limit, 20), 1), 100)), '[]'::json),
    'me', (select json_build_object('rank', rank, 'name', name, 'score', score, 'planets', planets)
           from ranked where player = p_player)
  );
$$;

-- Kỷ lục mọi thời đại: điểm cao nhất của mỗi người qua tất cả các ngày.
create or replace function public.hall_of_fame(p_player uuid default null, p_limit integer default 20)
returns json
language sql stable security definer set search_path = public, pg_temp
as $$
  with best as (
    select distinct on (player) player, name, score, planets, day, updated_at
    from public.scores
    order by player, score desc, updated_at asc
  ),
  ranked as (
    select *, row_number() over (order by score desc, updated_at asc) as rank from best
  )
  select json_build_object(
    'total', (select count(*) from ranked),
    'top', coalesce((
      select json_agg(json_build_object(
               'rank', rank, 'name', name, 'score', score, 'planets', planets, 'day', day,
               'me', coalesce(player = p_player, false)) order by rank)
      from ranked
      where rank <= least(greatest(coalesce(p_limit, 20), 1), 100)), '[]'::json),
    'me', (select json_build_object('rank', rank, 'name', name, 'score', score, 'planets', planets, 'day', day)
           from ranked where player = p_player)
  );
$$;

-- Gửi điểm: giữ điểm cao nhất của mỗi người trong ngày, trả về luôn bảng xếp hạng mới.
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

  -- Chỉ nhận bản đồ của hôm nay (tính mọi múi giờ) và hôm qua (ván chơi vắt qua nửa đêm).
  if p_day < public.qd_day(now() - interval '36 hours') or p_day > public.qd_day(now() + interval '14 hours') then
    raise exception 'Bản đồ ngày này đã đóng bảng xếp hạng' using errcode = '22023';
  end if;

  v_name := btrim(regexp_replace(regexp_replace(coalesce(p_name, ''), '[[:cntrl:]<>]', '', 'g'), '\s+', ' ', 'g'));
  if char_length(v_name) < 2 or char_length(v_name) > 16 then
    raise exception 'Tên phải dài từ 2 đến 16 ký tự' using errcode = '22023';
  end if;

  -- Kiểm tra hợp lý: mỗi hành tinh cho tối đa 6 điểm (1 điểm + thưởng chuỗi 5).
  if p_planets < 0 or p_planets > 500 or p_score < 0 or p_score > p_planets * 6 + 5 then
    raise exception 'Điểm không hợp lệ' using errcode = '22023';
  end if;

  -- Chặn spam: tối đa 300 người chơi khác nhau từ cùng một địa chỉ mạng mỗi ngày
  -- (để rộng vì mạng di động và wifi công cộng dùng chung địa chỉ).
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

-- Chỉ mở 3 hàm này cho trình duyệt (khoá công khai).
revoke all on function public.submit_score(integer, uuid, text, integer, integer, integer) from public;
revoke all on function public.leaderboard(integer, uuid, integer)                         from public;
revoke all on function public.hall_of_fame(uuid, integer)                                 from public;
grant execute on function public.submit_score(integer, uuid, text, integer, integer, integer) to anon, authenticated;
grant execute on function public.leaderboard(integer, uuid, integer)                         to anon, authenticated;
grant execute on function public.hall_of_fame(uuid, integer)                                 to anon, authenticated;
grant execute on function public.qd_day(timestamptz)                                         to anon, authenticated;
