-- Фото места (M8c): все фото посетителей из отчётов и уловов — для карусели в карточке места и
-- сетки «Все фото».
--
-- Видимость — та же, что у фото в отчётах: место видно зрителю, фото проходит
-- private.media_visible (видны чекин и, для фото улова, сам улов; блокировки учитываются).
-- Фильтр p_kind: null / 'all' — все, 'catches' — фото уловов, 'place' — фото места (без улова).
-- Страницы — свежие сверху; p_after — id последнего фото предыдущей страницы (у фото одного отчёта
-- общее время, поэтому курсор — по id, а не по времени). Невидимое фото курсором не служит.
-- Ошибки: 22023 — неизвестный фильтр.

create function public.place_photos(
  p_place uuid,
  p_kind text default null,
  p_limit integer default 60,
  p_after uuid default null
)
returns table (
  id uuid,
  checkin_id uuid,
  catch_id uuid,
  path text,
  thumb_path text,
  width integer,
  height integer,
  at timestamptz,
  author_id uuid,
  author_username text,
  author_display_name text,
  author_avatar_path text,
  is_own boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  viewer uuid := auth.uid();
  n integer := least(greatest(coalesce(p_limit, 60), 1), 100);
  before_at timestamptz := 'infinity'::timestamptz;
  before_id uuid := 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid;
begin
  if p_kind is not null and p_kind not in ('all', 'catches', 'place') then
    raise exception 'invalid kind' using errcode = '22023';
  end if;
  if p_after is not null then
    select c.at, m.id into before_at, before_id
      from public.media m
      join public.checkins c on c.id = m.checkin_id
     where m.id = p_after
       and private.media_visible(viewer, m.id);
    if not found then
      return;
    end if;
  end if;

  return query
  select m.id, c.id, m.catch_id,
         m.storage_path,
         m.owner_id::text || '/' || m.id::text || '_thumb.jpg',
         m.width, m.height,
         c.at,
         c.owner_id, pr.username, pr.display_name, pr.avatar_path,
         c.owner_id is not distinct from viewer
    from public.media m
    join public.checkins c on c.id = m.checkin_id
    join public.places p on p.id = c.place_id
    join public.profiles pr on pr.id = c.owner_id
   where c.place_id = p_place
     and m.deleted_at is null
     and c.deleted_at is null
     and p.deleted_at is null
     and (p.status = 'published' or p.owner_id = viewer)
     and private.can_view(viewer, p.owner_id, p.visibility)
     and private.media_visible(viewer, m.id)
     and (p_kind is null or p_kind = 'all'
          or (p_kind = 'catches' and m.catch_id is not null)
          or (p_kind = 'place' and m.catch_id is null))
     and (c.at, m.id) < (before_at, before_id)
   order by c.at desc, m.id desc
   limit n;
end;
$$;

revoke execute on function public.place_photos(uuid, text, integer, uuid) from public;
grant execute on function public.place_photos(uuid, text, integer, uuid) to anon, authenticated;
