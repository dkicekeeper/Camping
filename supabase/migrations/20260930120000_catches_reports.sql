-- Веха M2a: справочник рыб, уловы, свежие отчёты на странице места, «Мои уловы».
--
-- Приватность: уловы, как чекины, не видимее места; вес и длину автор может скрыть
-- (hide_size) — другие видят только вид и количество. Координат в отчётах нет.

-- Справочник рыб ---------------------------------------------------------------------------

create table public.fish_species (
  id            text primary key check (id ~ '^[a-z_]{2,40}$'),
  name_ru       text not null,
  name_kk       text not null,
  name_en       text not null,
  name_latin    text,
  -- Промысловая мера (минимальная длина), см. Заполняется по Правилам рыболовства РК.
  min_length_cm integer check (min_length_cm > 0),
  sort_order    integer not null default 100
);

comment on table public.fish_species is
  'Виды рыб региона. Казахские названия — на вычитку специалистом.';

alter table public.fish_species enable row level security;
revoke all on table public.fish_species from anon, authenticated;
grant select on table public.fish_species to anon, authenticated;
create policy "fish_species: читать всем" on public.fish_species
  for select to anon, authenticated using (true);

insert into public.fish_species (id, name_ru, name_kk, name_en, name_latin, sort_order) values
  ('common_carp',    'Сазан, карп',       'Сазан, тұқы',         'Common carp',       'Cyprinus carpio',               10),
  ('zander',         'Судак',             'Көксерке',            'Zander',            'Sander lucioperca',             20),
  ('asp',            'Жерех',             'Ақмарқа',             'Asp',               'Leuciscus aspius',              30),
  ('wels_catfish',   'Сом',               'Жайын',               'Wels catfish',      'Silurus glanis',                40),
  ('snakehead',      'Змееголов',         'Жыланбас',            'Northern snakehead','Channa argus',                  50),
  ('pike',           'Щука',              'Шортан',              'Northern pike',     'Esox lucius',                   60),
  ('perch',          'Окунь',             'Алабұға',             'European perch',    'Perca fluviatilis',             70),
  ('balkhash_perch', 'Балхашский окунь',  'Балқаш алабұғасы',    'Balkhash perch',    'Perca schrenkii',               80),
  ('bream',          'Лещ',               'Тыран',               'Common bream',      'Abramis brama',                 90),
  ('crucian_carp',   'Карась',            'Мөңке',               'Prussian carp',     'Carassius gibelio',            100),
  ('silver_carp',    'Толстолобик',       'Дөңмаңдай',           'Silver carp',       'Hypophthalmichthys molitrix',  110),
  ('grass_carp',     'Белый амур',        'Ақ амур',             'Grass carp',        'Ctenopharyngodon idella',      120),
  ('marinka',        'Маринка',           'Қарабалық',           'Marinka',           'Schizothorax argentatus',      130),
  ('rainbow_trout',  'Форель',            'Бахтах',              'Rainbow trout',     'Oncorhynchus mykiss',          140),
  ('roach',          'Плотва',            'Торта',               'Roach',             'Rutilus rutilus',              150),
  ('tench',          'Линь',              'Оңғақ',               'Tench',             'Tinca tinca',                  160),
  ('other',          'Другая рыба',       'Басқа балық',         'Other fish',        null,                           999);

-- Уловы ------------------------------------------------------------------------------------

create type public.fishing_method as enum ('spinning', 'feeder', 'float', 'fly', 'bottom', 'ice', 'other');

create table public.catches (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  checkin_id  uuid references public.checkins (id) on delete set null,
  place_id    uuid references public.places (id) on delete set null,
  species_id  text not null references public.fish_species (id),
  weight_g    integer check (weight_g between 1 and 200000),
  length_mm   integer check (length_mm between 1 and 3000),
  count       integer not null default 1 check (count between 1 and 1000),
  method      public.fishing_method,
  bait        text check (char_length(bait) <= 100),
  released    boolean not null default false,
  at          timestamptz not null default now(),
  visibility  public.visibility not null default 'friends',
  hide_size   boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

create index catches_owner_idx on public.catches (owner_id, at desc);
create index catches_checkin_idx on public.catches (checkin_id);
create index catches_place_idx on public.catches (place_id, at desc);

create function private.catches_before_write() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  ch public.checkins;
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
    new.checkin_id := old.checkin_id;
  end if;

  if new.owner_id is null then
    raise exception 'auth required' using errcode = '28000';
  end if;

  -- Улов в чекине: чекин должен быть своим, место берём из чекина.
  if new.checkin_id is not null then
    select * into ch from public.checkins where id = new.checkin_id;
    if not found or ch.owner_id <> new.owner_id or ch.deleted_at is not null then
      raise exception 'checkin not found' using errcode = 'P0002';
    end if;
    new.place_id := ch.place_id;
  end if;

  -- Улов в месте: место должно быть видно автору; улов не видимее места.
  if new.place_id is not null then
    select * into pl from public.places where id = new.place_id;
    if not found
       or pl.deleted_at is not null
       or (pl.status <> 'published' and pl.owner_id <> new.owner_id)
       or not private.can_view(new.owner_id, pl.owner_id, pl.visibility) then
      raise exception 'place not found' using errcode = 'P0002';
    end if;
    if pl.visibility = 'private' then
      new.visibility := 'private';
    elsif pl.visibility = 'friends' and new.visibility = 'public' then
      new.visibility := 'friends';
    end if;
  end if;

  new.updated_at := now();
  return new;
end;
$$;

create trigger catches_before_write before insert or update on public.catches
  for each row execute function private.catches_before_write();

alter table public.catches enable row level security;

revoke all on table public.catches from anon, authenticated;
grant select on table public.catches to authenticated;
grant insert (id, checkin_id, place_id, species_id, weight_g, length_mm, count, method, bait,
              released, at, visibility, hide_size)
  on table public.catches to authenticated;
grant update (species_id, weight_g, length_mm, count, method, bait, released, at, visibility,
              hide_size, deleted_at)
  on table public.catches to authenticated;

create policy "catches: читать свои" on public.catches
  for select to authenticated using (owner_id = (select auth.uid()));

create policy "catches: создавать свои" on public.catches
  for insert to authenticated with check (owner_id = (select auth.uid()));

create policy "catches: менять свои" on public.catches
  for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

-- RPC: свежие отчёты места -----------------------------------------------------------------

-- Чекины в месте, которые видит зритель, с уловами. Без координат.
-- Вес и длина скрытого (hide_size) чужого улова не отдаются.
create function public.place_reports(p_place uuid, p_limit integer default 20)
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
  catches jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id, c.owner_id, pr.username, pr.display_name, c.at, c.verified, c.conditions, c.note,
         c.owner_id = auth.uid(),
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

-- RPC: мои уловы ---------------------------------------------------------------------------

-- Свои уловы с названием места (если место всё ещё видно автору).
create function public.my_catches(p_limit integer default 50)
returns table (
  id uuid,
  species_id text,
  weight_g integer,
  length_mm integer,
  count integer,
  released boolean,
  at timestamptz,
  visibility public.visibility,
  place_id uuid,
  place_name text
)
language sql
stable
security definer
set search_path = ''
as $$
  select k.id, k.species_id, k.weight_g, k.length_mm, k.count, k.released, k.at, k.visibility,
         k.place_id,
         case when p.id is not null
                   and p.deleted_at is null
                   and private.can_view(auth.uid(), p.owner_id, p.visibility)
              then p.name end
    from public.catches k
    left join public.places p on p.id = k.place_id
   where k.owner_id = auth.uid()
     and k.deleted_at is null
   order by k.at desc
   limit least(greatest(p_limit, 1), 200);
$$;

revoke execute on function public.place_reports(uuid, integer), public.my_catches(integer) from public;
grant execute on function public.place_reports(uuid, integer) to anon, authenticated;
grant execute on function public.my_catches(integer) to authenticated;
