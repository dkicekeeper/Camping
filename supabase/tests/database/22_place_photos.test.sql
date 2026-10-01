-- Фото места (M8c): кто какие фото видит в галерее места, фильтр, страницы.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(14);

create function pg_temp.act_as_anon() returns void language plpgsql as $$
begin
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
end $$;

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

-- Номера фото (последняя цифра id), которые видит зритель, по порядку галереи.
create function pg_temp.photos(p_place uuid, p_kind text default null) returns int[]
language sql as $$
  select coalesce(array_agg(right(x.id::text, 1)::int order by x.at desc, x.id desc), '{}')
    from public.place_photos(p_place, p_kind) x;
$$;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'f@test.local'),
  ('33333333-3333-3333-3333-333333333333', 's@test.local'),
  ('44444444-4444-4444-4444-444444444444', 'b@test.local');

update public.profiles set username = 'owner_a'  where id = '11111111-1111-1111-1111-111111111111';
update public.profiles set username = 'friend_f' where id = '22222222-2222-2222-2222-222222222222';

-- A и F — друзья; F заблокировал B. Места A: публичное и секретное.
insert into public.friendships (user_id, friend_id) values
  ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222'),
  ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111');
insert into public.blocks (blocker_id, blocked_id) values
  ('22222222-2222-2222-2222-222222222222', '44444444-4444-4444-4444-444444444444');
insert into public.places (id, owner_id, type, name, geom, visibility, status) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'water_body',
   'Озеро', 'SRID=4326;POINT(77.00 43.90)', 'public', 'published'),
  ('aaaaaaaa-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'fishing_spot',
   'Секретное', 'SRID=4326;POINT(77.10 43.90)', 'private', 'published');

-- F: публичный чекин (фото места 1 и фото публичного улова 2), чекин «для друзей» (фото 3).
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
insert into public.checkins (id, place_id, at, visibility) values
  ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', now() - interval '3 hours', 'public'),
  ('cccccccc-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001', now() - interval '2 hours', 'friends');
insert into public.catches (id, checkin_id, species_id, visibility) values
  ('dddddddd-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001', 'pike', 'public');
insert into public.media (id, checkin_id, catch_id, width, height) values
  ('eeeeeeee-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001', null, 1600, 1200),
  ('eeeeeeee-0000-0000-0000-000000000002', 'cccccccc-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000001', 1200, 1600),
  ('eeeeeeee-0000-0000-0000-000000000003', 'cccccccc-0000-0000-0000-000000000002', null, 1600, 1200);

-- S: секретный чекин в публичном месте (фото 4).
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
insert into public.checkins (id, place_id, at, visibility) values
  ('cccccccc-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000001', now() - interval '1 hour', 'private');
insert into public.media (id, checkin_id, width, height) values
  ('eeeeeeee-0000-0000-0000-000000000004', 'cccccccc-0000-0000-0000-000000000003', 1600, 1200);

-- A: фото в своём секретном месте (5).
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.checkins (id, place_id, visibility) values
  ('cccccccc-0000-0000-0000-000000000004', 'aaaaaaaa-0000-0000-0000-000000000002', 'private');
insert into public.media (id, checkin_id, width, height) values
  ('eeeeeeee-0000-0000-0000-000000000005', 'cccccccc-0000-0000-0000-000000000004', 1600, 1200);

-- Матрица --------------------------------------------------------------------------------------

select pg_temp.act_as_anon();
select is(pg_temp.photos('aaaaaaaa-0000-0000-0000-000000000001'), array[2, 1],
  'гость: только фото публичного чекина');
select is(pg_temp.photos('aaaaaaaa-0000-0000-0000-000000000001', 'catches'), array[2], 'фильтр «уловы»');
select is(pg_temp.photos('aaaaaaaa-0000-0000-0000-000000000001', 'place'), array[1], 'фильтр «место»');

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is(pg_temp.photos('aaaaaaaa-0000-0000-0000-000000000001'), array[4, 2, 1],
  'S: публичные и своё секретное, свежие сверху');
select is(pg_temp.photos('aaaaaaaa-0000-0000-0000-000000000002'), '{}'::int[],
  'S: фото в чужом секретном месте не видны');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(pg_temp.photos('aaaaaaaa-0000-0000-0000-000000000001'), array[3, 2, 1],
  'A (друг F): и фото «для друзей», без секретного фото S');
select is(pg_temp.photos('aaaaaaaa-0000-0000-0000-000000000002'), array[5],
  'A: фото в своём секретном месте');

select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select is(pg_temp.photos('aaaaaaaa-0000-0000-0000-000000000001'), '{}'::int[],
  'B (заблокирован F): фото F не видны');

-- Улов стал секретным — его фото пропадает, фото места остаётся.
select pg_temp.act_as_admin();
update public.catches set visibility = 'private' where id = 'dddddddd-0000-0000-0000-000000000001';
select pg_temp.act_as_anon();
select is(pg_temp.photos('aaaaaaaa-0000-0000-0000-000000000001'), array[1],
  'фото секретного улова не видно');
select pg_temp.act_as_admin();
update public.catches set visibility = 'public' where id = 'dddddddd-0000-0000-0000-000000000001';

-- Поля и страницы ----------------------------------------------------------------------------------

select pg_temp.act_as_anon();
select is(
  (select array[x.path, x.thumb_path, x.author_username]
     from public.place_photos('aaaaaaaa-0000-0000-0000-000000000001', 'place') x),
  array['22222222-2222-2222-2222-222222222222/eeeeeeee-0000-0000-0000-000000000001.jpg',
        '22222222-2222-2222-2222-222222222222/eeeeeeee-0000-0000-0000-000000000001_thumb.jpg',
        'friend_f'],
  'путь, превью и автор');
select is(
  (select bool_or(x.is_own) from public.place_photos('aaaaaaaa-0000-0000-0000-000000000001') x),
  false, 'у гостя ничего не «своё»');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
create temp table page1 as
  select * from public.place_photos('aaaaaaaa-0000-0000-0000-000000000001', null, 2);
select is((select count(*) from page1), 2::bigint, 'первая страница — 2 фото');
select is(
  (select array_agg(right(x.id::text, 1)::int)
     from public.place_photos('aaaaaaaa-0000-0000-0000-000000000001', null, 2,
            (select at from page1 order by at, id limit 1),
            (select id from page1 order by at, id limit 1)) x),
  array[1], 'следующая страница — после курсора');

select throws_ok($$ select * from public.place_photos('aaaaaaaa-0000-0000-0000-000000000001', 'video') $$,
  '22023', null, 'неизвестный фильтр');

select * from finish();
rollback;
