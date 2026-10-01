-- Вкладка «Места» (M8): сохранённые места, подборки и поиск.
--
-- Приватность — как у places_in_bbox и place_card:
--  * отдаются только места, которые зритель видит (private.can_view, опубликованные или свои);
--  * у чужого приблизительного места — approx_center и радиус, расстояние и сортировка «рядом» —
--    тоже по approx_center, иначе настоящую точку можно найти, двигая «мою позицию»;
--  * счётчики и «свежие отчёты» строятся только из чекинов, видимых зрителю; фото — только видимые
--    (private.media_visible); «где были друзья» — только друзья, чьи чекины зритель видит;
--  * «Популярные» — только публичные места; в рейтинг идут публичные подтверждённые чекины, отзывы
--    и сохранения за 30 дней (сами числа клиенту не отдаются).
-- Ошибки: 22023 — неверные координаты или сортировка; P0002 — место не найдено (или не видно);
-- 54000 — слишком много сохранённых мест; 28000 — нужен вход.

-- Сохранённые места -----------------------------------------------------------------------------

create table public.saved_places (
  owner_id   uuid not null references public.profiles (id) on delete cascade,
  place_id   uuid not null references public.places (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (owner_id, place_id)
);

create index saved_places_place_idx on public.saved_places (place_id, created_at);

alter table public.saved_places enable row level security;

revoke all on table public.saved_places from anon, authenticated;
-- Пишется только через save_place; свои строки можно прочитать напрямую.
grant select on table public.saved_places to authenticated;

create policy "saved_places: читать свои" on public.saved_places
  for select to authenticated using (owner_id = (select auth.uid()));

create function private.saved_places_limit() returns integer
language sql immutable
set search_path = ''
as $$ select 1000 $$;

-- Подборки редакции -----------------------------------------------------------------------------
-- Ведёт редакция (Supabase Studio или миграции). Клиенту — только через RPC, с проверкой видимости.

create table public.place_collections (
  id         uuid primary key default gen_random_uuid(),
  slug       text not null unique check (slug ~ '^[a-z0-9_]{3,40}$'),
  -- {"ru": "…", "kk": "…", "en": "…"}
  title      jsonb not null check (jsonb_typeof(title) = 'object'),
  position   integer not null default 0,
  published  boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.place_collection_items (
  collection_id uuid not null references public.place_collections (id) on delete cascade,
  place_id      uuid not null references public.places (id) on delete cascade,
  position      integer not null default 0,
  primary key (collection_id, place_id)
);

create index place_collection_items_place_idx on public.place_collection_items (place_id);

alter table public.place_collections enable row level security;
alter table public.place_collection_items enable row level security;
revoke all on table public.place_collections, public.place_collection_items from anon, authenticated;

-- Карточка места в списке -------------------------------------------------------------------------

create type public.place_item as (
  id             uuid,
  type           public.place_type,
  name           text,
  lon            double precision,
  lat            double precision,
  approximate    boolean,
  radius_m       integer,
  visibility     public.visibility,
  is_own         boolean,
  is_editorial   boolean,
  -- Метры от переданной точки до показанной точки места; null — точку не передали.
  distance_m     integer,
  rating_avg     numeric,
  reviews_count  integer,
  -- Видимые зрителю чекины: за 30 дней и последний.
  reports_30d    integer,
  last_report_at timestamptz,
  -- Превью последнего видимого фото (путь в бакете media).
  photo_path     text,
  -- До трёх друзей с видимыми чекинами здесь: [{id, username, display_name, avatar_path}].
  friends        jsonb,
  saved          boolean
);

-- Точка «где я» или null. Неверные координаты — 22023.
create function private.viewer_point(p_lon double precision, p_lat double precision)
returns extensions.geometry
language plpgsql immutable
set search_path = ''
as $$
begin
  if p_lon is null and p_lat is null then
    return null;
  end if;
  if p_lon is null or p_lat is null
     or p_lon not between -180 and 180 or p_lat not between -90 and 90 then
    raise exception 'invalid point' using errcode = '22023';
  end if;
  return extensions.st_setsrid(extensions.st_makepoint(p_lon, p_lat), 4326);
end;
$$;

-- Видимые зрителю места и точка, которую ему можно показать (у чужих приблизительных — смещённая).
create function private.visible_places(p_viewer uuid)
returns table (
  id uuid,
  owner_id uuid,
  type public.place_type,
  name text,
  pt extensions.geometry,
  visibility public.visibility,
  created_at timestamptz
)
language sql stable
security definer
set search_path = ''
as $$
  select p.id, p.owner_id, p.type, p.name,
         case when p.approximate and p.owner_id is distinct from p_viewer
              then p.approx_center else p.geom end,
         p.visibility, p.created_at
    from public.places p
   where p.deleted_at is null
     and (p.status = 'published' or p.owner_id = p_viewer)
     and private.can_view(p_viewer, p.owner_id, p.visibility);
$$;

-- Популярность публичного места за 30 дней (без учёта расстояния):
-- чекин — 1, чекин с фото — 1.5, отзыв — 2, сохранение — 0.5. Только публичные подтверждённые чекины.
create function private.place_popularity(p_place uuid) returns numeric
language sql stable
security definer
set search_path = ''
as $$
  select coalesce((
           select sum(case when exists (
                             select 1 from public.media m
                              where m.checkin_id = c.id and m.deleted_at is null)
                           then 1.5 else 1.0 end)
             from public.checkins c
            where c.place_id = p_place
              and c.deleted_at is null
              and c.visibility = 'public'
              and c.verified
              and c.at > now() - interval '30 days'), 0)
       + 2.0 * (select count(*) from public.reviews r
                 where r.place_id = p_place and r.deleted_at is null
                   and r.created_at > now() - interval '30 days')
       + 0.5 * (select count(*) from public.saved_places s
                 where s.place_id = p_place and s.created_at > now() - interval '30 days');
$$;

-- Карточки мест для списка в заданном порядке (ord — позиция в p_ids). Невидимые пропускаются.
create function private.place_items(
  p_viewer uuid,
  p_ids uuid[],
  p_lon double precision,
  p_lat double precision
)
returns table (ord integer, item public.place_item)
language sql stable
security definer
set search_path = ''
as $$
  select i.ord::integer,
         row(
           p.id, p.type, p.name,
           extensions.st_x(s.pt), extensions.st_y(s.pt),
           s.fuzzed,
           case when s.fuzzed then private.approx_radius_m() else 0 end,
           p.visibility,
           p.owner_id is not distinct from p_viewer,
           p.owner_id = private.editorial_id(),
           case when h.pt is null then null
                else round(extensions.st_distance(s.pt::extensions.geography,
                                                  h.pt::extensions.geography))::integer end,
           rv.rating_avg, rv.reviews_count,
           rp.reports_30d, rp.last_report_at,
           ph.photo_path,
           coalesce(fr.friends, '[]'::jsonb),
           exists (select 1 from public.saved_places sp
                    where sp.owner_id = p_viewer and sp.place_id = p.id)
         )::public.place_item
    from unnest(p_ids) with ordinality as i (id, ord)
    join public.places p on p.id = i.id
    cross join (select private.viewer_point(p_lon, p_lat) as pt) h
    cross join lateral (
      select (p.approximate and p.owner_id is distinct from p_viewer) as fuzzed
    ) f
    cross join lateral (
      select case when f.fuzzed then p.approx_center else p.geom end as pt, f.fuzzed
    ) s
    -- Отзывы бывают только у публичных мест; авторы, с которыми есть блокировка, не считаются.
    cross join lateral (
      select round(avg(r.rating), 1) as rating_avg, count(*)::integer as reviews_count
        from public.reviews r
       where r.place_id = p.id
         and r.deleted_at is null
         and p.visibility = 'public'
         and (p_viewer is null or not private.is_blocked(p_viewer, r.owner_id))
    ) rv
    cross join lateral (
      select (count(*) filter (where c.at > now() - interval '30 days'))::integer as reports_30d,
             max(c.at) as last_report_at
        from public.checkins c
       where c.place_id = p.id
         and c.deleted_at is null
         and private.can_view(p_viewer, c.owner_id, c.visibility)
    ) rp
    left join lateral (
      select m.owner_id::text || '/' || m.id::text || '_thumb.jpg' as photo_path
        from public.media m
        join public.checkins c on c.id = m.checkin_id
       where c.place_id = p.id
         and c.deleted_at is null
         and m.deleted_at is null
         and private.media_visible(p_viewer, m.id)
       order by c.at desc, m.created_at desc, m.id
       limit 1
    ) ph on true
    left join lateral (
      select jsonb_agg(jsonb_build_object(
               'id', x.id, 'username', x.username,
               'display_name', x.display_name, 'avatar_path', x.avatar_path
             ) order by x.last_at desc) as friends
        from (
          select pr.id, pr.username, pr.display_name, pr.avatar_path, max(c.at) as last_at
            from public.checkins c
            join public.friendships fs on fs.user_id = p_viewer and fs.friend_id = c.owner_id
            join public.profiles pr on pr.id = c.owner_id
           where c.place_id = p.id
             and c.deleted_at is null
             and private.can_view(p_viewer, c.owner_id, c.visibility)
           group by pr.id
           order by max(c.at) desc
           limit 3
        ) x
    ) fr on true
   where p.deleted_at is null
     and (p.status = 'published' or p.owner_id = p_viewer)
     and private.can_view(p_viewer, p.owner_id, p.visibility);
$$;

create function private.place_items_json(
  p_viewer uuid,
  p_ids uuid[],
  p_lon double precision,
  p_lat double precision
)
returns jsonb
language sql stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(i.item) order by i.ord), '[]'::jsonb)
    from private.place_items(p_viewer, p_ids, p_lon, p_lat) i;
$$;

-- Места подборки: видимые, по расстоянию от точки (если есть) или в порядке редакции.
create function private.collection_place_ids(
  p_collection uuid,
  p_viewer uuid,
  p_here extensions.geometry,
  p_limit integer
)
returns uuid[]
language sql stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(x.id order by x.rank), '{}')
    from (
      select v.id,
             row_number() over (
               order by case when p_here is null then 0
                             else extensions.st_distance(v.pt::extensions.geography,
                                                         p_here::extensions.geography) end,
                        ci.position, v.name, v.id) as rank
        from public.place_collection_items ci
        join private.visible_places(p_viewer) v on v.id = ci.place_id
       where ci.collection_id = p_collection
       order by rank
       limit p_limit
    ) x;
$$;

-- RPC ---------------------------------------------------------------------------------------------

-- Подборки вкладки «Места» одним ответом (по 10 мест):
-- {nearby, popular, friends, fresh, new: [place_item], recommended: [{id, slug, title, places}]}.
-- Без точки «Рядом» пустая, остальные — без расстояния; у гостя «Где были друзья» пустая.
create function public.places_discover(
  p_lon double precision default null,
  p_lat double precision default null
)
returns jsonb
language plpgsql stable
security definer
set search_path = ''
as $$
declare
  viewer uuid := auth.uid();
  here extensions.geometry := private.viewer_point(p_lon, p_lat);
  n constant integer := 10;
  nearby uuid[];
  popular uuid[];
  friends uuid[];
  fresh uuid[];
  newest uuid[];
  recommended jsonb;
begin
  -- Рядом: чужие видимые места по расстоянию до показанной точки.
  if here is not null then
    select array_agg(x.id order by x.dist, x.id) into nearby
      from (
        select v.id, extensions.st_distance(v.pt::extensions.geography,
                                            here::extensions.geography) as dist
          from private.visible_places(viewer) v
         where v.owner_id is distinct from viewer
         order by dist, v.id
         limit n
      ) x;
  end if;

  -- Популярные: публичные места с ненулевым рейтингом; чем дальше, тем ниже (вдвое — на 25 км).
  select array_agg(x.id order by x.rank desc, x.id) into popular
    from (
      select y.id, y.rank
        from (
          select v.id,
                 private.place_popularity(v.id)
                   / case when here is null then 1
                          else 1 + extensions.st_distance(v.pt::extensions.geography,
                                                          here::extensions.geography) / 25000 end
                   as rank
            from private.visible_places(viewer) v
           where v.visibility = 'public'
        ) y
       where y.rank > 0
       order by y.rank desc, y.id
       limit n
    ) x;

  -- Где были друзья: места с видимыми чекинами друзей, по свежести.
  if viewer is not null then
    select array_agg(x.place_id order by x.last_at desc, x.place_id) into friends
      from (
        select c.place_id, max(c.at) as last_at
          from public.checkins c
          join public.friendships fs on fs.user_id = viewer and fs.friend_id = c.owner_id
          join public.places p on p.id = c.place_id
         where c.deleted_at is null
           and p.deleted_at is null
           and p.status = 'published'
           and private.can_view(viewer, p.owner_id, p.visibility)
           and private.can_view(viewer, c.owner_id, c.visibility)
         group by c.place_id
         order by max(c.at) desc, c.place_id
         limit n
      ) x;
  end if;

  -- Свежие отчёты: места с видимыми чужими чекинами за 30 дней, по свежести.
  select array_agg(x.place_id order by x.last_at desc, x.place_id) into fresh
    from (
      select c.place_id, max(c.at) as last_at
        from public.checkins c
        join public.places p on p.id = c.place_id
       where c.deleted_at is null
         and c.at > now() - interval '30 days'
         and c.owner_id is distinct from viewer
         and p.deleted_at is null
         and p.status = 'published'
         and private.can_view(viewer, p.owner_id, p.visibility)
         and private.can_view(viewer, c.owner_id, c.visibility)
       group by c.place_id
       order by max(c.at) desc, c.place_id
       limit n
    ) x;

  -- Новые: чужие места за 90 дней (места редакции — в подборках, не здесь).
  select array_agg(x.id order by x.created_at desc, x.id) into newest
    from (
      select v.id, v.created_at
        from private.visible_places(viewer) v
       where v.owner_id is distinct from viewer
         and v.owner_id <> private.editorial_id()
         and v.created_at > now() - interval '90 days'
       order by v.created_at desc, v.id
       limit n
    ) x;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id,
           'slug', c.slug,
           'title', c.title,
           'places', private.place_items_json(
                       viewer, private.collection_place_ids(c.id, viewer, here, n), p_lon, p_lat)
         ) order by c.position, c.slug), '[]'::jsonb)
    into recommended
    from public.place_collections c
   where c.published
     and exists (
       select 1 from public.place_collection_items ci
         join private.visible_places(viewer) v on v.id = ci.place_id
        where ci.collection_id = c.id);

  return jsonb_build_object(
    'nearby', private.place_items_json(viewer, nearby, p_lon, p_lat),
    'popular', private.place_items_json(viewer, popular, p_lon, p_lat),
    'friends', private.place_items_json(viewer, friends, p_lon, p_lat),
    'fresh', private.place_items_json(viewer, fresh, p_lon, p_lat),
    'new', private.place_items_json(viewer, newest, p_lon, p_lat),
    'recommended', recommended
  );
end;
$$;

-- Поиск и полные списки: по названию (без учёта регистра и диакритики, с опечатками), по типам,
-- с сортировкой: distance | rating | fresh | popular | new | name | relevance.
-- По умолчанию: с запросом — relevance, без него — distance (если есть точка) или name.
create function public.places_search(
  p_query text default null,
  p_types public.place_type[] default null,
  p_sort text default null,
  p_lon double precision default null,
  p_lat double precision default null,
  p_limit integer default 30,
  p_offset integer default 0
)
returns setof public.place_item
language plpgsql stable
security definer
set search_path = ''
as $$
declare
  viewer uuid := auth.uid();
  here extensions.geometry := private.viewer_point(p_lon, p_lat);
  q text := nullif(btrim(coalesce(p_query, '')), '');
  needle text;
  sort text;
  ids uuid[];
begin
  if char_length(q) > 80 then
    raise exception 'query too long' using errcode = '22023';
  end if;
  sort := coalesce(p_sort, case when q is not null then 'relevance'
                                when here is not null then 'distance'
                                else 'name' end);
  if sort not in ('distance', 'rating', 'fresh', 'popular', 'new', 'name', 'relevance') then
    raise exception 'invalid sort' using errcode = '22023';
  end if;
  if sort = 'distance' and here is null then
    sort := 'name';
  end if;
  if q is not null then
    needle := extensions.unaccent(lower(q));
  end if;

  select array_agg(x.id order by x.rn) into ids
    from (
      select c.id,
             row_number() over (order by
               case when sort = 'distance'
                    then extensions.st_distance(c.pt::extensions.geography, here::extensions.geography) end,
               case when sort = 'rating' then c.rating end desc nulls last,
               case when sort = 'rating' then c.reviews end desc,
               case when sort = 'fresh' then c.last_at end desc nulls last,
               case when sort = 'popular' then c.popularity end desc,
               case when sort = 'new' then c.created_at end desc,
               case when sort = 'relevance' then c.relevance end desc,
               lower(c.name), c.id) as rn
        from (
          select v.id, v.name, v.pt, v.created_at,
                 case when sort = 'rating' then (
                   select avg(r.rating) from public.reviews r
                    where r.place_id = v.id and r.deleted_at is null and v.visibility = 'public'
                      and (viewer is null or not private.is_blocked(viewer, r.owner_id))) end as rating,
                 case when sort = 'rating' then (
                   select count(*) from public.reviews r
                    where r.place_id = v.id and r.deleted_at is null and v.visibility = 'public'
                      and (viewer is null or not private.is_blocked(viewer, r.owner_id))) end as reviews,
                 case when sort = 'fresh' then (
                   select max(ch.at) from public.checkins ch
                    where ch.place_id = v.id and ch.deleted_at is null
                      and private.can_view(viewer, ch.owner_id, ch.visibility)) end as last_at,
                 case when sort = 'popular' and v.visibility = 'public'
                      then private.place_popularity(v.id) else 0 end as popularity,
                 case when needle is null then 0
                      else (case when starts_with(extensions.unaccent(lower(v.name)), needle) then 2
                                 when strpos(extensions.unaccent(lower(v.name)), needle) > 0 then 1
                                 else 0 end)
                           + extensions.word_similarity(needle, extensions.unaccent(lower(v.name)))
                 end as relevance
            from private.visible_places(viewer) v
           where (p_types is null or cardinality(p_types) = 0 or v.type = any (p_types))
             and (needle is null
                  or strpos(extensions.unaccent(lower(v.name)), needle) > 0
                  or extensions.word_similarity(needle, extensions.unaccent(lower(v.name))) >= 0.5)
        ) c
       order by rn
       limit least(greatest(coalesce(p_limit, 30), 1), 100)
       offset greatest(coalesce(p_offset, 0), 0)
    ) x;

  return query
  select (i.item).*
    from private.place_items(viewer, ids, p_lon, p_lat) i
   order by i.ord;
end;
$$;

-- Сохранить место или убрать из сохранённых. Невидимое место сохранить нельзя (P0002).
create function public.save_place(p_place uuid, p_saved boolean) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  viewer uuid := auth.uid();
begin
  if viewer is null then
    raise exception 'auth required' using errcode = '28000';
  end if;
  if coalesce(p_saved, false) then
    if not exists (select 1 from private.visible_places(viewer) v where v.id = p_place) then
      raise exception 'place not found' using errcode = 'P0002';
    end if;
    perform pg_advisory_xact_lock(hashtext('saved_places:' || viewer::text));
    if not exists (select 1 from public.saved_places where owner_id = viewer and place_id = p_place)
       and (select count(*) from public.saved_places where owner_id = viewer)
           >= private.saved_places_limit() then
      raise exception 'too many saved places' using errcode = '54000';
    end if;
    insert into public.saved_places (owner_id, place_id) values (viewer, p_place)
      on conflict do nothing;
    return true;
  end if;
  delete from public.saved_places where owner_id = viewer and place_id = p_place;
  return false;
end;
$$;

-- Сохранённые места, свежие сверху. Место, которое больше не видно, в список не попадает.
create function public.my_saved_places(
  p_lon double precision default null,
  p_lat double precision default null
)
returns setof public.place_item
language plpgsql stable
security definer
set search_path = ''
as $$
declare
  viewer uuid := auth.uid();
begin
  if viewer is null then
    raise exception 'auth required' using errcode = '28000';
  end if;
  return query
  select (i.item).*
    from private.place_items(
           viewer,
           array(select s.place_id from public.saved_places s
                  where s.owner_id = viewer order by s.created_at desc, s.place_id),
           p_lon, p_lat) i
   order by i.ord;
end;
$$;

-- Все места подборки (до 100).
create function public.place_collection(
  p_collection uuid,
  p_lon double precision default null,
  p_lat double precision default null
)
returns setof public.place_item
language sql stable
security definer
set search_path = ''
as $$
  select (i.item).*
    from public.place_collections c
    cross join lateral private.place_items(
      auth.uid(),
      private.collection_place_ids(c.id, auth.uid(), private.viewer_point(p_lon, p_lat), 100),
      p_lon, p_lat) i
   where c.id = p_collection
     and c.published
   order by i.ord;
$$;

revoke execute on function
  public.places_discover(double precision, double precision),
  public.places_search(text, public.place_type[], text, double precision, double precision, integer, integer),
  public.place_collection(uuid, double precision, double precision),
  public.save_place(uuid, boolean),
  public.my_saved_places(double precision, double precision)
from public;

grant execute on function
  public.places_discover(double precision, double precision),
  public.places_search(text, public.place_type[], text, double precision, double precision, integer, integer),
  public.place_collection(uuid, double precision, double precision)
to anon, authenticated;

grant execute on function
  public.save_place(uuid, boolean),
  public.my_saved_places(double precision, double precision)
to authenticated;

-- Подборки редакции к бете: из мест @dalada, порядок — от Алматы.
-- Состав потом правит редакция в Studio (place_collection_items).

insert into public.place_collections (slug, title, position) values
  ('waters_near_almaty',
   '{"ru": "Водоёмы рядом с Алматы", "kk": "Алматы маңындағы су айдындары", "en": "Waters near Almaty"}',
   10),
  ('overnight', '{"ru": "Стоянки с ночёвкой", "kk": "Түнеуге болатын тұрақтар", "en": "Places to stay overnight"}', 20),
  ('springs', '{"ru": "Родники", "kk": "Бұлақтар", "en": "Springs"}', 30),
  ('sights', '{"ru": "Что посмотреть по дороге", "kk": "Жол бойындағы көрікті жерлер", "en": "Sights on the way"}', 40),
  ('paid_and_tackle',
   '{"ru": "Платники и снасти", "kk": "Ақылы тоғандар мен балық аулау құралдары", "en": "Paid ponds and tackle shops"}',
   50);

insert into public.place_collection_items (collection_id, place_id, position)
select c.id, p.id,
       row_number() over (
         partition by c.id
         order by extensions.st_distance(
                    p.geom::extensions.geography,
                    extensions.st_setsrid(extensions.st_makepoint(76.9286, 43.2567), 4326)::extensions.geography),
                  p.id)
  from public.place_collections c
  join public.places p
    on p.owner_id = private.editorial_id()
   and p.deleted_at is null
   and p.status = 'published'
   and p.visibility = 'public'
   and case c.slug
         when 'waters_near_almaty' then
           p.type in ('water_body', 'fishing_spot', 'paid_pond')
           and extensions.st_dwithin(
                 p.geom::extensions.geography,
                 extensions.st_setsrid(extensions.st_makepoint(76.9286, 43.2567), 4326)::extensions.geography,
                 120000)
         when 'overnight' then p.type in ('campsite', 'base')
         when 'springs' then p.type = 'spring'
         when 'sights' then p.type = 'landmark'
         when 'paid_and_tackle' then p.type in ('paid_pond', 'tackle_shop')
         else false
       end;
