-- M13: достижения. Считаются по своим данным, остаются после удаления, видны только владельцу.
-- A — набирает значки, B — другой человек.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(18);

create function pg_temp.act_as(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

create function pg_temp.act_as_admin() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

-- Значок: «progress/target», «earned» или «new».
create function pg_temp.badge(p_id text) returns text language sql as $$
  select a.progress || '/' || a.target
         || case when a.is_new then ' new' when a.earned_at is not null then ' earned' else '' end
    from public.my_achievements() a
   where a.achievement = p_id;
$$;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.local');

-- Пусто -------------------------------------------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  (select count(*)::integer from public.my_achievements() where earned_at is null),
  10,
  'у нового человека 10 значков, ни одного не получено'
);
select is(
  (select string_agg(achievement, ',') from public.my_achievements()),
  'first_trip,distance_100,nights_5,first_catch,species_5,trophy_3kg,places_5,first_public_place,reviews_5,accepted_edit',
  'порядок показа'
);

-- Поездки ------------------------------------------------------------------------------------------

select pg_temp.act_as_admin();
insert into public.trips (id, owner_id, title, started_at, ended_at, distance_m, visibility) values
  -- Две ночи и 120 км.
  ('77777777-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Алаколь',
   '2026-07-10 10:00+05', '2026-07-12 18:00+05', 120000, 'private'),
  -- Забытая запись на месяц — не больше 14 ночей.
  ('77777777-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'Забыл выключить',
   '2026-08-01 10:00+05', '2026-08-31 10:00+05', 0, 'private'),
  -- Удалённая — не в счёт.
  ('77777777-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'Удалённая',
   '2026-09-01 10:00+05', '2026-09-03 10:00+05', 500000, 'private');
update public.trips set deleted_at = now() where id = '77777777-0000-0000-0000-000000000003';

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(pg_temp.badge('first_trip'), '2/1 new', 'первая поездка получена и отмечена новой');
select is(pg_temp.badge('distance_100'), '120/100 new', '100 км: удалённая поездка не в счёт');
select is(pg_temp.badge('nights_5'), '16/5 new', 'ночёвки: 2 + не больше 14 за одну поездку');

-- Уловы и места ------------------------------------------------------------------------------------

select pg_temp.act_as_admin();
insert into public.places (id, owner_id, type, name, geom, visibility, status) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'water_body', 'Озеро',
   'SRID=4326;POINT(77.10 43.90)', 'public', 'pending'),
  ('aaaaaaaa-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'fishing_spot', 'Секрет',
   'SRID=4326;POINT(77.20 43.90)', 'private', 'published');
insert into public.checkins (id, owner_id, place_id, visibility) values
  ('cccccccc-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-0000-0000-0000-000000000001', 'private'),
  ('cccccccc-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-0000-0000-0000-000000000002', 'private'),
  ('cccccccc-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-0000-0000-0000-000000000002', 'private');
insert into public.catches (owner_id, checkin_id, species_id, weight_g, count, visibility) values
  ('11111111-1111-1111-1111-111111111111', 'cccccccc-0000-0000-0000-000000000001', 'pike', 2400, 1, 'private'),
  -- Пять окуней вместе 4 кг — не трофей.
  ('11111111-1111-1111-1111-111111111111', 'cccccccc-0000-0000-0000-000000000002', 'perch', 4000, 5, 'private'),
  ('11111111-1111-1111-1111-111111111111', 'cccccccc-0000-0000-0000-000000000003', 'other', null, 1, 'private');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(pg_temp.badge('first_catch'), '3/1 new', 'первый улов');
select is(pg_temp.badge('species_5'), '2/5', 'виды без «другой рыбы»');
select is(pg_temp.badge('trophy_3kg'), '2400/3000', 'трофей — одна рыба, а не сумма нескольких');
select is(pg_temp.badge('places_5'), '2/5', 'разные места с отчётами');
select is(pg_temp.badge('first_public_place'), '0/1', 'место на проверке и секретное — не в счёт');

select pg_temp.act_as_admin();
update public.places set status = 'published' where id = 'aaaaaaaa-0000-0000-0000-000000000001';
insert into public.catches (owner_id, checkin_id, species_id, weight_g, count, visibility)
values ('11111111-1111-1111-1111-111111111111', 'cccccccc-0000-0000-0000-000000000001', 'common_carp', 3200, 1, 'private');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  pg_temp.badge('first_public_place') || ' ' || pg_temp.badge('trophy_3kg'),
  '1/1 new 3200/3000 new',
  'опубликованное публичное место и сазан на 3,2 кг'
);

-- Новые и просмотренные ----------------------------------------------------------------------------

select public.mark_achievements_seen();
select is(
  (select count(*)::integer from public.my_achievements() where is_new),
  0,
  'после поздравления значки уже не новые'
);

-- Значок остаётся, даже если удалить то, за что он получен.
select pg_temp.act_as_admin();
update public.trips set deleted_at = now() where owner_id = '11111111-1111-1111-1111-111111111111';
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(pg_temp.badge('first_trip'), '0/1 earned', 'полученный значок не пропадает');

-- Приватность --------------------------------------------------------------------------------------

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is(
  (select count(*)::integer from public.achievements),
  0,
  'чужие значки не видны'
);
select is(
  (select count(*)::integer from public.my_achievements() where earned_at is not null),
  0,
  'у B своих значков нет — чужие данные не считаются'
);
select throws_ok(
  $$ insert into public.achievements (owner_id, achievement)
     values ('22222222-2222-2222-2222-222222222222', 'first_trip') $$,
  '42501',
  null,
  'выдать себе значок напрямую нельзя'
);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  (select count(*)::integer from public.achievements),
  6,
  'свои полученные значки видны'
);

reset role;
set local role anon;
select throws_ok(
  $$ select * from public.my_achievements() $$,
  '42501',
  null,
  'без входа — нельзя'
);

select * from finish();
rollback;
