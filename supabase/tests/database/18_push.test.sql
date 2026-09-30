-- Пуш-уведомления (M6d): устройства — только свои и только через RPC; уведомления — тем, у кого
-- есть устройство, не себе и не между заблокированными; очередь забирает только service_role.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(25);

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

create function pg_temp.act_as_service() returns void language plpgsql as $$
begin
  perform set_config('role', 'service_role', true);
  perform set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
end $$;

create function pg_temp.act_as_admin() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

create function pg_temp.token(n integer) returns text language sql as $$
  select repeat(lpad(to_hex(n), 2, '0'), 32);
$$;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.local'),
  ('33333333-3333-3333-3333-333333333333', 'c@test.local'),
  ('44444444-4444-4444-4444-444444444444', 'd@test.local');
update public.profiles set username = 'author', display_name = 'Автор' where id = '11111111-1111-1111-1111-111111111111';
update public.profiles set username = 'bob' where id = '22222222-2222-2222-2222-222222222222';

-- Устройства ------------------------------------------------------------------------------------

select pg_temp.act_as_anon();
select throws_ok(
  $$ select public.register_device(pg_temp.token(1), 'production') $$,
  '42501', null,
  'гость не регистрирует устройство'
);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select lives_ok(
  $$ select public.register_device(upper(pg_temp.token(1)), 'production', 'kk') $$,
  'человек регистрирует телефон'
);
select throws_ok(
  $$ select public.register_device('not-a-token', 'production') $$,
  '22023', null,
  'неверный токен не принимается'
);
select throws_ok(
  $$ select * from public.devices $$,
  '42501', null,
  'устройства клиенту не видны'
);

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select public.register_device(pg_temp.token(2), 'sandbox', 'ru');
select public.unregister_device(pg_temp.token(1));

select pg_temp.act_as_admin();
select is(
  (select array[user_id::text, environment::text, language] from public.devices where token = pg_temp.token(1)),
  array['11111111-1111-1111-1111-111111111111', 'production', 'kk'],
  'токен сохранён в нижнем регистре; чужой токен не удалить'
);

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select public.register_device(pg_temp.token(3), 'production');
select public.register_device(pg_temp.token(3), 'production');
select public.register_device(pg_temp.token(4), 'production');

select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select public.register_device(pg_temp.token(4), 'production');

select pg_temp.act_as_admin();
select is(
  (select user_id from public.devices where token = pg_temp.token(4)),
  '44444444-4444-4444-4444-444444444444'::uuid,
  'телефон перешёл к другому аккаунту — токен теперь его'
);

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select public.register_device(pg_temp.token(g), 'production') from generate_series(10, 22) g;

select pg_temp.act_as_admin();
select is(
  (select count(*)::integer from public.devices where user_id = '33333333-3333-3333-3333-333333333333'),
  10,
  'не больше 10 устройств на человека'
);

-- Обсуждения ------------------------------------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.places (id, type, name, geom, visibility)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'fishing_spot', 'Залив', 'SRID=4326;POINT(77.00 43.90)', 'public');

select pg_temp.act_as_admin();
update public.places set status = 'published' where id = 'aaaaaaaa-0000-0000-0000-000000000001';

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.threads (id, place_id, title, body)
values ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'Дорога', 'Как проехать?');
insert into public.thread_posts (id, thread_id, body)
values ('eeeeeeee-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000001', 'Сам себе отвечаю');

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
insert into public.thread_posts (id, thread_id, body)
values ('eeeeeeee-0000-0000-0000-000000000002', 'dddddddd-0000-0000-0000-000000000001', 'Через мост у    Бакбакты');

select pg_temp.act_as_admin();
select is(
  (select count(*)::integer from private.push_outbox),
  1,
  'свой ответ в своём обсуждении — без уведомления'
);
select is(
  (select array[user_id::text, kind::text, payload ->> 'actor', payload ->> 'username', payload ->> 'snippet', payload ->> 'title']
     from private.push_outbox),
  array['11111111-1111-1111-1111-111111111111', 'thread_reply', '@bob', 'bob', 'Через мост у Бакбакты', 'Дорога'],
  'автор обсуждения получает ответ: кто, текст, обсуждение'
);

-- Ответ с цитатой: автору процитированного ответа (Б) тоже; у В телефонов 10.
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
insert into public.thread_posts (thread_id, body, quote_post_id)
values ('dddddddd-0000-0000-0000-000000000001', 'Согласен', 'eeeeeeee-0000-0000-0000-000000000002');

select pg_temp.act_as_admin();
select is(
  (select array_agg(user_id::text order by user_id) from private.push_outbox where payload ->> 'snippet' = 'Согласен'),
  array['11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222'],
  'автор обсуждения и автор процитированного ответа'
);

-- Блокировка: Г заблокировал А — уведомлений между ними нет (писать в обсуждениях друг друга
-- заблокированные и так не могут).
select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
insert into public.blocks (blocked_id) values ('11111111-1111-1111-1111-111111111111');

select pg_temp.act_as_admin();
delete from private.push_outbox;
select private.push_enqueue('11111111-1111-1111-1111-111111111111', '44444444-4444-4444-4444-444444444444', 'thread_reply', '{}');
select private.push_enqueue('44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111', 'friend_request', '{}');
select is_empty(
  $$ select id from private.push_outbox $$,
  'между заблокированными уведомлений нет'
);

-- Друзья ----------------------------------------------------------------------------------------

delete from private.push_outbox;
insert into public.friend_requests (id, from_user, to_user)
values ('ffffffff-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111');

select is(
  (select array[user_id::text, kind::text, payload ->> 'username'] from private.push_outbox),
  array['11111111-1111-1111-1111-111111111111', 'friend_request', 'bob'],
  'запрос в друзья — получателю, со ссылкой на профиль'
);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select public.respond_friend_request('ffffffff-0000-0000-0000-000000000001', true);

select pg_temp.act_as_admin();
select is(
  (select array[user_id::text, payload ->> 'actor'] from private.push_outbox where kind = 'friend_accept'),
  array['22222222-2222-2222-2222-222222222222', 'Автор'],
  'запрос принят — отправителю'
);

-- Отправка --------------------------------------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select throws_ok(
  $$ select * from public.push_claim() $$,
  '42501', null,
  'забрать очередь может только сервер'
);

select pg_temp.act_as_service();
create temporary table claimed on commit drop as select * from public.push_claim(100);

select is(
  (select count(*)::integer from claimed),
  2,
  'по строке на уведомление и устройство получателя'
);
select is(
  (select array_agg(token || ':' || environment::text || ':' || language order by outbox_id) from claimed),
  array[pg_temp.token(1) || ':production:kk', pg_temp.token(2) || ':sandbox:ru'],
  'с токеном, окружением и языком устройства'
);
select is_empty(
  $$ select * from public.push_claim(100) $$,
  'взятое в работу не отдаётся повторно в ту же минуту'
);

select lives_ok(
  $$ select public.push_finish(
       array[(select min(outbox_id) from claimed)],
       array[pg_temp.token(2)],
       jsonb_build_object((select max(outbox_id) from claimed)::text, 'BadDeviceToken')
     ) $$,
  'сервер отчитывается об отправке'
);

select pg_temp.act_as_admin();
select is(
  (select count(*)::integer from private.push_outbox where sent_at is not null),
  1,
  'доставленное помечено'
);
select is(
  (select last_error from private.push_outbox where id = (select max(outbox_id) from claimed)),
  'BadDeviceToken',
  'ошибка записана'
);
select is_empty(
  $$ select token from public.devices where token = pg_temp.token(2) $$,
  'токен, который APNs не принимает, удалён'
);
select lives_ok(
  $$ select private.push_kick() $$,
  'без настроенных секретов вызов функции просто пропускается'
);
select is(
  (select count(*)::integer from net.http_request_queue),
  0,
  'и запрос не отправляется'
);

select vault.create_secret('http://127.0.0.1:9/functions/v1/push', 'push_function_url');
select vault.create_secret('test-secret', 'push_worker_secret');
select private.push_kick();
select is(
  (select array[url, headers ->> 'x-push-secret'] from net.http_request_queue),
  array['http://127.0.0.1:9/functions/v1/push', 'test-secret'],
  'с секретами — вызывает функцию отправки с общим секретом'
);
select is(
  (select jobname || ' ' || schedule from cron.job where command = 'select private.push_kick()'),
  'push-worker * * * * *',
  'отправка запускается раз в минуту'
);

select * from finish();
rollback;
