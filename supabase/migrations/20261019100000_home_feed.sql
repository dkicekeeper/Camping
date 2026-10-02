-- Главная (M10): лента в виде постов — записи друзей и свои (поездки, отчёты, новые места, отзывы)
-- и свежие обсуждения публичных мест.
--
-- Видимость — как у friends_feed и карточек: чужое — только друзей и только то, что зритель видит
-- (private.can_view), свои записи — все, включая секретные и места на проверке. Обсуждения — в
-- открытых местах (private.is_open_place) без заблокированных авторов. Гостю — только обсуждения.
--
-- У поездки в ленте — упрощённый трек для превью маршрута: тот же видимый трек, что на странице
-- поездки (private.visible_track — без начала, конца, зон приватности и секретных мест), без высоты
-- и времени.

create function public.home_feed(
  p_limit integer default 20,
  p_before_at timestamptz default null,
  p_before_id uuid default null
)
returns table (
  kind text,
  id uuid,
  at timestamptz,
  author_id uuid,
  author_username text,
  author_display_name text,
  author_avatar_path text,
  data jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  viewer uuid := auth.uid();
  n integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  before_at timestamptz := coalesce(p_before_at, 'infinity'::timestamptz);
  before_id uuid := coalesce(p_before_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid);
begin
  return query
  with authors as (
    select f.friend_id as id from public.friendships f where viewer is not null and f.user_id = viewer
    union all
    select viewer where viewer is not null
  ),
  items as (
    (select 'trip'::text as kind, t.id, t.ended_at as at, t.owner_id as author_id,
            jsonb_build_object(
              'activity', t.activity,
              'title', t.title,
              'note', t.note,
              'started_at', t.started_at,
              'ended_at', t.ended_at,
              'moving_seconds', t.moving_seconds,
              'distance_m', t.distance_m,
              'elevation_gain_m', t.elevation_gain_m,
              'track', extensions.st_asgeojson(
                extensions.st_simplify(extensions.st_force2d(private.visible_track(t, viewer)), 0.0001), 5
              )::jsonb
            ) as data
       from public.trips t
       join authors a on a.id = t.owner_id
      where t.deleted_at is null
        and (t.ended_at, t.id) < (before_at, before_id)
        and private.can_view(viewer, t.owner_id, t.visibility)
      order by t.ended_at desc, t.id desc
      limit n)
    union all
    (select 'checkin', c.id, c.at, c.owner_id,
            jsonb_build_object(
              'place_id', p.id,
              'place_name', p.name,
              'place_type', p.type,
              'verified', c.verified,
              'conditions', c.conditions,
              'note', c.note,
              'catches', private.checkin_catches_json(c.id, viewer),
              'media', private.checkin_media_json(c.id, viewer)
            )
       from public.checkins c
       join authors a on a.id = c.owner_id
       join public.places p on p.id = c.place_id
      where c.deleted_at is null
        and (c.at, c.id) < (before_at, before_id)
        and p.deleted_at is null
        and (p.status = 'published' or p.owner_id = viewer)
        and private.can_view(viewer, p.owner_id, p.visibility)
        and private.can_view(viewer, c.owner_id, c.visibility)
      order by c.at desc, c.id desc
      limit n)
    union all
    (select 'place', p.id, p.created_at, p.owner_id,
            jsonb_build_object(
              'place_type', p.type,
              'name', p.name,
              'approximate', p.approximate
            )
       from public.places p
       join authors a on a.id = p.owner_id
      where p.deleted_at is null
        and (p.status = 'published' or p.owner_id = viewer)
        and (p.created_at, p.id) < (before_at, before_id)
        and private.can_view(viewer, p.owner_id, p.visibility)
      order by p.created_at desc, p.id desc
      limit n)
    union all
    (select 'review', r.id, r.created_at, r.owner_id,
            jsonb_build_object(
              'place_id', p.id,
              'place_name', p.name,
              'place_type', p.type,
              'rating', r.rating,
              'body', r.body
            )
       from public.reviews r
       join authors a on a.id = r.owner_id
       join public.places p on p.id = r.place_id
      where r.deleted_at is null
        and (r.created_at, r.id) < (before_at, before_id)
        and private.is_open_place(r.place_id, viewer)
      order by r.created_at desc, r.id desc
      limit n)
    union all
    (select 'thread', t.id, t.created_at, t.owner_id,
            jsonb_build_object(
              'place_id', p.id,
              'place_name', p.name,
              'place_type', p.type,
              'title', t.title,
              'body', left(t.body, 300),
              'posts_count', t.posts_count,
              'last_activity_at', t.last_activity_at
            )
       from public.threads t
       join public.places p on p.id = t.place_id
      where t.deleted_at is null
        and (t.created_at, t.id) < (before_at, before_id)
        and private.is_open_place(t.place_id, viewer)
        and (viewer is null or not private.is_blocked(viewer, t.owner_id))
      order by t.created_at desc, t.id desc
      limit n)
  )
  select i.kind, i.id, i.at, i.author_id, pr.username, pr.display_name, pr.avatar_path, i.data
    from items i
    join public.profiles pr on pr.id = i.author_id
   order by i.at desc, i.id desc
   limit n;
end;
$$;

revoke execute on function public.home_feed(integer, timestamptz, uuid) from public;
grant execute on function public.home_feed(integer, timestamptz, uuid) to anon, authenticated;
