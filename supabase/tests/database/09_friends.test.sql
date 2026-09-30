-- Поиск людей, запросы в друзья, отмена запроса, список блокировок.
-- A — ищет, B — Арман (arman), C — Арсен (arsen_c), D — заблокирован A, E — без username.

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

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local', '{"full_name":"Алия"}'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.local', '{"full_name":"Арман Сейтов"}'),
  ('33333333-3333-3333-3333-333333333333', 'c@test.local', '{"full_name":"Арсен"}'),
  ('44444444-4444-4444-4444-444444444444', 'd@test.local', '{"full_name":"Арман Блок"}'),
  ('55555555-5555-5555-5555-555555555555', 'e@test.local', '{"full_name":"Арман Без Имени"}');
update public.profiles set username = 'aliya' where id = '11111111-1111-1111-1111-111111111111';
update public.profiles set username = 'arman' where id = '22222222-2222-2222-2222-222222222222';
update public.profiles set username = 'arsen_c' where id = '33333333-3333-3333-3333-333333333333';
update public.profiles set username = 'armanblock' where id = '44444444-4444-4444-4444-444444444444';

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.blocks (blocked_id) values ('44444444-4444-4444-4444-444444444444');

-- Поиск --------------------------------------------------------------------------------------

select is(
  (select array_agg(username order by username) from public.search_profiles('ar')),
  array['arman', 'arsen_c'],
  'поиск по началу username: без себя, заблокированных и тех, кто без username'
);
select is(
  (select array_agg(username) from public.search_profiles('@ARM')),
  array['arman'],
  '«@» и регистр в запросе не мешают'
);
select is(
  (select array_agg(username) from public.search_profiles('сейтов')),
  array['arman'],
  'поиск по части имени'
);
select is_empty($$ select * from public.search_profiles('a') $$, 'один символ — не ищем');
select is_empty($$ select * from public.search_profiles('a%') $$, '«%» — обычный символ, а не шаблон');
select is(
  (select array_agg(username) from public.search_profiles('arsen_')),
  array['arsen_c'],
  '«_» — обычный символ'
);

select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select is_empty($$ select * from public.search_profiles('aliya') $$,
  'заблокированный не находит того, кто его заблокировал');

-- Запросы ------------------------------------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(public.send_friend_request('22222222-2222-2222-2222-222222222222'), 'sent', 'A отправляет запрос B');
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is(public.send_friend_request('11111111-1111-1111-1111-111111111111'), 'sent', 'C отправляет запрос A');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  (select array_agg(direction || ':' || username order by username) from public.my_friend_requests()),
  array['outgoing:arman', 'incoming:arsen_c'],
  'A видит исходящий запрос к B и входящий от C'
);
select is(
  (select request_status from public.search_profiles('arman')),
  'outgoing',
  'в поиске виден статус запроса'
);

-- B не может отменить чужой запрос, A — может.
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select public.cancel_friend_request(
  (select id from public.friend_requests where from_user = '11111111-1111-1111-1111-111111111111'
                                         and to_user = '22222222-2222-2222-2222-222222222222'));
select is(
  (select count(*) from public.my_friend_requests()),
  1::bigint,
  'получатель не может отменить запрос — он остаётся входящим'
);
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select public.cancel_friend_request(
  (select request_id from public.my_friend_requests() where direction = 'outgoing'));
select is(
  (select array_agg(direction) from public.my_friend_requests()),
  array['incoming'],
  'отправитель отменяет свой запрос'
);

-- Блокировки ---------------------------------------------------------------------------------

select is(
  (select array_agg(username) from public.my_blocks()),
  array['armanblock'],
  'в списке блокировок — username заблокированного'
);

select * from finish();
rollback;
