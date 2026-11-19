-- Bỏ dạng không dấu "myden" khỏi bộ lọc: nó chặn nhầm tên bình thường (ví dụ "Amy Dennis"). Giữ dạng có dấu.
create or replace function public.qd_name_ok(p_name text)
returns boolean language plpgsql immutable
as $$
declare
  v text := lower(coalesce(p_name, ''));
  flat text;
begin
  flat := translate(v, '0134578@$!', 'oieastbasi');
  flat := regexp_replace(flat, '[^[:alpha:]]', '', 'g');
  if flat ~ '(fuck|shit|bitch|cunt|nigg|faggot|nazi|hitler|porn|pussy|whore|slut|địt|đụm|lồn|cặc|buồi|đéo|mỹđen)' then return false; end if;
  if v ~ '(^|[^[:alnum:]])(vcl|vkl|dmm|đmm|dcm|đcm|clm|đm)([^[:alnum:]]|$)' then return false; end if;
  return true;
end;
$$;
