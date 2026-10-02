-- M10c: комментарии к постам, фото профиля, уведомления о комментариях и постах друзей.
-- A — автор постов, F — друг A, S — чужой, B — заблокирован A.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(37);

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

-- Тексты видимых комментариев поста (по алфавиту: в одной транзакции время у всех одно).
create function pg_temp.bodies(p_kind public.reaction_target, p_target uuid) returns text[] language sql as $$
  select coalesce(array_agg(body order by body), '{}') from public.post_comments(p_kind, p_target);
$$;

create function pg_temp.pushes(p_user uuid, p_kind public.push_kind) returns integer language sql as $$
  select count(*)::integer from private.push_outbox where user_id = p_user and kind = p_kind;
$$;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'f@test.local'),
  ('33333333-3333-3333-3333-333333333333', 's@test.local'),
  ('44444444-4444-4444-4444-444444444444', 'b@test.local');
update public.profiles set username = 'author_a', display_name = 'Автор' where id = '11111111-1111-1111-1111-111111111111';
update public.profiles set username = 'friend_f' where id = '22222222-2222-2222-2222-222222222222';

insert into public.friendships (user_id, friend_id) values
  ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222'),
  ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111');
insert into public.blocks (blocker_id, blocked_id) values
  ('11111111-1111-1111-1111-111111111111', '44444444-4444-4444-4444-444444444444');

-- Устройства: уведомления кладутся в очередь только тем, у кого они есть.
insert into public.devices (user_id, token, environment) values
  ('11111111-1111-1111-1111-111111111111', repeat('a1', 32), 'production'),
  ('22222222-2222-2222-2222-222222222222', repeat('b2', 32), 'production'),
  ('33333333-3333-3333-3333-333333333333', repeat('c3', 32), 'production');

-- Поездка A «для друзей», публичное место S с публичным отчётом S.
insert into public.trips (id, owner_id, title, started_at, ended_at, visibility) values
  ('77777777-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Поездка A',
   now() - interval '3 hours', now() - interval '1 hour', 'friends');
insert into public.places (id, owner_id, type, name, geom, visibility, status) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', 'water_body', 'Озеро S',
   'SRID=4326;POINT(77.10 43.90)', 'public', 'published');
insert into public.checkins (id, owner_id, place_id, visibility) values
  ('cccccccc-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333',
   'aaaaaaaa-0000-0000-0000-000000000001', 'public');

-- Комментарии -----------------------------------------------------------------------------------

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select lives_ok(
  $$ insert into public.comments (target_kind, target_id, body)
     values ('trip', '77777777-0000-0000-0000-000000000001', '  Отличный улов!  ') $$,
  'друг комментирует поездку «для друзей»'
);

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select throws_ok(
  $$ insert into public.comments (target_kind, target_id, body)
     values ('trip', '77777777-0000-0000-0000-000000000001', 'Привет') $$,
  'P0002', null,
  'чужой не комментирует пост, которого не видит'
);
select is(pg_temp.bodies('trip', '77777777-0000-0000-0000-000000000001'), '{}'::text[],
  'и комментариев к нему не видит');

select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select throws_ok(
  $$ insert into public.comments (target_kind, target_id, body)
     values ('trip', '77777777-0000-0000-0000-000000000001', 'Привет') $$,
  'P0002', null,
  'заблокированный не комментирует'
);

-- B комментирует публичный отчёт S (S его не блокировал), затем A.
select lives_ok(
  $$ insert into public.comments (target_kind, target_id, body)
     values ('checkin', 'cccccccc-0000-0000-0000-000000000001', 'Комментарий B') $$,
  'B комментирует публичный отчёт S'
);
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.comments (target_kind, target_id, body)
values ('checkin', 'cccccccc-0000-0000-0000-000000000001', 'Комментарий A');

select throws_ok(
  $$ insert into public.comments (target_kind, target_id, body)
     values ('post', 'aaaaaaaa-0000-0000-0000-000000000001', 'Ответ') $$,
  '22023', null,
  'комментарии — только к поездке, отчёту и отзыву'
);

select is(
  pg_temp.bodies('trip', '77777777-0000-0000-0000-000000000001'),
  array['Отличный улов!'],
  'автор видит комментарий друга (пробелы обрезаны)'
);

select is(
  pg_temp.bodies('checkin', 'cccccccc-0000-0000-0000-000000000001'),
  array['Комментарий A'],
  'комментарии заблокированного не видны'
);

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is(
  pg_temp.bodies('checkin', 'cccccccc-0000-0000-0000-000000000001'),
  array['Комментарий A', 'Комментарий B'],
  'автор отчёта видит все комментарии'
);

select pg_temp.act_as_anon();
select is(
  pg_temp.bodies('checkin', 'cccccccc-0000-0000-0000-000000000001'),
  array['Комментарий A', 'Комментарий B'],
  'гость видит комментарии публичного отчёта'
);
select is(pg_temp.bodies('trip', '77777777-0000-0000-0000-000000000001'), '{}'::text[],
  'но не поездки «для друзей»');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(
  (select array_agg(target_kind::text || ':' || comments_count order by target_kind)
     from public.comment_summary(
       array['trip', 'checkin']::public.reaction_target[],
       array['77777777-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001']::uuid[])),
  array['trip:1', 'checkin:1'],
  'число комментариев — без заблокированных'
);

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is(
  (select array_agg(target_kind::text || ':' || comments_count order by target_kind)
     from public.comment_summary(
       array['trip', 'checkin']::public.reaction_target[],
       array['77777777-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001']::uuid[])),
  array['checkin:2'],
  'у невидимого поста числа нет'
);

select is(
  (select array_agg(coalesce(author_username, '-') || ':' || can_delete order by body)
     from public.post_comments('checkin', 'cccccccc-0000-0000-0000-000000000001')),
  array['author_a:true', '-:true'],
  'автор поста может удалить любой комментарий под ним'
);

-- Правка и удаление
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
update public.comments set body = 'Отличный улов, поздравляю!'
 where target_id = '77777777-0000-0000-0000-000000000001';
select pg_temp.act_as_admin();
select ok(
  (select edited_at is not null and owner_id = '22222222-2222-2222-2222-222222222222'
     from public.comments where target_id = '77777777-0000-0000-0000-000000000001'),
  'правка своего комментария отмечается'
);

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select throws_ok(
  $$ update public.comments set target_id = 'cccccccc-0000-0000-0000-000000000001' $$,
  '42501', null,
  'пост комментария не меняется'
);

select pg_temp.act_as_admin();
create temp table comment_a as select id from public.comments where body = 'Комментарий A';
grant select on comment_a to authenticated;

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select throws_ok(
  $$ select public.delete_comment((select id from comment_a)) $$,
  'P0002', null,
  'чужой комментарий под чужим постом не удалить'
);
select throws_ok(
  $$ select public.delete_comment(gen_random_uuid()) $$,
  'P0002', null,
  'несуществующий комментарий'
);

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select lives_ok(
  $$ select public.delete_comment(c.id) from public.post_comments('checkin', 'cccccccc-0000-0000-0000-000000000001') c
      where c.body = 'Комментарий B' $$,
  'автор поста удаляет чужой комментарий'
);
select is(
  pg_temp.bodies('checkin', 'cccccccc-0000-0000-0000-000000000001'),
  array['Комментарий A'],
  'удалённый комментарий не виден'
);

-- Фильтр слов
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select throws_ok(
  $$ insert into public.comments (target_kind, target_id, body)
     values ('trip', '77777777-0000-0000-0000-000000000001', 'what the fuck') $$,
  'DL005', null,
  'грубые слова в комментарии не принимаются'
);

-- Жалоба на комментарий
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select lives_ok(
  $$ select public.report_content('comment', c.id, 'abuse')
       from public.post_comments('checkin', 'cccccccc-0000-0000-0000-000000000001') c $$,
  'на чужой комментарий можно пожаловаться'
);
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select throws_ok(
  $$ select public.report_content('comment', c.id, 'abuse')
       from public.post_comments('checkin', 'cccccccc-0000-0000-0000-000000000001') c $$,
  '22023', null,
  'на свой — нельзя'
);

-- Уведомления о комментариях
select pg_temp.act_as_admin();
select is(pg_temp.pushes('11111111-1111-1111-1111-111111111111', 'comment'), 1,
  'автору поездки — уведомление о комментарии друга');
select is(
  (select payload ->> 'target_id' from private.push_outbox
    where user_id = '11111111-1111-1111-1111-111111111111' and kind = 'comment'),
  '77777777-0000-0000-0000-000000000001',
  'со ссылкой на пост'
);
select is(pg_temp.pushes('33333333-3333-3333-3333-333333333333', 'comment'), 2,
  'автору отчёта — о каждом комментарии');

-- Посты друзей ----------------------------------------------------------------------------------

-- Новая поездка F «для друзей» — уведомление A; секретная — нет; вторая подряд — нет (3 часа).
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
insert into public.trips (id, title, started_at, ended_at, visibility) values
  ('77777777-0000-0000-0000-000000000002', 'Поездка F',
   now() - interval '2 hours', now() - interval '10 minutes', 'friends'),
  ('77777777-0000-0000-0000-000000000003', 'Секретная F',
   now() - interval '2 hours', now() - interval '5 minutes', 'private');

select pg_temp.act_as_admin();
select is(pg_temp.pushes('11111111-1111-1111-1111-111111111111', 'friend_post'), 1,
  'новая поездка друга — уведомление');
select is(
  (select payload ->> 'title' from private.push_outbox
    where user_id = '11111111-1111-1111-1111-111111111111' and kind = 'friend_post'),
  'Поездка F',
  'с названием поездки'
);
select is(pg_temp.pushes('33333333-3333-3333-3333-333333333333', 'friend_post'), 0,
  'не друзьям — нет');

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
update public.trips set visibility = 'friends' where id = '77777777-0000-0000-0000-000000000003';
select pg_temp.act_as_admin();
select is(pg_temp.pushes('11111111-1111-1111-1111-111111111111', 'friend_post'), 1,
  'вторая поездка того же друга в течение трёх часов — без уведомления');

-- Отчёт F: A выключил уведомления о постах друзей — нет.
update public.profiles set notify_friend_posts = false where id = '11111111-1111-1111-1111-111111111111';
delete from private.push_outbox where kind = 'friend_post';
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
insert into public.checkins (place_id, visibility)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'friends');
select pg_temp.act_as_admin();
select is(pg_temp.pushes('11111111-1111-1111-1111-111111111111', 'friend_post'), 0,
  'уведомления о постах друзей можно выключить');

-- Включил обратно: отчёт друга в месте, которого A не видит, — без уведомления.
update public.profiles set notify_friend_posts = true where id = '11111111-1111-1111-1111-111111111111';
insert into public.places (id, owner_id, type, name, geom, visibility, status) values
  ('aaaaaaaa-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'fishing_spot', 'Секрет F',
   'SRID=4326;POINT(77.20 43.90)', 'private', 'published');
select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
insert into public.checkins (place_id, visibility)
values ('aaaaaaaa-0000-0000-0000-000000000002', 'friends');
select pg_temp.act_as_admin();
select is(pg_temp.pushes('11111111-1111-1111-1111-111111111111', 'friend_post'), 0,
  'отчёт в секретном месте друга — без уведомления');

-- Фото профиля ----------------------------------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select throws_ok(
  $$ update public.profiles set avatar_path = '22222222-2222-2222-2222-222222222222/aaaaaaaa-1111-1111-1111-111111111111.jpg'
      where id = '11111111-1111-1111-1111-111111111111' $$,
  '23514', null,
  'фото профиля — только из своей папки'
);
select lives_ok(
  $$ update public.profiles set avatar_path = '11111111-1111-1111-1111-111111111111/aaaaaaaa-1111-1111-1111-111111111111.jpg'
      where id = '11111111-1111-1111-1111-111111111111' $$,
  'своё фото профиля'
);

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select ok(
  rls.can_read_media_object('11111111-1111-1111-1111-111111111111/aaaaaaaa-1111-1111-1111-111111111111.jpg')
  and not rls.can_read_media_object('11111111-1111-1111-1111-111111111111/aaaaaaaa-2222-2222-2222-222222222222.jpg')
  and not rls.can_read_media_object('11111111-1111-1111-1111-111111111111/aaaaaaaa-1111-1111-1111-111111111111_thumb.jpg'),
  'вошедший видит фото профиля, но не другие файлы из папки'
);

select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select ok(
  not rls.can_read_media_object('11111111-1111-1111-1111-111111111111/aaaaaaaa-1111-1111-1111-111111111111.jpg'),
  'заблокированный фото профиля не видит'
);

select pg_temp.act_as_anon();
select ok(
  not rls.can_read_media_object('11111111-1111-1111-1111-111111111111/aaaaaaaa-1111-1111-1111-111111111111.jpg'),
  'гость — тоже (ему инициалы)'
);

select * from finish();
rollback;
