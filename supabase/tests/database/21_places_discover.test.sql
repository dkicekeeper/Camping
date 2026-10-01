-- Вкладка «Места» (M8): подборки, поиск, сохранённые места, подборки редакции.
-- Матрица «зритель × место × видимость», огрубление координат, счётчики только из видимых чекинов.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(40);

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

-- Имена мест, которые видит зритель в поиске (по алфавиту).
create function pg_temp.search_names(p_types public.place_type[] default null) returns text[]
language sql as $$
  select coalesce(array_agg(s.name order by s.name), '{}')
    from public.places_search(null, p_types, 'name', null, null, 100) s;
$$;

-- Места редакции в этих тестах не нужны.
delete from public.places where owner_id = private.editorial_id();

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'f@test.local'),
  ('33333333-3333-3333-3333-333333333333', 's@test.local'),
  ('44444444-4444-4444-4444-444444444444', 'b@test.local');

update public.profiles set username = 'owner_a'    where id = '11111111-1111-1111-1111-111111111111';
update public.profiles set username = 'friend_f'   where id = '22222222-2222-2222-2222-222222222222';
update public.profiles set username = 'stranger_s' where id = '33333333-3333-3333-3333-333333333333';
update public.profiles set username = 'blocked_b'  where id = '44444444-4444-4444-4444-444444444444';

insert into public.friendships (user_id, friend_id) values
  ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222'),
  ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111');
insert into public.blocks (blocker_id, blocked_id) values
  ('11111111-1111-1111-1111-111111111111', '44444444-4444-4444-4444-444444444444');

insert into public.places (id, owner_id, type, name, geom, visibility, approximate, status, deleted_at) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'water_body',
   'Публичное озеро', st_setsrid(st_makepoint(77.00, 43.90), 4326), 'public', false, 'published', null),
  ('aaaaaaaa-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'fishing_spot',
   'Приблизительная коса', st_setsrid(st_makepoint(77.05, 43.90), 4326), 'public', true, 'published', null),
  ('aaaaaaaa-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'fishing_spot',
   'Для друзей', st_setsrid(st_makepoint(77.10, 43.90), 4326), 'friends', false, 'published', null),
  ('aaaaaaaa-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111', 'fishing_spot',
   'Тайная яма', st_setsrid(st_makepoint(77.20, 43.90), 4326), 'private', false, 'published', null),
  ('aaaaaaaa-0000-0000-0000-000000000005', '11111111-1111-1111-1111-111111111111', 'fishing_spot',
   'На модерации', st_setsrid(st_makepoint(77.25, 43.90), 4326), 'public', false, 'pending', null),
  ('aaaaaaaa-0000-0000-0000-000000000006', '11111111-1111-1111-1111-111111111111', 'fishing_spot',
   'Удалённое', st_setsrid(st_makepoint(77.27, 43.90), 4326), 'public', false, 'published', now()),
  ('aaaaaaaa-0000-0000-0000-000000000007', '44444444-4444-4444-4444-444444444444', 'campsite',
   'Стоянка B', st_setsrid(st_makepoint(77.30, 43.90), 4326), 'public', false, 'published', null),
  ('aaaaaaaa-0000-0000-0000-000000000008', '33333333-3333-3333-3333-333333333333', 'spring',
   'Родник S', st_setsrid(st_makepoint(77.40, 43.90), 4326), 'public', false, 'published', null),
  -- В ~80 м от настоящей точки приблизительной косы: смещённый центр косы всегда дальше (200–800 м).
  ('aaaaaaaa-0000-0000-0000-000000000009', '22222222-2222-2222-2222-222222222222', 'fishing_spot',
   'Рядом с косой', st_setsrid(st_makepoint(77.051, 43.90), 4326), 'public', false, 'published', null);

-- Чекины: F — публичный подтверждённый с фото; A — секретный с фото (позже); S — «для друзей»
-- (друзей у S нет); F — в месте «для друзей».
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
insert into public.checkins (id, place_id, at, geom, visibility) values
  ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
   now() - interval '10 minutes', st_setsrid(st_makepoint(77.00, 43.90), 4326), 'public'),
  ('cccccccc-0000-0000-0000-000000000004', 'aaaaaaaa-0000-0000-0000-000000000003',
   now() - interval '20 minutes', null, 'friends');
insert into public.media (id, checkin_id, width, height) values
  ('eeeeeeee-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001', 1600, 1200);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.checkins (id, place_id, at, visibility) values
  ('cccccccc-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001', now() - interval '1 minute', 'private');
insert into public.media (id, checkin_id, width, height) values
  ('eeeeeeee-0000-0000-0000-000000000002', 'cccccccc-0000-0000-0000-000000000002', 1600, 1200);

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
insert into public.checkins (id, place_id, at, visibility) values
  ('cccccccc-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000001', now() - interval '5 minutes', 'friends');

-- Кто что видит в поиске --------------------------------------------------------------------------

select pg_temp.act_as_anon();
select is(pg_temp.search_names(),
  array['Приблизительная коса', 'Публичное озеро', 'Родник S', 'Рядом с косой', 'Стоянка B'],
  'гость: только публичные опубликованные места');

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is(pg_temp.search_names(),
  array['Приблизительная коса', 'Публичное озеро', 'Родник S', 'Рядом с косой', 'Стоянка B'],
  'чужой: публичные и свои');

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is(pg_temp.search_names(),
  array['Для друзей', 'Приблизительная коса', 'Публичное озеро', 'Родник S', 'Рядом с косой', 'Стоянка B'],
  'друг: ещё и места «для друзей»');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(pg_temp.search_names(),
  array['Для друзей', 'На модерации', 'Приблизительная коса', 'Публичное озеро', 'Родник S', 'Рядом с косой',
        'Тайная яма'],
  'автор: все свои (и на модерации), без удалённых и без мест заблокированного');

select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select is(pg_temp.search_names(),
  array['Родник S', 'Рядом с косой', 'Стоянка B'],
  'заблокированный не видит мест A');

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is(pg_temp.search_names(array['spring']::public.place_type[]),
  array['Родник S'], 'фильтр по типу');

select is(
  (select count(*) from public.places_search('Тайная', null, null, null, null, 10)),
  0::bigint, 'чужой не находит секретное место по названию');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  (select count(*) from public.places_search('тайная', null, null, null, null, 10)),
  1::bigint, 'автор находит своё секретное место (без учёта регистра)');

select is(
  (select array_agg(s.name) from public.places_search('публичнае озро', null, null, null, null, 10) s),
  array['Публичное озеро'], 'поиск прощает опечатки');

-- Огрубление ----------------------------------------------------------------------------------------

-- Настоящая точка и смещённый центр — от имени администратора (зрителю их таблица не отдаёт).
select pg_temp.act_as_admin();
create temp table approx_place as
  select approx_center, geom from public.places where id = 'aaaaaaaa-0000-0000-0000-000000000002';
grant select on approx_place to authenticated;

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select ok(
  (select s.approximate and s.radius_m = 1000
          and st_equals(st_setsrid(st_makepoint(s.lon, s.lat), 4326),
                        (select approx_center from approx_place))
     from public.places_search('Приблизительная', null, null, null, null, 10) s),
  'чужой получает смещённый центр приблизительного места');

select is(
  (select s.distance_m
     from public.places_search('Приблизительная', null, 'distance', 77.05, 43.90, 10) s),
  (select round(st_distance(approx_center::geography, geom::geography))::integer from approx_place),
  'расстояние — до смещённого центра, а не до настоящей точки');

-- Встав в настоящую точку косы, S не должен увидеть её первой: сортировка — по смещённому центру.
select is(
  public.places_discover(77.05, 43.90)->'nearby'->0->>'name', 'Рядом с косой',
  'рядом: порядок по смещённому центру, настоящая точка не выдаётся');
select is(
  (select s.name from public.places_search(null, null, 'distance', 77.05, 43.90, 1) s),
  'Рядом с косой', 'поиск по расстоянию: то же');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select ok(
  (select not s.approximate and s.lon = 77.05 and s.lat = 43.90
     from public.places_search('Приблизительная', null, null, null, null, 10) s),
  'автор видит своё место точно');

-- Счётчики, фото, друзья -----------------------------------------------------------------------------

select pg_temp.act_as_anon();
select is(
  (select s.reports_30d from public.places_search('Публичное озеро', null, null, null, null, 1) s),
  1, 'гость: в счётчике только публичный чекин');
select is(
  (select s.photo_path from public.places_search('Публичное озеро', null, null, null, null, 1) s),
  '22222222-2222-2222-2222-222222222222/eeeeeeee-0000-0000-0000-000000000001_thumb.jpg',
  'гость: фото из публичного чекина, а не из более свежего секретного');

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is(
  (select s.reports_30d from public.places_search('Публичное озеро', null, null, null, null, 1) s),
  2, 'S: публичный чекин и свой');
select is(
  (select s.friends from public.places_search('Публичное озеро', null, null, null, null, 1) s),
  '[]'::jsonb, 'S: друзей здесь нет');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  (select s.reports_30d from public.places_search('Публичное озеро', null, null, null, null, 1) s),
  2, 'A: свой секретный и публичный F, без «для друзей» чужого S');
select is(
  (select jsonb_path_query_array(s.friends, '$[*].username')
     from public.places_search('Публичное озеро', null, null, null, null, 1) s),
  '["friend_f"]'::jsonb, 'A: здесь был друг F');

-- Подборки ------------------------------------------------------------------------------------------

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is(
  (select array_agg(x->>'name' order by x->>'name')
     from jsonb_array_elements(public.places_discover(77.00, 43.90)->'nearby') x),
  array['Приблизительная коса', 'Публичное озеро', 'Рядом с косой', 'Стоянка B'],
  'рядом: видимые чужие места, без своих');
select is(
  public.places_discover(77.00, 43.90)->'friends', '[]'::jsonb,
  'у S нет друзей — секция пустая');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  (select array_agg(x->>'name' order by x->>'name')
     from jsonb_array_elements(public.places_discover()->'friends') x),
  array['Для друзей', 'Публичное озеро'],
  'где были друзья: места с видимыми чекинами F');

select pg_temp.act_as_anon();
select is(public.places_discover()->'nearby', '[]'::jsonb, 'без точки «рядом» пустая');
select is(public.places_discover()->'friends', '[]'::jsonb, 'у гостя «где были друзья» пустая');
select is(
  (select array_agg(x->>'name') from jsonb_array_elements(public.places_discover()->'popular') x),
  array['Публичное озеро'],
  'популярные: только место с публичным подтверждённым чекином');
select is(
  (select array_agg(x->>'name') from jsonb_array_elements(public.places_discover()->'fresh') x),
  array['Публичное озеро'],
  'свежие отчёты: только видимые гостю чекины');

-- Сохранённые -------------------------------------------------------------------------------------

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is(public.save_place('aaaaaaaa-0000-0000-0000-000000000001', true), true, 'S сохраняет публичное место');
select lives_ok($$ select public.save_place('aaaaaaaa-0000-0000-0000-000000000001', true) $$,
  'повторное сохранение — без ошибки');
select is(
  (select array_agg(s.name) from public.my_saved_places() s where s.saved),
  array['Публичное озеро'], 'S видит его в сохранённых');
select throws_ok($$ select public.save_place('aaaaaaaa-0000-0000-0000-000000000004', true) $$,
  'P0002', null, 'чужое секретное место сохранить нельзя');
select throws_ok($$ select public.save_place('aaaaaaaa-0000-0000-0000-000000000003', true) $$,
  'P0002', null, 'чужое место «для друзей» не другу сохранить нельзя');
select throws_ok($$ insert into public.saved_places (owner_id, place_id)
                   values ('33333333-3333-3333-3333-333333333333', 'aaaaaaaa-0000-0000-0000-000000000002') $$,
  '42501', null, 'напрямую в таблицу писать нельзя');

select pg_temp.act_as_anon();
select throws_ok($$ select public.save_place('aaaaaaaa-0000-0000-0000-000000000001', true) $$,
  '42501', null, 'гость не сохраняет места');

-- Место стало секретным — из сохранённых пропадает.
select pg_temp.act_as_admin();
update public.places set visibility = 'private' where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is((select count(*) from public.my_saved_places()), 0::bigint,
  'место, которое больше не видно, в сохранённых не показывается');

-- Подборки редакции ------------------------------------------------------------------------------

select pg_temp.act_as_admin();
insert into public.place_collections (id, slug, title, published) values
  ('bbbbbbbb-0000-0000-0000-000000000001', 'test_open', '{"ru": "Тест"}', true),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'test_hidden', '{"ru": "Скрытая"}', false);
insert into public.place_collection_items (collection_id, place_id) values
  ('bbbbbbbb-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000002'),
  ('bbbbbbbb-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000004'),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000002');

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is(
  (select array_agg(s.name) from public.place_collection('bbbbbbbb-0000-0000-0000-000000000001') s),
  array['Приблизительная коса'], 'в подборке — только видимые места');
select is(
  (select count(*) from public.place_collection('bbbbbbbb-0000-0000-0000-000000000002')),
  0::bigint, 'скрытая подборка пустая');
select is(
  (select array_agg(x->>'slug') from jsonb_array_elements(public.places_discover()->'recommended') x),
  array['test_open'], 'в «рекомендуемых» — только опубликованные подборки');

-- Ошибки ----------------------------------------------------------------------------------------------

select throws_ok($$ select public.places_discover(77.0, null) $$, '22023', null, 'точка без широты');
select throws_ok($$ select * from public.places_search(null, null, 'loudest') $$, '22023', null, 'неизвестная сортировка');

select * from finish();
rollback;
