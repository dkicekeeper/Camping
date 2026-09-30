-- Поездки с треком (M3a).
--
-- Трек — `LineStringZM`: долгота, широта, высота (м, 0 — если неизвестна) и время точки
-- (M — секунды Unix). Пишет телефон целиком после финиша поездки.
--
-- Поездки пока видит только автор: делиться ими (лента, зоны приватности у дома) — в M4.
-- Поле `visibility` заполняется уже сейчас, по умолчанию «только я».
-- Чекины привязываются к поездке по времени: чекин автора между началом и концом поездки.

create type public.trip_activity as enum ('fishing', 'camping', 'hiking', 'other');

create table public.trips (
  id                uuid primary key default gen_random_uuid(),
  owner_id          uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  activity          public.trip_activity not null default 'fishing',
  title             text not null check (char_length(title) between 1 and 100),
  note              text check (char_length(note) <= 2000),
  started_at        timestamptz not null,
  ended_at          timestamptz not null,
  moving_seconds    integer not null default 0 check (moving_seconds >= 0),
  distance_m        integer not null default 0 check (distance_m >= 0),
  elevation_gain_m  integer not null default 0 check (elevation_gain_m >= 0),
  max_speed_mps     real check (max_speed_mps >= 0),
  track             extensions.geometry(LineStringZM, 4326),
  visibility        public.visibility not null default 'private',
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz,
  check (ended_at >= started_at),
  check (ended_at - started_at <= interval '31 days')
);

create index trips_owner_idx on public.trips (owner_id, started_at desc);

-- Больше точек в треке не принимаем (≈ неделя записи раз в 5 секунд).
create function private.track_points_limit() returns integer
language sql immutable
set search_path = ''
as $$ select 150000 $$;

create function private.trips_before_write() returns trigger
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

  if new.track is not null
     and extensions.st_npoints(new.track) > private.track_points_limit() then
    raise exception 'track too long' using errcode = '54000';
  end if;

  new.updated_at := now();
  return new;
end;
$$;

create trigger trips_before_write before insert or update on public.trips
  for each row execute function private.trips_before_write();

alter table public.trips enable row level security;

revoke all on table public.trips from anon, authenticated;
grant select on table public.trips to authenticated;
grant insert (id, activity, title, note, started_at, ended_at, moving_seconds, distance_m,
              elevation_gain_m, max_speed_mps, track, visibility)
  on table public.trips to authenticated;
grant update (activity, title, note, visibility, deleted_at) on table public.trips to authenticated;

create policy "trips: читать свои" on public.trips
  for select to authenticated using (owner_id = (select auth.uid()));

create policy "trips: создавать свои" on public.trips
  for insert to authenticated with check (owner_id = (select auth.uid()));

create policy "trips: менять свои" on public.trips
  for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

-- RPC: чекины поездки ---------------------------------------------------------------------------

-- Свои чекины за время своей поездки: место (если его ещё видно), условия, заметка, уловы.
create function public.my_trip_checkins(p_trip uuid)
returns table (
  checkin_id uuid,
  at timestamptz,
  verified boolean,
  place_id uuid,
  place_name text,
  conditions jsonb,
  note text,
  catches jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id, c.at, c.verified, c.place_id,
         case when p.deleted_at is null and private.can_view(auth.uid(), p.owner_id, p.visibility)
              then p.name end,
         c.conditions, c.note,
         coalesce((
           select jsonb_agg(jsonb_build_object(
                    'id', k.id,
                    'species_id', k.species_id,
                    'count', k.count,
                    'released', k.released,
                    'weight_g', k.weight_g,
                    'length_mm', k.length_mm
                  ) order by k.at)
             from public.catches k
            where k.checkin_id = c.id and k.deleted_at is null
         ), '[]'::jsonb)
    from public.trips t
    join public.checkins c
      on c.owner_id = t.owner_id
     and c.at between t.started_at and t.ended_at
     and c.deleted_at is null
    join public.places p on p.id = c.place_id
   where t.id = p_trip
     and t.owner_id = auth.uid()
     and t.deleted_at is null
   order by c.at;
$$;

revoke execute on function public.my_trip_checkins(uuid) from public;
grant execute on function public.my_trip_checkins(uuid) to authenticated;
