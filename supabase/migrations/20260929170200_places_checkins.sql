-- Места и чекины.
--
-- Приватность (docs/03-architecture/02-backend.md, «Приватность в базе»):
--  * таблицы с координатами напрямую отдают только свои строки;
--  * чужие места читаются через places_in_bbox / place_card, которые применяют
--    private.can_view и огрубление координат;
--  * у приблизительного места показывается центр со СТАБИЛЬНЫМ смещением (approx_center),
--    который создаётся один раз при записи точки — иначе точку можно найти усреднением;
--  * фильтр по области карты для чужих приблизительных мест идёт по approx_center,
--    а не по настоящей точке — иначе точку можно найти, сужая область.

create type public.place_type as enum (
  'fishing_spot',  -- точка ловли
  'water_body',    -- водоём
  'campsite',      -- стоянка / кемпинг
  'paid_pond',     -- платник
  'base',          -- база отдыха
  'parking',       -- съезд / парковка
  'spring',        -- родник
  'tackle_shop',   -- снасти и наживка
  'landmark'       -- достопримечательность
);

create type public.place_status as enum ('pending', 'published', 'hidden');

-- Радиус круга приблизительного места, метры.
create function private.approx_radius_m() returns integer
language sql immutable
set search_path = ''
as $$ select 1000 $$;

create table public.places (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  type          public.place_type not null,
  name          text not null check (char_length(name) between 1 and 80),
  description   text check (char_length(description) <= 2000),
  geom          extensions.geometry(Point, 4326) not null,
  access_point  extensions.geometry(Point, 4326),
  attributes    jsonb not null default '{}'::jsonb check (jsonb_typeof(attributes) = 'object'),
  visibility    public.visibility not null,
  approximate   boolean not null default false,
  approx_center extensions.geometry(Point, 4326) not null,
  status        public.place_status not null default 'published',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);

create index places_geom_idx on public.places using gist (geom);
create index places_owner_idx on public.places (owner_id);

comment on column public.places.approx_center is
  'Стабильно смещённый центр для приблизительного показа. Выставляет триггер; клиенту не отдаётся.';

-- Стабильно смещённая точка: случайное направление, расстояние 20–80% радиуса.
-- Круг радиуса approx_radius_m() вокруг неё всегда содержит настоящую точку.
create function private.random_offset_point(p extensions.geometry) returns extensions.geometry
language sql volatile
set search_path = ''
as $$
  select extensions.st_setsrid(
    extensions.st_project(
      p::extensions.geography,
      private.approx_radius_m() * (0.2 + random() * 0.6),
      random() * 2 * pi()
    )::extensions.geometry,
    4326
  );
$$;

-- Запрос из приложения (роль authenticated) или служебный (миграции, начальные данные,
-- модератор в Supabase Studio / service_role). Клиентские ограничения — только для первого.
create function private.is_client_request() returns boolean
language sql stable
set search_path = ''
as $$ select coalesce(auth.role(), '') in ('authenticated', 'anon') $$;

create function private.places_before_write() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  client boolean := private.is_client_request();
  published_public integer;
begin
  if tg_op = 'INSERT' then
    if client then
      new.owner_id := auth.uid();
    end if;
    new.created_at := now();
    new.approx_center := private.random_offset_point(new.geom);
  else
    new.owner_id := old.owner_id;
    new.created_at := old.created_at;
    if not extensions.st_equals(new.geom, old.geom) then
      new.approx_center := private.random_offset_point(new.geom);
    else
      new.approx_center := old.approx_center;
    end if;
    if client then
      new.status := old.status;
    end if;
  end if;

  if new.owner_id is null then
    raise exception 'auth required' using errcode = '28000';
  end if;

  if client then
    -- Новое публичное место (или ставшее публичным) проходит модерацию, пока у автора
    -- меньше 3 опубликованных публичных мест. Подтверждение телефона снимет это правило.
    if new.visibility = 'public'
       and (tg_op = 'INSERT' or old.visibility <> 'public')
       and new.status <> 'hidden' then
      select count(*) into published_public
        from public.places
       where owner_id = new.owner_id
         and visibility = 'public'
         and status = 'published'
         and deleted_at is null;
      new.status := case when published_public >= 3 then 'published' else 'pending' end;
    elsif tg_op = 'INSERT' then
      new.status := 'published';
    end if;
  end if;

  new.updated_at := now();
  return new;
end;
$$;

create trigger places_before_write before insert or update on public.places
  for each row execute function private.places_before_write();

alter table public.places enable row level security;

revoke all on table public.places from anon, authenticated;
grant select on table public.places to authenticated;
grant insert (id, type, name, description, geom, access_point, attributes, visibility, approximate)
  on table public.places to authenticated;
grant update (type, name, description, geom, access_point, attributes, visibility, approximate, deleted_at)
  on table public.places to authenticated;

create policy "places: читать свои" on public.places
  for select to authenticated using (owner_id = (select auth.uid()));

create policy "places: создавать свои" on public.places
  for insert to authenticated with check (owner_id = (select auth.uid()));

create policy "places: менять свои" on public.places
  for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

-- Чекины -------------------------------------------------------------------------------------

create table public.checkins (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  place_id    uuid not null references public.places (id) on delete cascade,
  at          timestamptz not null default now(),
  geom        extensions.geometry(Point, 4326),
  verified    boolean not null default false,
  conditions  jsonb not null default '{}'::jsonb check (jsonb_typeof(conditions) = 'object'),
  note        text check (char_length(note) <= 2000),
  visibility  public.visibility not null default 'friends',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

create index checkins_place_idx on public.checkins (place_id, at desc);
create index checkins_owner_idx on public.checkins (owner_id, at desc);

-- Радиус подтверждённого чекина, метры.
create function private.checkin_radius_m() returns integer
language sql immutable
set search_path = ''
as $$ select 500 $$;

create function private.checkins_before_write() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  pl public.places;
begin
  if tg_op = 'INSERT' then
    if private.is_client_request() then
      new.owner_id := auth.uid();
    end if;
    new.created_at := now();
  else
    new.owner_id := old.owner_id;
    new.created_at := old.created_at;
    new.place_id := old.place_id;
  end if;

  if new.owner_id is null then
    raise exception 'auth required' using errcode = '28000';
  end if;

  select * into pl from public.places where id = new.place_id;
  if not found
     or pl.deleted_at is not null
     or (pl.status <> 'published' and pl.owner_id <> new.owner_id)
     or not private.can_view(new.owner_id, pl.owner_id, pl.visibility) then
    raise exception 'place not found' using errcode = 'P0002';
  end if;

  -- Чекин не может быть видимее места.
  if pl.visibility = 'private' then
    new.visibility := 'private';
  elsif pl.visibility = 'friends' and new.visibility = 'public' then
    new.visibility := 'friends';
  end if;

  -- Подтверждён, если сделан «сейчас» и рядом с местом. Задним числом — не подтверждён.
  new.verified := new.geom is not null
    and new.at > now() - interval '1 hour'
    and new.at < now() + interval '5 minutes'
    and extensions.st_dwithin(
          new.geom::extensions.geography,
          pl.geom::extensions.geography,
          private.checkin_radius_m());

  new.updated_at := now();
  return new;
end;
$$;

create trigger checkins_before_write before insert or update on public.checkins
  for each row execute function private.checkins_before_write();

alter table public.checkins enable row level security;

revoke all on table public.checkins from anon, authenticated;
grant select on table public.checkins to authenticated;
grant insert (id, place_id, at, geom, conditions, note, visibility) on table public.checkins to authenticated;
grant update (at, geom, conditions, note, visibility, deleted_at) on table public.checkins to authenticated;

create policy "checkins: читать свои" on public.checkins
  for select to authenticated using (owner_id = (select auth.uid()));

create policy "checkins: создавать свои" on public.checkins
  for insert to authenticated with check (owner_id = (select auth.uid()));

create policy "checkins: менять свои" on public.checkins
  for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

-- RPC: чтение мест ---------------------------------------------------------------------------

-- Места в прямоугольнике карты с учётом видимости и огрубления.
-- Для чужого приблизительного места отдаётся approx_center и radius_m; настоящая точка — никогда.
create function public.places_in_bbox(
  min_lon double precision,
  min_lat double precision,
  max_lon double precision,
  max_lat double precision,
  max_results integer default 500
)
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
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  viewer uuid := auth.uid();
  env extensions.geometry;
  -- Запас для индексного предфильтра: показанная точка отстоит от настоящей меньше чем на
  -- approx_radius_m (1 км ≈ 0.009° широты, ≈ 0.013° долготы на 45° с.ш.).
  margin constant double precision := 0.02;
begin
  if min_lon is null or min_lat is null or max_lon is null or max_lat is null
     or min_lon >= max_lon or min_lat >= max_lat
     or max_lon - min_lon > 10 or max_lat - min_lat > 10 then
    raise exception 'invalid bbox' using errcode = '22023';
  end if;

  env := extensions.st_makeenvelope(min_lon, min_lat, max_lon, max_lat, 4326);

  return query
  select p.id, p.owner_id, p.type, p.name,
         extensions.st_x(s.pt), extensions.st_y(s.pt),
         s.fuzzed,
         case when s.fuzzed then private.approx_radius_m() else 0 end,
         p.visibility, p.status,
         p.owner_id = viewer
    from public.places p
    cross join lateral (
      select (p.approximate and p.owner_id is distinct from viewer) as fuzzed
    ) f
    cross join lateral (
      select case when f.fuzzed then p.approx_center else p.geom end as pt, f.fuzzed
    ) s
   where extensions.st_intersects(p.geom, extensions.st_expand(env, margin))
     and extensions.st_intersects(s.pt, env)
     and p.deleted_at is null
     and (p.status = 'published' or p.owner_id = viewer)
     and private.can_view(viewer, p.owner_id, p.visibility)
   limit least(greatest(max_results, 1), 1000);
end;
$$;

-- Карточка места. Нет доступа — пустой результат (не отличаем «нет» от «не видно»).
create function public.place_card(p_id uuid)
returns table (
  id uuid,
  owner_id uuid,
  owner_username text,
  type public.place_type,
  name text,
  description text,
  lon double precision,
  lat double precision,
  approximate boolean,
  radius_m integer,
  access_lon double precision,
  access_lat double precision,
  attributes jsonb,
  visibility public.visibility,
  status public.place_status,
  is_own boolean,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.owner_id, pr.username, p.type, p.name, p.description,
         extensions.st_x(case when fuzzed then p.approx_center else p.geom end),
         extensions.st_y(case when fuzzed then p.approx_center else p.geom end),
         fuzzed,
         case when fuzzed then private.approx_radius_m() else 0 end,
         -- Точка подъезда выдаёт настоящее место — у огрублённых не показываем.
         case when fuzzed then null else extensions.st_x(p.access_point) end,
         case when fuzzed then null else extensions.st_y(p.access_point) end,
         p.attributes, p.visibility, p.status,
         p.owner_id = auth.uid(),
         p.created_at
    from public.places p
    join public.profiles pr on pr.id = p.owner_id
    cross join lateral (
      select (p.approximate and p.owner_id is distinct from auth.uid()) as fuzzed
    ) f
   where p.id = p_id
     and p.deleted_at is null
     and (p.status = 'published' or p.owner_id = auth.uid())
     and private.can_view(auth.uid(), p.owner_id, p.visibility);
$$;

revoke execute on function
  public.places_in_bbox(double precision, double precision, double precision, double precision, integer),
  public.place_card(uuid)
from public;

grant execute on function
  public.places_in_bbox(double precision, double precision, double precision, double precision, integer),
  public.place_card(uuid)
to anon, authenticated;
