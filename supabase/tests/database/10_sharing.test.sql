-- Поездки друзей, зоны приватности, профиль другого человека и лента друзей (M4b).
-- A — автор, F — друг A, S — чужой, B — заблокирован A.
--
-- Трек поездок A идёт на восток по широте 43.2 от дома H (77.000, 43.200): 101 точка
-- через 0.001° долготы (≈ 81 м), всего ≈ 8,1 км.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(48);

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

create function pg_temp.act_as_admin() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

-- Трек из n точек на восток от (lon0, lat).
create function pg_temp.track(lon0 double precision, lat double precision, n integer)
returns extensions.geometry language sql as $$
  select extensions.st_setsrid(
    extensions.st_makeline(array_agg(
      extensions.st_makepoint(lon0 + i * 0.001, lat, 700, 1790485200 + i * 60) order by i)),
    4326)
    from generate_series(0, n - 1) i;
$$;

-- Видимый трек как геометрия (из GeoJSON ответа trip_view).
create function pg_temp.geo(track jsonb) returns extensions.geography language sql as $$
  select extensions.st_setsrid(extensions.st_geomfromgeojson(track::text), 4326)::extensions.geography;
$$;

create function pg_temp.pt(lon double precision, lat double precision) returns extensions.geography
language sql as $$
  select extensions.st_setsrid(extensions.st_makepoint(lon, lat), 4326)::extensions.geography;
$$;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'f@test.local'),
  ('33333333-3333-3333-3333-333333333333', 's@test.local'),
  ('44444444-4444-4444-4444-444444444444', 'b@test.local');
update public.profiles set username = 'author' where id = '11111111-1111-1111-1111-111111111111';

insert into public.friendships (user_id, friend_id) values
  ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222'),
  ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.blocks (blocked_id) values ('44444444-4444-4444-4444-444444444444');

-- Зоны приватности -----------------------------------------------------------------------------

select lives_ok(
  $$ insert into public.privacy_zones (id, name, geom, radius_m) values
       ('99999999-0000-0000-0000-000000000001', 'Дом', 'SRID=4326;POINT(77.000 43.200)', 500) $$,
  'автор добавляет зону приватности'
);
select throws_ok(
  $$ select hidden_center from public.privacy_zones $$,
  '42501', null,
  'смещённый центр зоны не отдаётся даже автору'
);
select throws_ok(
  $$ insert into public.privacy_zones (name, geom, radius_m) values ('Мала', 'SRID=4326;POINT(77 43)', 100) $$,
  '23514', null,
  'радиус зоны — от 200 м'
);
select throws_ok(
  $$ insert into public.privacy_zones (owner_id, name, geom) values
       ('33333333-3333-3333-3333-333333333333', 'Чужая', 'SRID=4326;POINT(77 43)') $$,
  '42501', null,
  'владельца зоны задать нельзя'
);
select lives_ok(
  $$ insert into public.privacy_zones (name, geom)
     select 'Зона ' || i, extensions.st_setsrid(extensions.st_makepoint(76 + i * 0.01, 44), 4326)
       from generate_series(1, 9) i $$,
  'до 10 зон'
);
select throws_ok(
  $$ insert into public.privacy_zones (name, geom) values ('Лишняя', 'SRID=4326;POINT(77 44)') $$,
  '54000', null,
  'одиннадцатая зона не создаётся'
);
delete from public.privacy_zones where name like 'Зона %';

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is_empty($$ select id from public.privacy_zones $$, 'чужие зоны не видны');
select is(
  (select count(*)::integer from public.privacy_zones where id = '99999999-0000-0000-0000-000000000001'),
  0,
  'чужую зону не найти и по id'
);

select pg_temp.act_as_admin();
select ok(
  (select extensions.st_distance(hidden_center::extensions.geography, geom::extensions.geography)
          between 49 and 201
     from public.privacy_zones where id = '99999999-0000-0000-0000-000000000001'),
  'центр круга скрытия смещён на 10–40% радиуса'
);

-- Места и поездки A ------------------------------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.places (id, type, name, geom, visibility, approximate) values
  -- Секретное место прямо на треке.
  ('aaaaaaaa-0000-0000-0000-000000000001', 'fishing_spot', 'Секретное', 'SRID=4326;POINT(77.050 43.200)', 'private', false),
  -- Публичное, на модерации (у автора ещё нет опубликованных) — в стороне от трека.
  ('aaaaaaaa-0000-0000-0000-000000000003', 'fishing_spot', 'На модерации', 'SRID=4326;POINT(77.020 43.250)', 'public', false),
  -- Для друзей, в стороне от трека.
  ('aaaaaaaa-0000-0000-0000-000000000004', 'campsite', 'Для друзей', 'SRID=4326;POINT(77.030 43.250)', 'friends', false),
  -- Публичное приблизительное, далеко.
  ('aaaaaaaa-0000-0000-0000-000000000005', 'water_body', 'Приблизительное', 'SRID=4326;POINT(77.200 43.400)', 'public', true);

select pg_temp.act_as_admin();
update public.places set status = 'published' where id = 'aaaaaaaa-0000-0000-0000-000000000005';

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.trips (id, title, started_at, ended_at, track, visibility) values
  ('77777777-0000-0000-0000-000000000001', 'Для друзей', now() - interval '3 days',
   now() - interval '3 days' + interval '100 minutes', pg_temp.track(77.000, 43.200, 101), 'friends'),
  ('77777777-0000-0000-0000-000000000002', 'Публичная', now() - interval '2 days' - interval '100 minutes',
   now() - interval '2 days', pg_temp.track(77.000, 43.500, 101), 'public'),
  ('77777777-0000-0000-0000-000000000003', 'Короткая', now() - interval '4 days' - interval '5 minutes',
   now() - interval '4 days', pg_temp.track(77.000, 43.600, 5), 'public'),
  ('77777777-0000-0000-0000-000000000004', 'Только я', now() - interval '5 days' - interval '1 hour',
   now() - interval '5 days', pg_temp.track(77.000, 43.700, 20), 'private');

-- Чекины за время первой поездки.
insert into public.checkins (id, place_id, at, visibility) values
  ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', now() - interval '3 days' + interval '50 minutes', 'friends'),
  ('cccccccc-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000003', now() - interval '3 days' + interval '30 minutes', 'friends'),
  ('cccccccc-0000-0000-0000-000000000004', 'aaaaaaaa-0000-0000-0000-000000000004', now() - interval '3 days' + interval '40 minutes', 'friends');
insert into public.catches (id, checkin_id, species_id, weight_g, hide_size) values
  ('dddddddd-0000-0000-0000-000000000004', 'cccccccc-0000-0000-0000-000000000004', 'pike', 1500, true);

-- Поездка друга.
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
insert into public.trips (id, title, started_at, ended_at, visibility) values
  ('77777777-0000-0000-0000-000000000005', 'Поездка F', now() - interval '1 day' - interval '1 hour',
   now() - interval '1 day', 'public');

-- Трек: автор ----------------------------------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select ok(
  (select is_own and track->>'type' = 'LineString' and jsonb_array_length(track->'coordinates') = 101
     from public.trip_view('77777777-0000-0000-0000-000000000001')),
  'автор видит свой трек целиком'
);

-- Трек: друг -----------------------------------------------------------------------------------

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select ok(
  (select not is_own and owner_username = 'author' and track->>'type' = 'MultiLineString'
     from public.trip_view('77777777-0000-0000-0000-000000000001')),
  'друг видит поездку для друзей; трек — набор видимых отрезков'
);
select is(
  (select jsonb_array_length(track->'coordinates') from public.trip_view('77777777-0000-0000-0000-000000000001')),
  2,
  'у секретного места трек разрезан на два отрезка'
);
select ok(
  (select extensions.st_distance(pg_temp.geo(track), pg_temp.pt(77.000, 43.200)) >= 500
     from public.trip_view('77777777-0000-0000-0000-000000000001')),
  'в зоне приватности (500 м от дома) трека не видно'
);
select ok(
  (select extensions.st_distance(pg_temp.geo(track), pg_temp.pt(77.050, 43.200)) >= 690
     from public.trip_view('77777777-0000-0000-0000-000000000001')),
  'у секретного места трека не видно (не ближе ≈700 м)'
);
select ok(
  (select extensions.st_distance(pg_temp.geo(track), pg_temp.pt(77.100, 43.200)) >= 200
     from public.trip_view('77777777-0000-0000-0000-000000000001')),
  'финиш скрыт (не ближе 200 м)'
);
select ok(
  (select extensions.st_npoints(extensions.st_geomfromgeojson(track::text)) >= 20
     from public.trip_view('77777777-0000-0000-0000-000000000001')),
  'остальной трек виден'
);

-- Трек: чужой и публичная поездка ----------------------------------------------------------------

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is_empty(
  $$ select id from public.trip_view('77777777-0000-0000-0000-000000000001') $$,
  'чужой не видит поездку для друзей'
);
select is(
  (select jsonb_array_length(track->'coordinates') from public.trip_view('77777777-0000-0000-0000-000000000002')),
  1,
  'публичную поездку без зон и секретных мест видно одним отрезком'
);
select ok(
  (select extensions.st_distance(pg_temp.geo(track), pg_temp.pt(77.000, 43.500)) between 200 and 600
     from public.trip_view('77777777-0000-0000-0000-000000000002')),
  'старт скрыт на 200–500 м'
);
select ok(
  (select extensions.st_distance(pg_temp.geo(track), pg_temp.pt(77.100, 43.500)) between 200 and 600
     from public.trip_view('77777777-0000-0000-0000-000000000002')),
  'финиш скрыт на 200–500 м'
);
select is(
  (select track from public.trip_view('77777777-0000-0000-0000-000000000002')),
  (select track from public.trip_view('77777777-0000-0000-0000-000000000002')),
  'обрезка стабильна: повторный запрос даёт тот же трек'
);
select ok(
  (select track is null and distance_m = 0 from public.trip_view('77777777-0000-0000-0000-000000000003')),
  'от короткого трека (меньше скрытых краёв) не остаётся ничего'
);
select is_empty(
  $$ select id from public.trip_view('77777777-0000-0000-0000-000000000004') $$,
  'поездку «только я» не видит никто, кроме автора'
);

select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select is_empty(
  $$ select id from public.trip_view('77777777-0000-0000-0000-000000000002') $$,
  'заблокированный не видит даже публичную поездку'
);

select pg_temp.act_as_anon();
select throws_ok(
  $$ select * from public.trip_view('77777777-0000-0000-0000-000000000002') $$,
  '42501', null,
  'гостю поездки недоступны'
);

-- Чекины поездки -------------------------------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  (select array_agg(place_name order by at) from public.trip_checkins('77777777-0000-0000-0000-000000000001')),
  array['На модерации', 'Для друзей', 'Секретное'],
  'автор видит все свои чекины поездки с названиями мест'
);

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is(
  (select array_agg(checkin_id order by at) from public.trip_checkins('77777777-0000-0000-0000-000000000001')),
  array['cccccccc-0000-0000-0000-000000000003', 'cccccccc-0000-0000-0000-000000000004']::uuid[],
  'друг не видит чекин в секретном месте (он «только я»)'
);
select ok(
  (select place_id is null and place_name is null
     from public.trip_checkins('77777777-0000-0000-0000-000000000001')
    where checkin_id = 'cccccccc-0000-0000-0000-000000000003'),
  'место на модерации для друга — «Секретное место»: без id и названия'
);
select is(
  (select catches->0->>'weight_g' from public.trip_checkins('77777777-0000-0000-0000-000000000001')
    where checkin_id = 'cccccccc-0000-0000-0000-000000000004'),
  null,
  'скрытый вес улова другу не отдаётся'
);

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is_empty(
  $$ select * from public.trip_checkins('77777777-0000-0000-0000-000000000001') $$,
  'чужой не видит чекины поездки для друзей'
);

-- Профиль другого человека ---------------------------------------------------------------------

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is(
  (select array_agg(title order by started_at desc) from public.user_trips('11111111-1111-1111-1111-111111111111')),
  array['Публичная', 'Для друзей', 'Короткая'],
  'друг видит поездки для друзей и публичные, новые сверху'
);
select is(
  (select array_agg(title) from public.user_trips('11111111-1111-1111-1111-111111111111', 1,
     (select started_at from public.user_trips('11111111-1111-1111-1111-111111111111', 1)))),
  array['Для друзей'],
  'следующая страница поездок'
);
select is(
  (select array_agg(name order by name) from public.user_places('11111111-1111-1111-1111-111111111111')),
  array['Для друзей', 'Приблизительное'],
  'друг видит места для друзей и опубликованные публичные'
);
select is(
  (select row(trips_count, places_count, catches_count, friends_count)::text
     from public.user_stats('11111111-1111-1111-1111-111111111111')),
  '(3,2,1,1)',
  'итоги для друга — по тому, что он видит'
);

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is(
  (select array_agg(title order by started_at desc) from public.user_trips('11111111-1111-1111-1111-111111111111')),
  array['Публичная', 'Короткая'],
  'чужой видит только публичные поездки'
);
select ok(
  (select approximate and radius_m = 1000
          and (lon, lat) <> (77.200::double precision, 43.400::double precision)
          and extensions.st_distance(pg_temp.pt(lon, lat), pg_temp.pt(77.200, 43.400)) < 1000
     from public.user_places('11111111-1111-1111-1111-111111111111')),
  'чужой видит приблизительное место только смещённым кругом'
);
select is(
  (select row(trips_count, places_count, catches_count)::text
     from public.user_stats('11111111-1111-1111-1111-111111111111')),
  '(2,1,0)',
  'итоги для чужого — только публичное'
);

select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select is_empty(
  $$ select * from public.user_trips('11111111-1111-1111-1111-111111111111') $$,
  'заблокированный не видит поездок'
);
select is_empty(
  $$ select * from public.user_places('11111111-1111-1111-1111-111111111111') $$,
  'заблокированный не видит мест'
);
select is_empty(
  $$ select * from public.user_stats('11111111-1111-1111-1111-111111111111') $$,
  'заблокированный не видит итогов'
);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  (select array_agg(name order by name) from public.user_places('11111111-1111-1111-1111-111111111111')),
  array['Для друзей', 'На модерации', 'Приблизительное', 'Секретное'],
  'свои места — все, включая секретные и на модерации'
);

-- Лента ------------------------------------------------------------------------------------------

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is(
  (select array_agg(kind || ':' || right(id::text, 1)) from public.friends_feed(10)),
  array['place:5', 'place:4', 'trip:2', 'trip:1', 'checkin:4', 'trip:3'],
  'лента друга: новые места, поездки и чекины A, которые он видит; своих записей нет'
);
select is(
  (select array_agg(kind || ':' || right(id::text, 1)) from public.friends_feed(2,
     (select at from public.friends_feed(4) offset 3 limit 1),
     (select id from public.friends_feed(4) offset 3 limit 1))),
  array['checkin:4', 'trip:3'],
  'следующая страница ленты'
);
select is(
  (select array_agg(kind || ':' || right(id::text, 1)) from public.friends_feed(2,
     (select at from public.friends_feed(1)),
     (select id from public.friends_feed(1)))),
  array['place:4', 'trip:2'],
  'страница после записи с тем же временем'
);
select ok(
  (select data->'catches'->0->>'weight_g' is null and data->>'place_name' = 'Для друзей'
     from public.friends_feed(10) where kind = 'checkin'),
  'чекин в ленте — с местом и уловом без скрытого веса'
);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  (select array_agg(kind || ':' || right(id::text, 1)) from public.friends_feed(10)),
  array['trip:5'],
  'лента автора — записи его друга'
);

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is_empty($$ select * from public.friends_feed(10) $$, 'у чужого без друзей лента пустая');

select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select is_empty($$ select * from public.friends_feed(10) $$, 'заблокированный публичных записей A в ленте не видит');

select * from finish();
rollback;
