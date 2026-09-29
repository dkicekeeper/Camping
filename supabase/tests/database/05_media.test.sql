-- Фото: строки `media`, файлы в бакете `media`, фото в отчётах места.
-- A — автор фото, F — друг A, S — чужой, B — заблокирован A, гость.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(30);

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

-- Путь файла фото N автора A: `<A>/eeeeeeee-…-00000000000N.jpg` (или `_thumb.jpg`).
create function pg_temp.path(n integer, suffix text default '') returns text language sql as $$
  select '11111111-1111-1111-1111-111111111111/eeeeeeee-0000-0000-0000-'
         || lpad(n::text, 12, '0') || suffix || '.jpg'
$$;

-- Видит ли текущий зритель файл (проверка идёт через политики `storage.objects`).
create function pg_temp.sees(object_name text) returns boolean language sql as $$
  select exists (select 1 from storage.objects where bucket_id = 'media' and name = object_name)
$$;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'f@test.local'),
  ('33333333-3333-3333-3333-333333333333', 's@test.local'),
  ('44444444-4444-4444-4444-444444444444', 'b@test.local');

-- Места A: публичное, для друзей, публичное на модерации.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.places (id, type, name, geom, visibility) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'fishing_spot', 'Публичное', 'SRID=4326;POINT(77.00 43.90)', 'public'),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'fishing_spot', 'Для друзей', 'SRID=4326;POINT(77.10 43.90)', 'friends'),
  ('aaaaaaaa-0000-0000-0000-000000000003', 'fishing_spot', 'На проверке', 'SRID=4326;POINT(77.20 43.90)', 'public');
insert into public.blocks (blocked_id) values ('44444444-4444-4444-4444-444444444444');

-- Чекины A: публичный и для друзей в публичном месте, в месте для друзей, в месте на проверке.
insert into public.checkins (id, place_id, visibility) values
  ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'public'),
  ('cccccccc-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001', 'friends'),
  ('cccccccc-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000002', 'public'),
  ('cccccccc-0000-0000-0000-000000000004', 'aaaaaaaa-0000-0000-0000-000000000003', 'public');
-- Уловы в первом чекине: публичный и приватный.
insert into public.catches (id, checkin_id, species_id, visibility) values
  ('dddddddd-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001', 'pike', 'public'),
  ('dddddddd-0000-0000-0000-000000000002', 'cccccccc-0000-0000-0000-000000000001', 'perch', 'private');

select pg_temp.act_as_admin();
update public.places set status = 'published'
 where id in ('aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000002');
insert into public.friendships (user_id, friend_id) values
  ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222'),
  ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111');

-- Строки media ---------------------------------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select lives_ok(
  $$ insert into public.media (id, checkin_id, catch_id, width, height) values
       ('eeeeeeee-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001', null, 1600, 1200),
       ('eeeeeeee-0000-0000-0000-000000000002', 'cccccccc-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000001', 1200, 1600),
       ('eeeeeeee-0000-0000-0000-000000000003', 'cccccccc-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000002', 1600, 1200),
       ('eeeeeeee-0000-0000-0000-000000000004', 'cccccccc-0000-0000-0000-000000000002', null, 1600, 1200),
       ('eeeeeeee-0000-0000-0000-000000000005', 'cccccccc-0000-0000-0000-000000000003', null, 1600, 1200),
       ('eeeeeeee-0000-0000-0000-000000000006', 'cccccccc-0000-0000-0000-000000000004', null, 1600, 1200),
       ('eeeeeeee-0000-0000-0000-000000000007', 'cccccccc-0000-0000-0000-000000000001', null, 1600, 1200) $$,
  'автор добавляет фото к своим чекинам и уловам'
);
select is(
  (select storage_path from public.media where id = 'eeeeeeee-0000-0000-0000-000000000001'),
  pg_temp.path(1),
  'путь файла: <автор>/<id фото>.jpg'
);
select is(
  (select place_id from public.media where id = 'eeeeeeee-0000-0000-0000-000000000005'),
  'aaaaaaaa-0000-0000-0000-000000000002'::uuid,
  'место фото берётся из чекина'
);
select throws_ok(
  $$ insert into public.media (owner_id, checkin_id) values
       ('33333333-3333-3333-3333-333333333333', 'cccccccc-0000-0000-0000-000000000001') $$,
  '42501', null,
  'автора фото задать нельзя'
);
select throws_ok(
  $$ insert into public.media (checkin_id, catch_id) values
       ('cccccccc-0000-0000-0000-000000000002', 'dddddddd-0000-0000-0000-000000000001') $$,
  'P0002', 'catch not found',
  'улов фото должен быть из того же чекина'
);
select throws_ok(
  $$ update public.media set checkin_id = 'cccccccc-0000-0000-0000-000000000002'
      where id = 'eeeeeeee-0000-0000-0000-000000000001' $$,
  '42501', null,
  'фото нельзя перенести в другой чекин'
);
select lives_ok(
  $$ insert into public.media (checkin_id)
     select 'cccccccc-0000-0000-0000-000000000004' from generate_series(1, 19) $$,
  'до 20 фото на чекин'
);
select throws_ok(
  $$ insert into public.media (checkin_id) values ('cccccccc-0000-0000-0000-000000000004') $$,
  '54000', 'too many photos',
  '21-е фото на чекин не принимается'
);

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select throws_ok(
  $$ insert into public.media (checkin_id) values ('cccccccc-0000-0000-0000-000000000001') $$,
  'P0002', 'checkin not found',
  'нельзя добавить фото к чужому чекину'
);
select is_empty($$ select * from public.media $$, 'чужие строки media напрямую не читаются');

-- Файлы в бакете media -------------------------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select lives_ok(
  $$ insert into storage.objects (bucket_id, name)
     select 'media', pg_temp.path(n) from generate_series(1, 7) n
     union all select 'media', pg_temp.path(1, '_thumb')
     union all select 'media', pg_temp.path(99) $$,
  'автор загружает файлы в свою папку'
);
select throws_ok(
  $$ insert into storage.objects (bucket_id, name) values
       ('media', '33333333-3333-3333-3333-333333333333/eeeeeeee-0000-0000-0000-000000000001.jpg') $$,
  '42501', null,
  'в чужую папку загрузить нельзя'
);
select throws_ok(
  $$ insert into storage.objects (bucket_id, name) values
       ('media', '11111111-1111-1111-1111-111111111111/photo.png') $$,
  '42501', null,
  'имя файла — только <id>.jpg или <id>_thumb.jpg'
);
select ok(pg_temp.sees(pg_temp.path(3)), 'автор видит фото своего приватного улова');
select ok(pg_temp.sees(pg_temp.path(99)), 'автор видит свой файл без строки media');

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select ok(pg_temp.sees(pg_temp.path(4)) and pg_temp.sees(pg_temp.path(5)),
  'друг видит фото чекина для друзей и фото из места для друзей');
select ok(not pg_temp.sees(pg_temp.path(3)), 'друг не видит фото приватного улова');

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select ok(pg_temp.sees(pg_temp.path(1)) and pg_temp.sees(pg_temp.path(1, '_thumb')),
  'чужой видит фото и превью публичного чекина');
select ok(pg_temp.sees(pg_temp.path(2)), 'чужой видит фото публичного улова');
select ok(not pg_temp.sees(pg_temp.path(3)), 'чужой не видит фото приватного улова');
select ok(not pg_temp.sees(pg_temp.path(4)) and not pg_temp.sees(pg_temp.path(5)),
  'чужой не видит фото чекина и места для друзей');
select ok(not pg_temp.sees(pg_temp.path(6)), 'чужой не видит фото из места на модерации');
select ok(not pg_temp.sees(pg_temp.path(99)), 'файл без строки media виден только автору');
select throws_ok(
  $$ insert into storage.objects (bucket_id, name) values ('media', pg_temp.path(50)) $$,
  '42501', null,
  'чужой не может загрузить файл в папку автора'
);

select pg_temp.act_as_anon();
select ok(pg_temp.sees(pg_temp.path(1)) and not pg_temp.sees(pg_temp.path(5)),
  'гость видит только публичное фото');

select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select ok(not pg_temp.sees(pg_temp.path(1)), 'заблокированный не видит даже публичное фото');

-- Удалённое фото пропадает.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
update public.media set deleted_at = now() where id = 'eeeeeeee-0000-0000-0000-000000000007';
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select ok(not pg_temp.sees(pg_temp.path(7)), 'удалённое фото не видно');

-- Фото в отчётах места -------------------------------------------------------------------------

select is(
  (select jsonb_agg(e ->> 'id' order by e ->> 'id')
     from public.place_reports('aaaaaaaa-0000-0000-0000-000000000001') r,
          jsonb_array_elements(r.media) e),
  '["eeeeeeee-0000-0000-0000-000000000001", "eeeeeeee-0000-0000-0000-000000000002"]'::jsonb,
  'в отчётах для чужого — только видимые ему фото'
);
select ok(
  (select e ->> 'path' = pg_temp.path(1) and e ->> 'thumb_path' = pg_temp.path(1, '_thumb')
          and (e ->> 'width')::int = 1600 and e ->> 'catch_id' is null
     from public.place_reports('aaaaaaaa-0000-0000-0000-000000000001') r,
          jsonb_array_elements(r.media) e
    where e ->> 'id' = 'eeeeeeee-0000-0000-0000-000000000001'),
  'в отчёте пути к фото и превью, размеры'
);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  (select jsonb_array_length(media) from public.place_reports('aaaaaaaa-0000-0000-0000-000000000001')
    where checkin_id = 'cccccccc-0000-0000-0000-000000000001'),
  3,
  'автор видит в отчёте все свои фото, кроме удалённых'
);

select * from finish();
rollback;
