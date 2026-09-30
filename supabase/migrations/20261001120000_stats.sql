-- Статистика профиля (M3b): поездки, километры, время в движении, дни на природе, уловы, места.
--
-- Только свои данные: функция работает от имени пользователя (security invoker), таблицы
-- отдают ему только его строки. «День на природе» — календарный день по времени Алматы, в который
-- была поездка (многодневная поездка — каждый её день) или чекин.

create function public.my_stats()
returns table (
  trips_count integer,
  distance_m bigint,
  moving_seconds bigint,
  days_outdoors integer,
  checkins_count integer,
  catches_count bigint,
  species_count integer,
  places_count integer
)
language sql
stable
security invoker
set search_path = ''
as $$
  with me as (
    select auth.uid() as id
  ),
  my_trips as (
    select t.* from public.trips t, me
     where t.owner_id = me.id and t.deleted_at is null
  ),
  my_checkins as (
    select c.* from public.checkins c, me
     where c.owner_id = me.id and c.deleted_at is null
  ),
  my_catches as (
    select k.* from public.catches k, me
     where k.owner_id = me.id and k.deleted_at is null
  ),
  days as (
    select generate_series(
             (t.started_at at time zone 'Asia/Almaty')::date,
             (t.ended_at at time zone 'Asia/Almaty')::date,
             interval '1 day'
           )::date as day
      from my_trips t
    union
    select (c.at at time zone 'Asia/Almaty')::date from my_checkins c
  )
  select
    (select count(*) from my_trips)::integer,
    (select coalesce(sum(distance_m), 0) from my_trips)::bigint,
    (select coalesce(sum(moving_seconds), 0) from my_trips)::bigint,
    (select count(*) from days)::integer,
    (select count(*) from my_checkins)::integer,
    (select coalesce(sum(count), 0) from my_catches)::bigint,
    (select count(distinct species_id) from my_catches where species_id <> 'other')::integer,
    (select count(*) from public.places p, me where p.owner_id = me.id and p.deleted_at is null)::integer;
$$;

revoke execute on function public.my_stats() from public;
grant execute on function public.my_stats() to authenticated;
