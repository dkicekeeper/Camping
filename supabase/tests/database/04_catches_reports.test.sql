-- Уловы и свежие отчёты места: видимость, скрытие веса, привязка к чекину и месту.
-- A — владелец мест, F — друг A, S — чужой, B — заблокирован A, гость.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(22);

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

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'f@test.local'),
  ('33333333-3333-3333-3333-333333333333', 's@test.local'),
  ('44444444-4444-4444-4444-444444444444', 'b@test.local');
update public.profiles set username = 'owner_a' where id = '11111111-1111-1111-1111-111111111111';
update public.profiles set username = 'friend_f' where id = '22222222-2222-2222-2222-222222222222';
update public.profiles set username = 'stranger_s' where id = '33333333-3333-3333-3333-333333333333';

-- Места A: публичное, для друзей, секретное.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.places (id, type, name, geom, visibility) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'fishing_spot', 'Публичное', 'SRID=4326;POINT(77.00 43.90)', 'public'),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'fishing_spot', 'Для друзей', 'SRID=4326;POINT(77.10 43.90)', 'friends'),
  ('aaaaaaaa-0000-0000-0000-000000000003', 'fishing_spot', 'Секретное', 'SRID=4326;POINT(77.20 43.90)', 'private');
insert into public.blocks (blocked_id) values ('44444444-4444-4444-4444-444444444444');

select pg_temp.act_as_admin();
update public.places set status = 'published';
insert into public.friendships (user_id, friend_id) values
  ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222'),
  ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111');

-- Справочник рыб -----------------------------------------------------------------------------

select pg_temp.act_as_anon();
select ok((select count(*) from public.fish_species) >= 16, 'справочник рыб доступен гостю');

-- F: чекин в месте «для друзей» и два улова, у одного скрыт размер.
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
insert into public.checkins (id, place_id, geom, conditions, note, visibility) values
  ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000002',
   'SRID=4326;POINT(77.10 43.9005)', '{"bite": "good"}', 'Клюёт с утра', 'friends');
insert into public.catches (id, checkin_id, species_id, weight_g, length_mm, count, hide_size, visibility) values
  ('dddddddd-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001', 'pike', 2500, 650, 1, true, 'public'),
  ('dddddddd-0000-0000-0000-000000000002', 'cccccccc-0000-0000-0000-000000000001', 'perch', 300, null, 5, false, 'friends');

select is(
  (select place_id from public.catches where id = 'dddddddd-0000-0000-0000-000000000001'),
  'aaaaaaaa-0000-0000-0000-000000000002'::uuid,
  'место улова берётся из чекина'
);
select is(
  (select visibility from public.catches where id = 'dddddddd-0000-0000-0000-000000000001'),
  'friends'::public.visibility,
  'улов не может быть видимее места'
);
select throws_ok(
  $$ insert into public.catches (species_id) values ('no_such_fish') $$,
  '23503', null,
  'вид рыбы должен быть из справочника'
);
select ok(
  (select weight_g = 2500 and length_mm = 650 from public.my_catches() where id = 'dddddddd-0000-0000-0000-000000000001'),
  'автор видит скрытый размер в «Моих уловах»'
);
select is(
  (select place_name from public.my_catches() where id = 'dddddddd-0000-0000-0000-000000000001'),
  'Для друзей',
  'в «Моих уловах» есть название места'
);

-- Чужой не может привязать улов к чужому чекину.
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select throws_ok(
  $$ insert into public.catches (checkin_id, species_id) values ('cccccccc-0000-0000-0000-000000000001', 'pike') $$,
  'P0002', 'checkin not found',
  'нельзя добавить улов в чужой чекин'
);
select throws_ok(
  $$ insert into public.catches (place_id, species_id) values ('aaaaaaaa-0000-0000-0000-000000000002', 'pike') $$,
  'P0002', 'place not found',
  'нельзя добавить улов в невидимое место'
);

-- Отчёты места: A видит отчёт друга ------------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  (select count(*) from public.place_reports('aaaaaaaa-0000-0000-0000-000000000002')),
  1::bigint,
  'владелец места видит отчёт друга'
);
select ok(
  (select verified and note = 'Клюёт с утра' and conditions ->> 'bite' = 'good' and author_username = 'friend_f'
     from public.place_reports('aaaaaaaa-0000-0000-0000-000000000002')),
  'в отчёте условия, заметка, автор и подтверждение'
);
select is(
  (select jsonb_array_length(catches) from public.place_reports('aaaaaaaa-0000-0000-0000-000000000002')),
  2,
  'в отчёте оба улова'
);
select ok(
  (select e ->> 'weight_g' is null and e ->> 'length_mm' is null and (e ->> 'count')::int = 1
     from public.place_reports('aaaaaaaa-0000-0000-0000-000000000002') r,
          jsonb_array_elements(r.catches) e
    where e ->> 'species_id' = 'pike'),
  'скрытый размер чужого улова не отдаётся'
);
select ok(
  (select (e ->> 'weight_g')::int = 300 and (e ->> 'count')::int = 5
     from public.place_reports('aaaaaaaa-0000-0000-0000-000000000002') r,
          jsonb_array_elements(r.catches) e
    where e ->> 'species_id' = 'perch'),
  'открытый размер виден'
);

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select ok(
  (select e ->> 'weight_g' = '2500'
     from public.place_reports('aaaaaaaa-0000-0000-0000-000000000002') r,
          jsonb_array_elements(r.catches) e
    where e ->> 'species_id' = 'pike'),
  'автор видит свой скрытый размер в отчёте'
);

-- Чужой и гость не видят отчёты в месте «для друзей».
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is_empty($$ select * from public.place_reports('aaaaaaaa-0000-0000-0000-000000000002') $$,
  'чужой не видит отчёты в месте для друзей');

-- S отмечается в публичном месте приватно: владелец места этого не видит.
insert into public.checkins (id, place_id, visibility, note)
values ('cccccccc-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001', 'private', 'только для себя');
insert into public.checkins (id, place_id, visibility, note)
values ('cccccccc-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000001', 'public', 'всем');
select is(
  (select count(*) from public.place_reports('aaaaaaaa-0000-0000-0000-000000000001')),
  2::bigint,
  'автор видит свои отчёты любой видимости'
);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  (select note from public.place_reports('aaaaaaaa-0000-0000-0000-000000000001')),
  'всем',
  'приватный отчёт другого пользователя не виден'
);

select pg_temp.act_as_anon();
select is(
  (select count(*) from public.place_reports('aaaaaaaa-0000-0000-0000-000000000001')),
  1::bigint,
  'гость видит публичный отчёт в публичном месте'
);
select is_empty($$ select * from public.place_reports('aaaaaaaa-0000-0000-0000-000000000003') $$,
  'гость не видит отчёты секретного места');
select throws_ok('select * from public.my_catches()', '42501', null, 'гостю «Мои уловы» недоступны');

-- Заблокированный не видит отчёты в местах A.
select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select is_empty($$ select * from public.place_reports('aaaaaaaa-0000-0000-0000-000000000001') $$,
  'заблокированный не видит отчёты в местах A');

-- Улов в секретном месте всегда приватный.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.catches (id, place_id, species_id, visibility)
values ('dddddddd-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000003', 'common_carp', 'public');
select is(
  (select visibility from public.catches where id = 'dddddddd-0000-0000-0000-000000000003'),
  'private'::public.visibility,
  'улов в секретном месте всегда приватный'
);

select * from finish();
rollback;
