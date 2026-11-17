-- Ngày của game tính theo giờ Việt Nam cho mọi người chơi (trước đây mỗi máy tự tính theo múi giờ của nó,
-- nên người ở múi giờ khác nhau rơi vào hai bảng xếp hạng khác nhau).

create or replace function public.qd_day(ts timestamptz)
returns integer language sql stable
as $$ select to_char(ts at time zone 'Asia/Ho_Chi_Minh', 'YYYYMMDD')::integer $$;

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

  -- Chỉ nhận bản đồ của hôm nay theo giờ Việt Nam, và của hôm qua (trang mở sẵn từ trước nửa đêm).
  -- Cộng 1 giờ để máy có đồng hồ chạy nhanh vài phút không bị từ chối oan lúc giao ngày.
  if p_day < public.qd_day(now() - interval '24 hours') or p_day > public.qd_day(now() + interval '1 hour') then
    raise exception 'Bản đồ ngày này đã đóng bảng xếp hạng. Tải lại trang để chơi bản đồ hôm nay' using errcode = '22023';
  end if;

  v_name := btrim(regexp_replace(regexp_replace(coalesce(p_name, ''), '[[:cntrl:]<>]', '', 'g'), '\s+', ' ', 'g'));
  if char_length(v_name) < 2 or char_length(v_name) > 16 then
    raise exception 'Tên phải dài từ 2 đến 16 ký tự' using errcode = '22023';
  end if;

  -- Kiểm tra hợp lý: mỗi hành tinh cho tối đa 6 điểm (1 điểm + thưởng chuỗi 5).
  if p_planets < 0 or p_planets > 500 or p_score < 0 or p_score > p_planets * 6 + 5 then
    raise exception 'Điểm không hợp lệ' using errcode = '22023';
  end if;

  -- Chặn spam: tối đa 300 người chơi khác nhau từ cùng một địa chỉ mạng mỗi ngày.
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
