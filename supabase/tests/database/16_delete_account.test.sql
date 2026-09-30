-- Удаление аккаунта (M6b): удаляется только свой аккаунт и всё своё; чужое остаётся.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(9);

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

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.local');

-- Б: публичное место и обсуждение; А: чекин, отзыв, ответ, жалоба, экипировка; дружба.
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
insert into public.places (id, type, name, geom, visibility)
values ('aaaaaaaa-0000-0000-0000-000000000002', 'fishing_spot', 'Место Б', 'SRID=4326;POINT(77.00 43.90)', 'public');

select pg_temp.act_as_admin();
update public.places set status = 'published' where id = 'aaaaaaaa-0000-0000-0000-000000000002';
insert into public.friendships (user_id, friend_id) values
  ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222'),
  ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111');

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
insert into public.threads (id, place_id, title, body)
values ('dddddddd-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000002', 'Дорога', 'Как проехать?');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.places (type, name, geom, visibility)
values ('campsite', 'Своё место А', 'SRID=4326;POINT(77.10 43.90)', 'private');
insert into public.checkins (place_id, visibility) values ('aaaaaaaa-0000-0000-0000-000000000002', 'public');
select public.save_review('aaaaaaaa-0000-0000-0000-000000000002', 5, 'Хорошо');
insert into public.thread_posts (thread_id, body) values ('dddddddd-0000-0000-0000-000000000002', 'Через мост');
select public.report_content('place', 'aaaaaaaa-0000-0000-0000-000000000002', 'false_info');
insert into public.gear_items (name) values ('Удочка');

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select public.report_content('user', '11111111-1111-1111-1111-111111111111', 'abuse');

-- Удаление -----------------------------------------------------------------------------------------

select pg_temp.act_as_anon();
select throws_ok(
  $$ select public.delete_my_account() $$,
  '42501', null,
  'гость ничего не удаляет'
);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select lives_ok($$ select public.delete_my_account() $$, 'человек удаляет свой аккаунт');

select pg_temp.act_as_admin();

select is_empty(
  $$ select id from auth.users where id = '11111111-1111-1111-1111-111111111111' $$,
  'пользователя в Auth больше нет'
);
select is_empty(
  $$ select id from public.profiles where id = '11111111-1111-1111-1111-111111111111' $$,
  'профиля больше нет'
);
select is(
  (select array[
     (select count(*) from public.places where owner_id = '11111111-1111-1111-1111-111111111111'),
     (select count(*) from public.checkins where owner_id = '11111111-1111-1111-1111-111111111111'),
     (select count(*) from public.reviews where owner_id = '11111111-1111-1111-1111-111111111111'),
     (select count(*) from public.thread_posts where owner_id = '11111111-1111-1111-1111-111111111111'),
     (select count(*) from public.gear_items where owner_id = '11111111-1111-1111-1111-111111111111'),
     (select count(*) from public.friendships
       where user_id = '11111111-1111-1111-1111-111111111111' or friend_id = '11111111-1111-1111-1111-111111111111')
   ]::integer[]),
  array[0, 0, 0, 0, 0, 0],
  'места, чекины, отзывы, ответы, экипировка и дружба удалены'
);
select is(
  (select count(*)::integer from public.reports where reporter_id = '11111111-1111-1111-1111-111111111111'),
  0,
  'свои жалобы удалены'
);
select is(
  (select target_owner_id from public.reports where target_kind = 'user'),
  null,
  'жалоба другого человека на удалённого остаётся, без ссылки на автора'
);
select isnt_empty(
  $$ select id from public.places where id = 'aaaaaaaa-0000-0000-0000-000000000002' $$,
  'чужое место остаётся'
);
select isnt_empty(
  $$ select id from public.threads where id = 'dddddddd-0000-0000-0000-000000000002' $$,
  'чужое обсуждение остаётся'
);

select * from finish();
rollback;
