-- Исправление: у гостя (без входа) `is_own` было null вместо false.
--
-- `owner_id = auth.uid()` для гостя даёт null (auth.uid() пустой), а приложение ждёт true/false —
-- у гостя не разбирались места на карте, карточка места и отчёты. Функции те же, меняется только
-- вычисление `is_own`: `is not distinct from` даёт false, когда зрителя нет.

create or replace function public.places_in_bbox(
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
         p.owner_id is not distinct from viewer
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

create or replace function public.place_card(p_id uuid)
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
         p.owner_id is not distinct from auth.uid(),
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

create or replace function public.place_reports(p_place uuid, p_limit integer default 20)
returns table (
  checkin_id uuid,
  author_id uuid,
  author_username text,
  author_display_name text,
  at timestamptz,
  verified boolean,
  conditions jsonb,
  note text,
  is_own boolean,
  catches jsonb,
  media jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id, c.owner_id, pr.username, pr.display_name, c.at, c.verified, c.conditions, c.note,
         c.owner_id is not distinct from auth.uid(),
         coalesce((
           select jsonb_agg(jsonb_build_object(
                    'id', k.id,
                    'species_id', k.species_id,
                    'count', k.count,
                    'released', k.released,
                    'weight_g', case when k.hide_size and k.owner_id is distinct from auth.uid() then null else k.weight_g end,
                    'length_mm', case when k.hide_size and k.owner_id is distinct from auth.uid() then null else k.length_mm end
                  ) order by k.at)
             from public.catches k
            where k.checkin_id = c.id
              and k.deleted_at is null
              and private.can_view(auth.uid(), k.owner_id, k.visibility)
         ), '[]'::jsonb),
         coalesce((
           select jsonb_agg(jsonb_build_object(
                    'id', m.id,
                    'catch_id', m.catch_id,
                    'path', m.storage_path,
                    'thumb_path', m.owner_id::text || '/' || m.id::text || '_thumb.jpg',
                    'width', m.width,
                    'height', m.height
                  ) order by m.created_at, m.id)
             from public.media m
            where m.checkin_id = c.id
              and private.media_visible(auth.uid(), m.id)
         ), '[]'::jsonb)
    from public.checkins c
    join public.places p on p.id = c.place_id
    join public.profiles pr on pr.id = c.owner_id
   where c.place_id = p_place
     and c.deleted_at is null
     and p.deleted_at is null
     and (p.status = 'published' or p.owner_id = auth.uid())
     and private.can_view(auth.uid(), p.owner_id, p.visibility)
     and private.can_view(auth.uid(), c.owner_id, c.visibility)
   order by c.at desc
   limit least(greatest(p_limit, 1), 100);
$$;
