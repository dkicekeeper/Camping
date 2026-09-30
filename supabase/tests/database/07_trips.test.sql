-- Поездки: только свои, служебные поля, трек, чекины поездки.
-- A — автор, S — другой пользователь.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(14);

create function pg_temp.act_as(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

create function pg_temp.act_as_anon() returns void language plpgsql as $$
begin
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
end $$;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('33333333-3333-3333-3333-333333333333', 's@test.local');

-- Место S (публичное, опубликовано) и секретное место S.
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
insert into public.places (id, type, name, geom, visibility) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'fishing_spot', 'Публичное S', 'SRID=4326;POINT(77.00 43.90)', 'public');
-- Публикует модератор (не клиент): без JWT пользователя.
reset role;
select set_config('request.jwt.claims', '', true);
update public.places set status = 'published' where id = 'aaaaaaaa-0000-0000-0000-000000000001';

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.places (id, type, name, geom, visibility) values
  ('aaaaaaaa-0000-0000-0000-000000000002', 'fishing_spot', 'Моё', 'SRID=4326;POINT(77.10 43.90)', 'private');

-- Поездка A так, как её отправляет телефон: трек в EWKT с высотой и временем.
select lives_ok(
  $$ insert into public.trips (id, activity, title, started_at, ended_at, moving_seconds, distance_m,
                               elevation_gain_m, max_speed_mps, track, visibility) values
       ('77777777-0000-0000-0000-000000000001', 'fishing', 'Рыбалка на Капшагае',
        '2026-09-27 05:00+00', '2026-09-27 13:00+00', 18000, 12400, 85, 16.5,
        'SRID=4326;LINESTRING ZM (77.000001 43.900001 480.5 1790485200, 77.010000 43.905000 482 1790485260, 77.020000 43.910000 0 1790485320)',
        'friends') $$,
  'автор сохраняет поездку с треком'
);
select ok(
  (select owner_id = '11111111-1111-1111-1111-111111111111'
          and extensions.st_npoints(track) = 3
          and extensions.st_m(extensions.st_startpoint(track)) = 1790485200
          and extensions.st_z(extensions.st_startpoint(track)) = 480.5
     from public.trips where id = '77777777-0000-0000-0000-000000000001'),
  'трек хранит высоту и время каждой точки'
);
select throws_ok(
  $$ insert into public.trips (owner_id, title, started_at, ended_at) values
       ('33333333-3333-3333-3333-333333333333', 'Чужая', now(), now()) $$,
  '42501', null,
  'автора поездки задать нельзя'
);
select throws_ok(
  $$ insert into public.trips (title, started_at, ended_at) values ('Назад в прошлое', now(), now() - interval '1 hour') $$,
  '23514', null,
  'конец поездки не раньше начала'
);
select throws_ok(
  $$ insert into public.trips (title, started_at, ended_at) values ('', now(), now()) $$,
  '23514', null,
  'у поездки есть название'
);
select lives_ok(
  $$ insert into public.trips (title, started_at, ended_at) values ('Без трека', now(), now()) $$,
  'поездка без трека (меньше двух точек) сохраняется'
);
select throws_ok(
  $$ update public.trips set track = null where id = '77777777-0000-0000-0000-000000000001' $$,
  '42501', null,
  'трек после сохранения не меняется'
);
select lives_ok(
  $$ update public.trips set title = 'Капшагай, утро', visibility = 'private'
      where id = '77777777-0000-0000-0000-000000000001' $$,
  'название и видимость можно поменять'
);

-- Чекины A: во время поездки (в чужом публичном и в своём месте) и после неё.
insert into public.checkins (id, place_id, at, note) values
  ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', '2026-09-27 07:00+00', 'утро'),
  ('cccccccc-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000002', '2026-09-27 12:00+00', 'день'),
  ('cccccccc-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000002', '2026-09-28 12:00+00', 'на следующий день');
insert into public.catches (checkin_id, species_id, count, weight_g) values
  ('cccccccc-0000-0000-0000-000000000001', 'zander', 2, 1800);

select is(
  (select array_agg(note order by at) from public.my_trip_checkins('77777777-0000-0000-0000-000000000001')),
  array['утро', 'день'],
  'к поездке относятся чекины за её время'
);
select ok(
  (select place_name = 'Публичное S' and jsonb_array_length(catches) = 1
     from public.my_trip_checkins('77777777-0000-0000-0000-000000000001')
    where checkin_id = 'cccccccc-0000-0000-0000-000000000001'),
  'в чекине поездки — название места и уловы'
);

-- Место S стало секретным: название пропадает, чекин остаётся.
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
update public.places set visibility = 'private' where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select ok(
  (select place_name is null from public.my_trip_checkins('77777777-0000-0000-0000-000000000001')
    where checkin_id = 'cccccccc-0000-0000-0000-000000000001'),
  'название чужого места, которое больше не видно, не отдаётся'
);

-- Другой пользователь.
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is_empty($$ select * from public.trips $$, 'чужие поездки не видны');
select is_empty($$ select * from public.my_trip_checkins('77777777-0000-0000-0000-000000000001') $$,
  'чекины чужой поездки не отдаются');

select pg_temp.act_as_anon();
select throws_ok('select * from public.my_trip_checkins(''77777777-0000-0000-0000-000000000001'')',
  '42501', null, 'гостю поездки недоступны');

select * from finish();
rollback;
