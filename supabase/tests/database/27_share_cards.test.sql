-- M11: данные для картинок своей поездки и своего улова. Делиться можно только своим; трек — как у
-- гостя (без начала и конца); название места — только публичного.
-- A — автор, F — друг A.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(10);

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

-- Трек на восток от (lon0, lat): n точек через 0.001° (≈ 81 м).
create function pg_temp.track(lon0 double precision, lat double precision, n integer)
returns extensions.geometry language sql as $$
  select extensions.st_setsrid(
    extensions.st_makeline(array_agg(
      extensions.st_makepoint(lon0 + i * 0.001, lat, 700, 1790485200 + i * 60) order by i)),
    4326)
    from generate_series(0, n - 1) i;
$$;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'f@test.local');
insert into public.friendships (user_id, friend_id) values
  ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222'),
  ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111');

insert into public.trips (id, owner_id, title, started_at, ended_at, distance_m, track, visibility) values
  ('77777777-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Утро на косе',
   now() - interval '3 hours', now() - interval '1 hour', 8100, pg_temp.track(77.000, 43.300, 101), 'friends');

-- Места: публичное и секретное; уловы A в каждом.
insert into public.places (id, owner_id, type, name, geom, visibility, status) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'water_body', 'Капшагай',
   'SRID=4326;POINT(77.10 43.90)', 'public', 'published'),
  ('aaaaaaaa-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'fishing_spot', 'Секретная коса',
   'SRID=4326;POINT(77.20 43.90)', 'private', 'published');
insert into public.checkins (id, owner_id, place_id, visibility) values
  ('cccccccc-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-0000-0000-0000-000000000001', 'public'),
  ('cccccccc-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-0000-0000-0000-000000000002', 'private');
insert into public.catches (id, owner_id, checkin_id, species_id, weight_g, visibility) values
  ('dddddddd-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'cccccccc-0000-0000-0000-000000000001', 'pike', 2400, 'public'),
  ('dddddddd-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'cccccccc-0000-0000-0000-000000000002', 'perch', 300, 'private');
insert into public.media (id, owner_id, checkin_id, catch_id) values
  ('eeeeeeee-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'cccccccc-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000001');

-- Поездка ----------------------------------------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');

select is(
  (select title || ' ' || distance_m from public.trip_share_card('77777777-0000-0000-0000-000000000001')),
  'Утро на косе 8100',
  'автор получает данные своей поездки'
);

select ok(
  (select extensions.st_xmin(extensions.st_geomfromgeojson(track::text)) > 77.002
          and extensions.st_xmax(extensions.st_geomfromgeojson(track::text)) < 77.098
     from public.trip_share_card('77777777-0000-0000-0000-000000000001')),
  'трек на картинке — без начала и конца, даже у автора'
);

select ok(
  (select extensions.st_npoints(extensions.st_geomfromgeojson(track::text)) < 101
     from public.trip_share_card('77777777-0000-0000-0000-000000000001')),
  'трек упрощён'
);

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is(
  (select count(*)::integer from public.trip_share_card('77777777-0000-0000-0000-000000000001')),
  0,
  'чужой поездкой (даже друга) поделиться нельзя'
);

-- Улов -------------------------------------------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');

select is(
  (select species_id || ' ' || weight_g || ' ' || place_name
     from public.catch_share_card('dddddddd-0000-0000-0000-000000000001')),
  'pike 2400 Капшагай',
  'улов в публичном месте — с названием места'
);

select is(
  (select photo_path from public.catch_share_card('dddddddd-0000-0000-0000-000000000001')),
  '11111111-1111-1111-1111-111111111111/eeeeeeee-0000-0000-0000-000000000001.jpg',
  'и с фото улова'
);

select ok(
  (select place_name is null and photo_path is null
     from public.catch_share_card('dddddddd-0000-0000-0000-000000000002')),
  'улов в секретном месте — без названия места (и без фото, если его нет)'
);

select pg_temp.act_as_admin();
update public.media set deleted_at = now() where id = 'eeeeeeee-0000-0000-0000-000000000001';
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  (select photo_path from public.catch_share_card('dddddddd-0000-0000-0000-000000000001')),
  null,
  'удалённое фото не попадает на картинку'
);

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is(
  (select count(*)::integer from public.catch_share_card('dddddddd-0000-0000-0000-000000000001')),
  0,
  'чужим уловом поделиться нельзя'
);

select pg_temp.act_as_admin();
update public.catches set deleted_at = now() where id = 'dddddddd-0000-0000-0000-000000000001';
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  (select count(*)::integer from public.catch_share_card('dddddddd-0000-0000-0000-000000000001')),
  0,
  'удалённым уловом — тоже'
);

select * from finish();
rollback;
