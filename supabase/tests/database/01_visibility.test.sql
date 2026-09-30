-- Матрица видимости мест и чекинов (docs/03-architecture/02-backend.md, «Приватность в базе»).
-- Зрители: A — владелец, F — друг A, S — чужой, B — заблокирован A, гость (anon).

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(41);

-- Места редакции (M6e) — начальные данные; в этих проверках не участвуют.
delete from public.places where owner_id = private.editorial_id();

-- Помощники: действовать от имени пользователя / гостя / администратора ----------------------

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

-- Пользователи -------------------------------------------------------------------------------

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local', '{"full_name": "Owner A"}'),
  ('22222222-2222-2222-2222-222222222222', 'f@test.local', '{"full_name": "Friend F"}'),
  ('33333333-3333-3333-3333-333333333333', 's@test.local', '{"full_name": "Stranger S"}'),
  ('44444444-4444-4444-4444-444444444444', 'b@test.local', '{"full_name": "Blocked B"}');

update public.profiles set username = 'owner_a'    where id = '11111111-1111-1111-1111-111111111111';
update public.profiles set username = 'friend_f'   where id = '22222222-2222-2222-2222-222222222222';
update public.profiles set username = 'stranger_s' where id = '33333333-3333-3333-3333-333333333333';
update public.profiles set username = 'blocked_b'  where id = '44444444-4444-4444-4444-444444444444';

select is(
  (select display_name from public.profiles where id = '11111111-1111-1111-1111-111111111111'),
  'Owner A',
  'профиль создаётся триггером при регистрации'
);

-- Места A (район Капшагая) -------------------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');

insert into public.places (id, type, name, geom, access_point, visibility, approximate) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'fishing_spot', 'Публичное точное',
   st_setsrid(st_makepoint(77.00, 43.90), 4326), null, 'public', false),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'fishing_spot', 'Публичное приблизительное',
   st_setsrid(st_makepoint(77.05, 43.90), 4326), st_setsrid(st_makepoint(77.051, 43.901), 4326), 'public', true),
  ('aaaaaaaa-0000-0000-0000-000000000003', 'fishing_spot', 'Для друзей точное',
   st_setsrid(st_makepoint(77.10, 43.90), 4326), null, 'friends', false),
  ('aaaaaaaa-0000-0000-0000-000000000004', 'fishing_spot', 'Для друзей приблизительное',
   st_setsrid(st_makepoint(77.15, 43.90), 4326), null, 'friends', true),
  ('aaaaaaaa-0000-0000-0000-000000000005', 'fishing_spot', 'Секретное',
   st_setsrid(st_makepoint(77.20, 43.90), 4326), null, 'private', false);

select is((select count(*) from public.places), 5::bigint, 'A напрямую видит свои 5 мест');

select is(
  (select count(*) from public.places where status = 'pending'),
  2::bigint,
  'первые публичные места нового автора уходят на модерацию'
);

select throws_ok(
  $$ update public.places set status = 'published' where id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
  '42501', null,
  'клиент не может сам опубликовать место'
);

select throws_ok(
  $$ insert into public.places (type, name, geom, visibility, owner_id)
     values ('fishing_spot', 'Чужое', st_setsrid(st_makepoint(77, 44), 4326), 'public',
             '33333333-3333-3333-3333-333333333333') $$,
  '42501', null,
  'клиент не может создать место от чужого имени'
);

-- Модератор публикует.
select pg_temp.act_as_admin();
update public.places set status = 'published' where status = 'pending';

select is(
  (select count(*) from public.places where status = 'published'),
  5::bigint,
  'модератор может менять статус'
);

-- Друзья и блокировки ------------------------------------------------------------------------

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is(public.send_friend_request('11111111-1111-1111-1111-111111111111'), 'sent', 'F отправляет запрос A');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select lives_ok(
  $$ select public.respond_friend_request(
       (select id from public.friend_requests where to_user = '11111111-1111-1111-1111-111111111111'), true) $$,
  'A принимает запрос'
);
select is((select count(*) from public.my_friends()), 1::bigint, 'у A один друг');
insert into public.blocks (blocked_id) values ('44444444-4444-4444-4444-444444444444');

-- Матрица: места в области карты -------------------------------------------------------------

-- Снимаем результаты от имени каждого зрителя во временные таблицы.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
create temp table seen_a as select * from public.places_in_bbox(76.5, 43.5, 77.5, 44.3);

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
create temp table seen_f as select * from public.places_in_bbox(76.5, 43.5, 77.5, 44.3);
create temp table seen_f_again as select * from public.places_in_bbox(76.5, 43.5, 77.5, 44.3);

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
create temp table seen_s as select * from public.places_in_bbox(76.5, 43.5, 77.5, 44.3);
-- Попытка найти настоящую точку, сузив область вокруг неё.
create temp table probe_s as select * from public.places_in_bbox(77.0495, 43.8995, 77.0505, 43.9005);

select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
create temp table seen_b as select * from public.places_in_bbox(76.5, 43.5, 77.5, 44.3);

select pg_temp.act_as_anon();
create temp table seen_anon as select * from public.places_in_bbox(76.5, 43.5, 77.5, 44.3);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
create temp table probe_a as select * from public.places_in_bbox(77.0495, 43.8995, 77.0505, 43.9005);

select pg_temp.act_as_admin();

select set_eq(
  'select id from seen_a',
  array['aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000002',
        'aaaaaaaa-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000004',
        'aaaaaaaa-0000-0000-0000-000000000005']::uuid[],
  'владелец видит все свои места'
);
select is(
  (select count(*) from seen_a where approximate or not is_own),
  0::bigint,
  'владелец видит свои места точно'
);

select set_eq(
  'select id from seen_f',
  array['aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000002',
        'aaaaaaaa-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000004']::uuid[],
  'друг видит публичные и дружеские, но не секретное'
);
select set_eq(
  'select id from seen_f where approximate and radius_m = 1000',
  array['aaaaaaaa-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000004']::uuid[],
  'другу приблизительные места показываются кругом 1 км'
);
select ok(
  (select not (lon = 77.05 and lat = 43.90)
          and st_dwithin(st_setsrid(st_makepoint(lon, lat), 4326)::geography,
                         st_setsrid(st_makepoint(77.05, 43.90), 4326)::geography, 1000)
     from seen_f where id = 'aaaaaaaa-0000-0000-0000-000000000002'),
  'показанный центр не совпадает с настоящей точкой, но круг её содержит'
);
select ok(
  (select a.lon = b.lon and a.lat = b.lat
     from seen_f a join seen_f_again b using (id)
    where id = 'aaaaaaaa-0000-0000-0000-000000000002'),
  'смещение стабильно между запросами (нельзя усреднить)'
);
select ok(
  (select lon = 77.10 and lat = 43.90 and not approximate
     from seen_f where id = 'aaaaaaaa-0000-0000-0000-000000000003'),
  'точное дружеское место друг видит точно'
);

select set_eq(
  'select id from seen_s',
  array['aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000002']::uuid[],
  'чужой видит только публичные'
);
select is(
  (select count(*) from probe_s where id = 'aaaaaaaa-0000-0000-0000-000000000002'),
  0::bigint,
  'сужение области вокруг настоящей точки не находит приблизительное место'
);
select is(
  (select count(*) from probe_a where id = 'aaaaaaaa-0000-0000-0000-000000000002'),
  1::bigint,
  'владелец находит своё место в узкой области'
);

select is((select count(*) from seen_b), 0::bigint, 'заблокированный не видит мест A');

select set_eq(
  'select id from seen_anon',
  array['aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000002']::uuid[],
  'гость видит только публичные'
);
select ok(
  (select approximate from seen_anon where id = 'aaaaaaaa-0000-0000-0000-000000000002'),
  'гостю приблизительное место показывается кругом'
);

-- Прямой доступ к таблицам -------------------------------------------------------------------

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is((select count(*) from public.places), 0::bigint, 'друг не читает чужие строки напрямую');
select is((select count(*) from public.profiles), 1::bigint, 'напрямую читается только свой профиль');

select pg_temp.act_as_anon();
select throws_ok('select * from public.places', '42501', null, 'гость не имеет доступа к таблице мест');

-- Карточка места ------------------------------------------------------------------------------

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is_empty(
  $$ select * from public.place_card('aaaaaaaa-0000-0000-0000-000000000003') $$,
  'чужой не получает карточку дружеского места'
);
select ok(
  (select access_lon is null and access_lat is null and approximate
     from public.place_card('aaaaaaaa-0000-0000-0000-000000000002')),
  'у огрублённого места точка подъезда скрыта'
);

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select isnt_empty(
  $$ select * from public.place_card('aaaaaaaa-0000-0000-0000-000000000003') $$,
  'друг получает карточку дружеского места'
);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select ok(
  (select access_lon = 77.051 and not approximate
     from public.place_card('aaaaaaaa-0000-0000-0000-000000000002')),
  'владелец видит точку подъезда своего места'
);

-- Модерация новых публичных мест ------------------------------------------------------------

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
insert into public.places (id, type, name, geom, visibility)
values ('aaaaaaaa-0000-0000-0000-000000000006', 'campsite', 'Новое публичное от S',
        st_setsrid(st_makepoint(77.30, 43.95), 4326), 'public');
select is(
  (select status from public.places_in_bbox(76.5, 43.5, 77.5, 44.3)
    where id = 'aaaaaaaa-0000-0000-0000-000000000006'),
  'pending'::public.place_status,
  'автор видит своё место на модерации'
);

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is(
  (select count(*) from public.places_in_bbox(76.5, 43.5, 77.5, 44.3)
    where id = 'aaaaaaaa-0000-0000-0000-000000000006'),
  0::bigint,
  'другие не видят место на модерации'
);

-- Чекины --------------------------------------------------------------------------------------

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
insert into public.checkins (id, place_id, geom, visibility) values
  ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000003',
   st_setsrid(st_makepoint(77.10, 43.9009), 4326), 'public'),
  ('cccccccc-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000003',
   st_setsrid(st_makepoint(77.10, 43.95), 4326), 'friends');

select ok(
  (select verified from public.checkins where id = 'cccccccc-0000-0000-0000-000000000001'),
  'чекин в 100 м от места подтверждён'
);
select ok(
  (select not verified from public.checkins where id = 'cccccccc-0000-0000-0000-000000000002'),
  'чекин в 5 км от места не подтверждён'
);
select is(
  (select visibility from public.checkins where id = 'cccccccc-0000-0000-0000-000000000001'),
  'friends'::public.visibility,
  'чекин не может быть видимее места'
);

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select throws_ok(
  $$ insert into public.checkins (place_id) values ('aaaaaaaa-0000-0000-0000-000000000003') $$,
  'P0002', 'place not found',
  'нельзя отметиться в месте, которое не видно'
);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.checkins (id, place_id, visibility)
values ('cccccccc-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000005', 'public');
select is(
  (select visibility from public.checkins where id = 'cccccccc-0000-0000-0000-000000000003'),
  'private'::public.visibility,
  'чекин в секретном месте всегда приватный'
);

-- Профили и блокировки -----------------------------------------------------------------------

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select isnt_empty($$ select * from public.profile_by_username('owner_a') $$, 'профиль находится по username');

select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select is_empty($$ select * from public.profile_by_username('owner_a') $$, 'заблокированный не находит профиль');

-- A блокирует друга F: дружба разрывается, места друзей пропадают.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.blocks (blocked_id) values ('22222222-2222-2222-2222-222222222222');
select is((select count(*) from public.my_friends()), 0::bigint, 'блокировка разрывает дружбу');

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is(
  (select count(*) from public.places_in_bbox(76.5, 43.5, 77.5, 44.3)
    where owner_id = '11111111-1111-1111-1111-111111111111'),
  0::bigint,
  'после блокировки бывший друг не видит мест A'
);

-- Модератор скрывает место.
select pg_temp.act_as_admin();
update public.places set status = 'hidden' where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is(
  (select count(*) from public.places_in_bbox(76.5, 43.5, 77.5, 44.3)
    where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  0::bigint,
  'скрытое модератором место не видно'
);

select * from finish();
rollback;
