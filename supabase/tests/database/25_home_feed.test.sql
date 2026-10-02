-- Главная (M10): лента — записи друзей и свои, обсуждения публичных мест.
-- A — зритель, F — друг A, S — чужой, B — заблокирован A.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(16);

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

-- Записи ленты как «вид:последняя цифра id».
create function pg_temp.feed(p_limit integer default 50) returns text[] language sql as $$
  select coalesce(array_agg(kind || ':' || right(id::text, 2) order by at desc, id desc), '{}')
    from public.home_feed(p_limit);
$$;

-- Трек на восток от (lon0, lat): n точек через 0.001° (≈ 81 м).
create function pg_temp.track(lon0 double precision, lat double precision, n integer)
returns extensions.geometry language sql as $$
  select extensions.st_setsrid(
    extensions.st_makeline(array_agg(
      extensions.st_makepoint(lon0 + i * 0.001, lat, 700, 1790485200 + i * 60) order by i)),
    4326)
    from generate_series(0, n - 1) i;
$$;

-- Места редакции в ленте не участвуют, но мешают подсчётам в других проверках — убираем.
delete from public.places where owner_id = private.editorial_id();

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'f@test.local'),
  ('33333333-3333-3333-3333-333333333333', 's@test.local'),
  ('44444444-4444-4444-4444-444444444444', 'b@test.local');
update public.profiles set username = 'viewer_a' where id = '11111111-1111-1111-1111-111111111111';

insert into public.friendships (user_id, friend_id) values
  ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222'),
  ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.blocks (blocked_id) values ('44444444-4444-4444-4444-444444444444');

-- Места: публичное у S (открыто для обсуждений), «для друзей» у F, своё на проверке у A.
-- Время создания мест и обсуждений ставят триггеры (сейчас), поэтому в ленте они сверху.
select pg_temp.act_as_admin();
insert into public.places (id, owner_id, type, name, geom, visibility, status, created_at) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', 'water_body', 'Озеро S',
   'SRID=4326;POINT(77.10 43.90)', 'public', 'published', now() - interval '20 days'),
  ('aaaaaaaa-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'fishing_spot', 'Коса F',
   'SRID=4326;POINT(77.20 43.90)', 'friends', 'published', now() - interval '9 days'),
  ('aaaaaaaa-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'campsite', 'Стоянка A',
   'SRID=4326;POINT(77.30 43.90)', 'public', 'pending', now() - interval '8 days');

-- Поездки: своя секретная у A, у F — для друзей и секретная.
insert into public.trips (id, owner_id, title, started_at, ended_at, track, visibility) values
  ('77777777-0000-0000-0000-000000000011', '11111111-1111-1111-1111-111111111111', 'Моя секретная',
   now() - interval '7 days' - interval '100 minutes', now() - interval '7 days', pg_temp.track(77.000, 43.200, 101), 'private'),
  ('77777777-0000-0000-0000-000000000012', '22222222-2222-2222-2222-222222222222', 'F для друзей',
   now() - interval '6 days' - interval '100 minutes', now() - interval '6 days', pg_temp.track(77.000, 43.300, 101), 'friends'),
  ('77777777-0000-0000-0000-000000000013', '22222222-2222-2222-2222-222222222222', 'F секретная',
   now() - interval '5 days' - interval '100 minutes', now() - interval '5 days', pg_temp.track(77.000, 43.400, 101), 'private');

-- Отчёты: F — публичный и секретный, S — публичный (не друг).
insert into public.checkins (id, owner_id, place_id, at, visibility) values
  ('cccccccc-0000-0000-0000-000000000021', '22222222-2222-2222-2222-222222222222', 'aaaaaaaa-0000-0000-0000-000000000001',
   now() - interval '4 days', 'public'),
  ('cccccccc-0000-0000-0000-000000000022', '22222222-2222-2222-2222-222222222222', 'aaaaaaaa-0000-0000-0000-000000000001',
   now() - interval '3 days 12 hours', 'private'),
  ('cccccccc-0000-0000-0000-000000000023', '33333333-3333-3333-3333-333333333333', 'aaaaaaaa-0000-0000-0000-000000000001',
   now() - interval '3 days', 'public');

-- Отзыв F, обсуждения S и заблокированного B в публичном месте.
insert into public.reviews (id, owner_id, place_id, rating, body, created_at) values
  ('eeeeeeee-0000-0000-0000-000000000031', '22222222-2222-2222-2222-222222222222', 'aaaaaaaa-0000-0000-0000-000000000001',
   5, 'Хорошо клюёт', now() - interval '2 days');
insert into public.threads (id, owner_id, place_id, title, body, created_at) values
  ('dddddddd-0000-0000-0000-000000000041', '33333333-3333-3333-3333-333333333333', 'aaaaaaaa-0000-0000-0000-000000000001',
   'Как проехать после дождя?', 'Дорога раскисла?', now() - interval '1 day'),
  ('dddddddd-0000-0000-0000-000000000042', '44444444-4444-4444-4444-444444444444', 'aaaaaaaa-0000-0000-0000-000000000001',
   'Продам лодку', 'Недорого', now() - interval '12 hours');

-- Лента A --------------------------------------------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  pg_temp.feed(),
  array['thread:41', 'place:03', 'place:02', 'review:31', 'checkin:21', 'trip:12', 'trip:11'],
  'A: свои записи (и секретные, и на проверке), записи друга, обсуждения; без чужих и заблокированных'
);

select ok(
  not ('checkin:22' = any (pg_temp.feed())) and not ('trip:13' = any (pg_temp.feed())),
  'секретное друга не видно'
);

select ok(
  not ('checkin:23' = any (pg_temp.feed())),
  'отчёты не-друзей в ленту не попадают'
);

select ok(
  not ('thread:42' = any (pg_temp.feed())),
  'обсуждения заблокированного не видны'
);

select is(
  (select data ->> 'title' from public.home_feed(50) where id = 'dddddddd-0000-0000-0000-000000000041'),
  'Как проехать после дождя?',
  'у обсуждения — заголовок'
);

select is(
  (select data ->> 'place_name' from public.home_feed(50) where id = 'dddddddd-0000-0000-0000-000000000041'),
  'Озеро S',
  'и место'
);

-- Трек: свой — с самого начала, у друга — без начала (обрезка 200–500 м).
select ok(
  (select (data -> 'track' -> 'coordinates' -> 0 ->> 0)::numeric = 77.0
     from public.home_feed(50) where id = '77777777-0000-0000-0000-000000000011'),
  'свой трек — целиком, с первой точки'
);

select ok(
  (select extensions.st_xmin(extensions.st_geomfromgeojson((data ->> 'track'))) > 77.002
     from public.home_feed(50) where id = '77777777-0000-0000-0000-000000000012'),
  'у трека друга начало скрыто'
);

select ok(
  (select jsonb_typeof(data -> 'track') = 'object'
          and (data ->> 'started_at') is not null
          and (data ->> 'distance_m') is not null
     from public.home_feed(50) where id = '77777777-0000-0000-0000-000000000012'),
  'у поездки — трек и цифры для поста'
);

-- Страницы
select is(
  (select array_agg(kind || ':' || right(id::text, 2) order by at desc, id desc)
     from public.home_feed(3,
       (select at from public.home_feed(3) order by at desc, id desc offset 2 limit 1),
       (select id from public.home_feed(3) order by at desc, id desc offset 2 limit 1))),
  array['review:31', 'checkin:21', 'trip:12'],
  'следующая страница — после последней записи предыдущей'
);

-- Лента друга F: видит свою секретную поездку и записи A, кроме секретного A.
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select ok(
  'trip:13' = any (pg_temp.feed()) and not ('trip:11' = any (pg_temp.feed())),
  'F видит своё секретное, но не секретное A'
);

select ok(
  not ('place:03' = any (pg_temp.feed())),
  'место A на проверке другу не видно'
);

-- Чужой S: свои записи и обсуждения (в том числе от B — S его не блокировал).
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is(
  pg_temp.feed(),
  array['thread:42', 'thread:41', 'place:01', 'checkin:23'],
  'S: своё (отчёт и место) и обсуждения, ничего от A и F'
);

-- Гость: только обсуждения.
select pg_temp.act_as_anon();
select is(
  pg_temp.feed(),
  array['thread:42', 'thread:41'],
  'гость видит только обсуждения публичных мест'
);

-- Место стало приватным — его обсуждения пропадают.
select pg_temp.act_as_admin();
update public.places set visibility = 'private' where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select pg_temp.act_as_anon();
select is(pg_temp.feed(), '{}'::text[], 'обсуждения закрытого места не видны');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select ok(
  not ('review:31' = any (pg_temp.feed())) and not ('checkin:21' = any (pg_temp.feed())),
  'отзыв и отчёт в закрытом чужом месте пропадают'
);

select * from finish();
rollback;
