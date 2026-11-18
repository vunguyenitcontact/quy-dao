-- Sửa bộ lọc tên: bỏ một mẫu gõ nhầm, và bỏ hai viết tắt quá dễ trùng với tên bình thường ("cc", "dm").
create or replace function public.qd_name_ok(p_name text)
returns boolean language plpgsql immutable
as $$
declare
  v text := lower(coalesce(p_name, ''));
  flat text;
begin
  flat := translate(v, '0134578@$!', 'oieastbasi');
  flat := regexp_replace(flat, '[^[:alpha:]]', '', 'g');
  if flat ~ '(fuck|shit|bitch|cunt|nigg|faggot|nazi|hitler|porn|pussy|whore|slut|địt|đụm|lồn|cặc|buồi|đéo)' then return false; end if;
  -- viết tắt tục tĩu tiếng Việt, chỉ chặn khi đứng riêng thành một từ
  if v ~ '(^|[^[:alnum:]])(vcl|vkl|dmm|đmm|dcm|đcm|clm|đm)([^[:alnum:]]|$)' then return false; end if;
  return true;
end;
$$;
