-- Поездки друзей, зоны приватности, профиль другого человека и лента друзей (M4b).
--
-- Трек для других (не для автора) обрезается:
--  * начало и конец поездки скрыты всегда: случайные 200–500 м от старта и от финиша, выбранные
--    один раз при сохранении поездки (trim_start_m / trim_end_m);
--  * участки внутри зон приватности автора (дом, дача) скрыты. Круг скрытия строится вокруг
--    центра со стабильным смещением (hidden_center), а не вокруг самой точки: иначе обрезанные
--    края треков разных поездок ложатся на окружность с домом в центре и выдают его. Радиус круга —
--    1,4 радиуса зоны, смещение — не больше 0,4 радиуса, поэтому вокруг самой точки скрыто не
--    меньше выбранного радиуса;
--  * участки у мест, которые зритель не видит точно (секретное, приблизительное, на модерации),
--    скрыты в круге 1500 м вокруг смещённого центра места (approx_center), а не самой точки.
--
-- Всё чужое — через RPC с private.can_view; координаты зон приватности другим не отдаются никогда.

-- Смещение точки на заданное расстояние в случайном направлении.
create function private.offset_point(p extensions.geometry, distance_m double precision)
returns extensions.geometry
language sql volatile
set search_path = ''
as $$
  select extensions.st_setsrid(
    extensions.st_project(p::extensions.geography, distance_m, random() * 2 * pi())::extensions.geometry,
    4326
  );
$$;

-- Зоны приватности -----------------------------------------------------------------------------

create table public.privacy_zones (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  name          text not null check (char_length(name) between 1 and 50),
  geom          extensions.geometry(Point, 4326) not null,
  radius_m      integer not null default 500 check (radius_m between 200 and 1000),
  hidden_center extensions.geometry(Point, 4326) not null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index privacy_zones_owner_idx on public.privacy_zones (owner_id);

comment on column public.privacy_zones.hidden_center is
  'Центр круга скрытия со стабильным смещением. Выставляет триггер; клиенту не отдаётся.';

create function private.privacy_zones_limit() returns integer
language sql immutable
set search_path = ''
as $$ select 10 $$;

-- Радиус круга скрытия вокруг hidden_center (+5 м — на то, что круг строится многоугольником).
create function private.zone_hidden_radius_m(radius_m integer) returns double precision
language sql immutable
set search_path = ''
as $$ select radius_m * 1.4 + 5 $$;

create function private.privacy_zones_before_write() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if private.is_client_request() then
      new.owner_id := auth.uid();
    end if;
    new.created_at := now();
  else
    new.owner_id := old.owner_id;
    new.created_at := old.created_at;
  end if;

  if new.owner_id is null then
    raise exception 'auth required' using errcode = '28000';
  end if;

  if tg_op = 'INSERT' then
    perform pg_advisory_xact_lock(hashtext('privacy_zones:' || new.owner_id::text));
    if (select count(*) from public.privacy_zones where owner_id = new.owner_id)
       >= private.privacy_zones_limit() then
      raise exception 'too many privacy zones' using errcode = '54000';
    end if;
  end if;

  if tg_op = 'INSERT'
     or extensions.st_asewkb(new.geom) is distinct from extensions.st_asewkb(old.geom)
     or new.radius_m <> old.radius_m then
    new.hidden_center := private.offset_point(new.geom, new.radius_m * (0.1 + random() * 0.3));
  else
    new.hidden_center := old.hidden_center;
  end if;

  new.updated_at := now();
  return new;
end;
$$;

create trigger privacy_zones_before_write before insert or update on public.privacy_zones
  for each row execute function private.privacy_zones_before_write();

alter table public.privacy_zones enable row level security;

revoke all on table public.privacy_zones from anon, authenticated;
grant select (id, owner_id, name, geom, radius_m, created_at, updated_at)
  on table public.privacy_zones to authenticated;
grant insert (id, name, geom, radius_m) on table public.privacy_zones to authenticated;
grant update (name, geom, radius_m) on table public.privacy_zones to authenticated;
grant delete on table public.privacy_zones to authenticated;

create policy "privacy_zones: читать свои" on public.privacy_zones
  for select to authenticated using (owner_id = (select auth.uid()));

create policy "privacy_zones: создавать свои" on public.privacy_zones
  for insert to authenticated with check (owner_id = (select auth.uid()));

create policy "privacy_zones: менять свои" on public.privacy_zones
  for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

create policy "privacy_zones: удалять свои" on public.privacy_zones
  for delete to authenticated using (owner_id = (select auth.uid()));

-- Обрезка начала и конца трека ----------------------------------------------------------------

-- Сколько метров трека скрыть от старта и от финиша. Случайно и один раз на поездку: при каждом
-- запросе заново — края можно было бы усреднить.
alter table public.trips
  add column trim_start_m integer not null default (200 + floor(random() * 301))::integer
    check (trim_start_m between 200 and 500),
  add column trim_end_m integer not null default (200 + floor(random() * 301))::integer
    check (trim_end_m between 200 and 500);

comment on column public.trips.trim_start_m is 'Метры трека от старта, скрытые от других.';
comment on column public.trips.trim_end_m is 'Метры трека до финиша, скрытые от других.';

-- Радиус скрытия трека у места, которое зритель не видит точно. Круг вокруг approx_center
-- (смещение до 800 м от места) с таким радиусом закрывает место с запасом около 700 м.
create function private.secret_place_track_radius_m() returns integer
language sql immutable
set search_path = ''
as $$ select 1500 $$;

-- Трек поездки, который видит зритель: автору — целиком, другим — без начала, конца, зон
-- приватности автора и участков у мест, которых зритель точно не видит. Для других — набор
-- видимых отрезков (MultiLineString) или null, если не осталось ничего.
-- Видимость самой поездки проверяет вызывающая функция.
create function private.visible_track(p_trip public.trips, p_viewer uuid)
returns extensions.geometry
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  hidden extensions.geometry;
  result extensions.geometry;
begin
  if p_trip.track is null then
    return null;
  end if;
  if p_viewer is not distinct from p_trip.owner_id then
    return p_trip.track;
  end if;

  select extensions.st_union(a.area) into hidden
    from (
      select extensions.st_buffer(
               z.hidden_center::extensions.geography,
               private.zone_hidden_radius_m(z.radius_m),
               'quad_segs=16'
             )::extensions.geometry as area
        from public.privacy_zones z
       where z.owner_id = p_trip.owner_id
      union all
      select extensions.st_buffer(
               p.approx_center::extensions.geography,
               private.secret_place_track_radius_m(),
               'quad_segs=16'
             )::extensions.geometry
        from public.checkins c
        join public.places p on p.id = c.place_id
       where c.owner_id = p_trip.owner_id
         and c.deleted_at is null
         and c.at between p_trip.started_at and p_trip.ended_at
         and not (
           p.deleted_at is null
           and p.status = 'published'
           and not p.approximate
           and private.can_view(p_viewer, p.owner_id, p.visibility)
         )
    ) a;

  with pts as (
    select d.path[1] as n, d.geom
      from extensions.st_dumppoints(p_trip.track) d
  ),
  steps as (
    select n, geom,
           coalesce(extensions.st_distance(
             geom::extensions.geography,
             (lag(geom) over (order by n))::extensions.geography
           ), 0) as step
      from pts
  ),
  along as (
    select n, geom, sum(step) over (order by n) as dist, sum(step) over () as total
      from steps
  ),
  kept as (
    select n, geom, n - row_number() over (order by n) as run
      from along
     where dist >= p_trip.trim_start_m
       and dist <= total - p_trip.trim_end_m
       and (hidden is null or not extensions.st_intersects(geom, hidden))
  ),
  segments as (
    select extensions.st_makeline(array_agg(geom order by n)) as line
      from kept
     group by run
    having count(*) >= 2
  )
  select extensions.st_collect(line) into result from segments;

  return result;
end;
$$;

-- Общие части ответов: уловы и фото чекина, которые видит зритель --------------------------------

create function private.checkin_catches_json(p_checkin uuid, p_viewer uuid) returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', k.id,
           'species_id', k.species_id,
           'count', k.count,
           'released', k.released,
           'weight_g', case when k.hide_size and k.owner_id is distinct from p_viewer then null else k.weight_g end,
           'length_mm', case when k.hide_size and k.owner_id is distinct from p_viewer then null else k.length_mm end
         ) order by k.at), '[]'::jsonb)
    from public.catches k
   where k.checkin_id = p_checkin
     and k.deleted_at is null
     and private.can_view(p_viewer, k.owner_id, k.visibility);
$$;

create function private.checkin_media_json(p_checkin uuid, p_viewer uuid) returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', m.id,
           'catch_id', m.catch_id,
           'path', m.storage_path,
           'thumb_path', m.owner_id::text || '/' || m.id::text || '_thumb.jpg',
           'width', m.width,
           'height', m.height
         ) order by m.created_at, m.id), '[]'::jsonb)
    from public.media m
   where m.checkin_id = p_checkin
     and private.media_visible(p_viewer, m.id);
$$;

-- RPC: поездка ----------------------------------------------------------------------------------

-- Поездка, которую видит зритель (своя или чужая по видимости), с треком в GeoJSON:
-- своя — LineString целиком, чужая — MultiLineString видимых отрезков или null.
create function public.trip_view(p_trip uuid)
returns table (
  id uuid,
  owner_id uuid,
  owner_username text,
  owner_display_name text,
  owner_avatar_path text,
  activity public.trip_activity,
  title text,
  note text,
  started_at timestamptz,
  ended_at timestamptz,
  moving_seconds integer,
  distance_m integer,
  elevation_gain_m integer,
  max_speed_mps real,
  visibility public.visibility,
  is_own boolean,
  track jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select t.id, t.owner_id, pr.username, pr.display_name, pr.avatar_path,
         t.activity, t.title, t.note, t.started_at, t.ended_at,
         t.moving_seconds, t.distance_m, t.elevation_gain_m, t.max_speed_mps, t.visibility,
         t.owner_id = auth.uid(),
         extensions.st_asgeojson(private.visible_track(t, auth.uid()), 6)::jsonb
    from public.trips t
    join public.profiles pr on pr.id = t.owner_id
   where t.id = p_trip
     and t.deleted_at is null
     and private.can_view(auth.uid(), t.owner_id, t.visibility);
$$;

-- Чекины автора за время поездки, которые видит зритель. Место — если зритель его видит,
-- иначе place_id и place_name пустые («Секретное место»).
create function public.trip_checkins(p_trip uuid)
returns table (
  checkin_id uuid,
  at timestamptz,
  verified boolean,
  place_id uuid,
  place_name text,
  conditions jsonb,
  note text,
  catches jsonb,
  media jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id, c.at, c.verified,
         case when pv.visible then p.id end,
         case when pv.visible then p.name end,
         c.conditions, c.note,
         private.checkin_catches_json(c.id, auth.uid()),
         private.checkin_media_json(c.id, auth.uid())
    from public.trips t
    join public.checkins c
      on c.owner_id = t.owner_id
     and c.at between t.started_at and t.ended_at
     and c.deleted_at is null
    join public.places p on p.id = c.place_id
    cross join lateral (
      select p.deleted_at is null
             and (p.status = 'published' or p.owner_id = auth.uid())
             and private.can_view(auth.uid(), p.owner_id, p.visibility) as visible
    ) pv
   where t.id = p_trip
     and t.deleted_at is null
     and private.can_view(auth.uid(), t.owner_id, t.visibility)
     and private.can_view(auth.uid(), c.owner_id, c.visibility)
   order by c.at;
$$;

-- RPC: профиль другого человека -------------------------------------------------------------------

-- Поездки человека, которые видит зритель, без трека. Новые сверху; p_before — для следующей
-- страницы (started_at последней показанной).
create function public.user_trips(p_user uuid, p_limit integer default 20, p_before timestamptz default null)
returns table (
  id uuid,
  activity public.trip_activity,
  title text,
  note text,
  started_at timestamptz,
  ended_at timestamptz,
  moving_seconds integer,
  distance_m integer,
  elevation_gain_m integer,
  max_speed_mps real,
  visibility public.visibility
)
language sql
stable
security definer
set search_path = ''
as $$
  select t.id, t.activity, t.title, t.note, t.started_at, t.ended_at,
         t.moving_seconds, t.distance_m, t.elevation_gain_m, t.max_speed_mps, t.visibility
    from public.trips t
   where t.owner_id = p_user
     and t.deleted_at is null
     and (p_before is null or t.started_at < p_before)
     and private.can_view(auth.uid(), t.owner_id, t.visibility)
   order by t.started_at desc
   limit least(greatest(p_limit, 1), 100);
$$;

-- Места человека, которые видит зритель. Форма — как у places_in_bbox: у чужого приблизительного
-- места — смещённый центр и радиус, настоящая точка — никогда.
create function public.user_places(p_user uuid, p_limit integer default 100)
returns table (
  id uuid,
  owner_id uuid,
  type public.place_type,
  name text,
  lon double precision,
  lat double precision,
  approximate boolean,
  radius_m integer,
  visibility public.visibility,
  status public.place_status,
  is_own boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.owner_id, p.type, p.name,
         extensions.st_x(case when f.fuzzed then p.approx_center else p.geom end),
         extensions.st_y(case when f.fuzzed then p.approx_center else p.geom end),
         f.fuzzed,
         case when f.fuzzed then private.approx_radius_m() else 0 end,
         p.visibility, p.status,
         p.owner_id = auth.uid()
    from public.places p
    cross join lateral (
      select (p.approximate and p.owner_id is distinct from auth.uid()) as fuzzed
    ) f
   where p.owner_id = p_user
     and p.deleted_at is null
     and (p.status = 'published' or p.owner_id = auth.uid())
     and private.can_view(auth.uid(), p.owner_id, p.visibility)
   order by p.created_at desc
   limit least(greatest(p_limit, 1), 200);
$$;

-- Итоги человека по тому, что видит зритель: поездки, километры, места, уловы, друзья.
create function public.user_stats(p_user uuid)
returns table (
  trips_count integer,
  distance_m bigint,
  places_count integer,
  catches_count bigint,
  friends_count integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    (select count(*) from public.trips t
      where t.owner_id = p_user and t.deleted_at is null
        and private.can_view(auth.uid(), t.owner_id, t.visibility))::integer,
    (select coalesce(sum(t.distance_m), 0) from public.trips t
      where t.owner_id = p_user and t.deleted_at is null
        and private.can_view(auth.uid(), t.owner_id, t.visibility))::bigint,
    (select count(*) from public.places p
      where p.owner_id = p_user and p.deleted_at is null
        and (p.status = 'published' or p.owner_id = auth.uid())
        and private.can_view(auth.uid(), p.owner_id, p.visibility))::integer,
    (select coalesce(sum(k.count), 0) from public.catches k
      where k.owner_id = p_user and k.deleted_at is null
        and private.can_view(auth.uid(), k.owner_id, k.visibility))::bigint,
    (select count(*) from public.friendships f where f.user_id = p_user)::integer
   where auth.uid() is not null
     and not private.is_blocked(auth.uid(), p_user)
     and exists (select 1 from public.profiles where id = p_user);
$$;

-- RPC: лента друзей -------------------------------------------------------------------------------

-- Поездки, чекины-отчёты и новые места друзей, которые видит зритель, новые сверху.
-- Своих записей и записей не друзей в ленте нет. Следующая страница — с (at, id) последней записи.
-- kind: 'trip' (at — конец поездки), 'checkin' (at — время чекина), 'place' (at — создание места).
create function public.friends_feed(
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
  if viewer is null then
    raise exception 'auth required' using errcode = '28000';
  end if;

  return query
  with friends as (
    select f.friend_id as id from public.friendships f where f.user_id = viewer
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
              'elevation_gain_m', t.elevation_gain_m
            ) as data
       from public.trips t
       join friends fr on fr.id = t.owner_id
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
       join friends fr on fr.id = c.owner_id
       join public.places p on p.id = c.place_id
      where c.deleted_at is null
        and (c.at, c.id) < (before_at, before_id)
        and p.deleted_at is null
        and p.status = 'published'
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
       join friends fr on fr.id = p.owner_id
      where p.deleted_at is null
        and p.status = 'published'
        and (p.created_at, p.id) < (before_at, before_id)
        and private.can_view(viewer, p.owner_id, p.visibility)
      order by p.created_at desc, p.id desc
      limit n)
  )
  select i.kind, i.id, i.at, i.author_id, pr.username, pr.display_name, pr.avatar_path, i.data
    from items i
    join public.profiles pr on pr.id = i.author_id
   order by i.at desc, i.id desc
   limit n;
end;
$$;

revoke execute on function
  public.trip_view(uuid),
  public.trip_checkins(uuid),
  public.user_trips(uuid, integer, timestamptz),
  public.user_places(uuid, integer),
  public.user_stats(uuid),
  public.friends_feed(integer, timestamptz, uuid)
from public, anon;

grant execute on function
  public.trip_view(uuid),
  public.trip_checkins(uuid),
  public.user_trips(uuid, integer, timestamptz),
  public.user_places(uuid, integer),
  public.user_stats(uuid),
  public.friends_feed(integer, timestamptz, uuid)
to authenticated;
