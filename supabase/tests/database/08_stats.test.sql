-- Статистика профиля: только свои данные, дни на природе по времени Алматы.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(7);

create function pg_temp.act_as(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('33333333-3333-3333-3333-333333333333', 's@test.local');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.places (id, type, name, geom, visibility) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'fishing_spot', 'Моё', 'SRID=4326;POINT(77.00 43.90)', 'private'),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'campsite', 'Стоянка', 'SRID=4326;POINT(77.10 43.90)', 'private');

-- Поездки A: однодневная и с ночёвкой (27–29 сентября по Алматы), одна удалённая.
insert into public.trips (title, activity, started_at, ended_at, distance_m, moving_seconds) values
  ('Рыбалка', 'fishing', '2026-09-20 01:00+00', '2026-09-20 10:00+00', 12000, 14400),
  ('Кемпинг', 'camping', '2026-09-27 04:00+00', '2026-09-29 08:00+00', 30500, 21600);
insert into public.trips (id, title, started_at, ended_at, distance_m) values
  ('77777777-0000-0000-0000-000000000009', 'Удалённая', '2026-09-10 04:00+00', '2026-09-10 08:00+00', 99999);
update public.trips set deleted_at = now() where id = '77777777-0000-0000-0000-000000000009';

-- Чекины: в день поездки (не добавляет день) и отдельный — 22 сентября 20:00 UTC = 23-е в Алматы.
insert into public.checkins (id, place_id, at) values
  ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', '2026-09-20 05:00+00'),
  ('cccccccc-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001', '2026-09-22 20:00+00');
insert into public.catches (checkin_id, species_id, count) values
  ('cccccccc-0000-0000-0000-000000000001', 'pike', 2),
  ('cccccccc-0000-0000-0000-000000000001', 'perch', 5),
  ('cccccccc-0000-0000-0000-000000000002', 'pike', 1),
  ('cccccccc-0000-0000-0000-000000000002', 'other', 3);

select is((select trips_count from public.my_stats()), 2, 'удалённая поездка не считается');
select is((select distance_m from public.my_stats()), 42500::bigint, 'километры — сумма поездок');
select is((select moving_seconds from public.my_stats()), 36000::bigint, 'время в движении — сумма поездок');
select is((select days_outdoors from public.my_stats()), 5,
  'дни на природе: 20-е, 23-е (чекин вечером по Алматы) и 27–29-е');
select ok((select catches_count = 11 and species_count = 2 and checkins_count = 2 and places_count = 2
             from public.my_stats()),
  'уловы — по количеству рыб, виды без «другого», чекины и места');

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select ok((select trips_count = 0 and distance_m = 0 and days_outdoors = 0 and catches_count = 0
             from public.my_stats()),
  'у другого пользователя — только его нули');

select set_config('role', 'anon', true), set_config('request.jwt.claims', '{"role":"anon"}', true);
select throws_ok('select * from public.my_stats()', '42501', null, 'гостю статистика недоступна');

select * from finish();
rollback;
