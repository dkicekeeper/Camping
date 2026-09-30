-- Отзывы, обсуждения и реакции (M4c).
-- A — автор мест, F — друг A, S — чужой, B — заблокирован A.
-- P — публичное место A, Q — место A «для друзей», P2 — публичное место S.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(55);

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
update public.profiles set username = 'author' where id = '11111111-1111-1111-1111-111111111111';
update public.profiles set username = 'friend' where id = '22222222-2222-2222-2222-222222222222';

insert into public.friendships (user_id, friend_id) values
  ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222'),
  ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.blocks (blocked_id) values ('44444444-4444-4444-4444-444444444444');
insert into public.places (id, type, name, geom, visibility) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'fishing_spot', 'Публичное P', 'SRID=4326;POINT(77.00 43.90)', 'public'),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'campsite', 'Для друзей Q', 'SRID=4326;POINT(77.10 43.90)', 'friends');

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
insert into public.places (id, type, name, geom, visibility) values
  ('aaaaaaaa-0000-0000-0000-000000000003', 'water_body', 'Публичное P2', 'SRID=4326;POINT(77.20 43.90)', 'public');

select pg_temp.act_as_admin();
update public.places set status = 'published'
 where id in ('aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000003');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.checkins (id, place_id, at, visibility) values
  ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', now() - interval '3 days', 'public'),
  ('cccccccc-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000002', now() - interval '3 days', 'friends');
insert into public.trips (id, title, started_at, ended_at, visibility) values
  ('77777777-0000-0000-0000-000000000001', 'Для друзей', now() - interval '2 days', now() - interval '1 day', 'friends');

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
insert into public.checkins (place_id) values ('aaaaaaaa-0000-0000-0000-000000000001');

select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
insert into public.checkins (place_id) values ('aaaaaaaa-0000-0000-0000-000000000003');

-- Отзывы: запись ------------------------------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select lives_ok(
  $$ select public.save_review('aaaaaaaa-0000-0000-0000-000000000001', 5, '  Отлично, сазан клюёт  ') $$,
  'автор с чекином оставляет отзыв'
);
select ok(
  (select body = 'Отлично, сазан клюёт'
          and visited_on = ((now() - interval '3 days') at time zone 'Asia/Almaty')::date
          and edited_at is null
     from public.reviews where place_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'текст без пробелов по краям; дата визита — день последнего чекина'
);
select is(
  public.save_review('aaaaaaaa-0000-0000-0000-000000000001', 4, 'Отлично, но людно'),
  (select id from public.reviews where place_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'повторное сохранение правит тот же отзыв'
);
select public.save_review('aaaaaaaa-0000-0000-0000-000000000001', 4, 'Отлично, но людно');
select throws_ok(
  $$ select public.save_review('aaaaaaaa-0000-0000-0000-000000000002', 5) $$,
  'DL002', null,
  'в месте «для друзей» отзывов нет'
);
select throws_ok(
  $$ select public.save_review('aaaaaaaa-0000-0000-0000-000000000001', 6) $$,
  '22023', null,
  'оценка — от 1 до 5'
);
select throws_ok(
  $$ select public.save_review('aaaaaaaa-0000-0000-0000-000000000001', 5, null, current_date + 3) $$,
  '22023', null,
  'дата визита не в будущем'
);
select throws_ok(
  $$ insert into public.reviews (owner_id, place_id, rating) values
       ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-0000-0000-0000-000000000001', 5) $$,
  '42501', null,
  'напрямую в таблицу отзывы не пишутся'
);

select pg_temp.act_as_admin();
select is(
  (select count(*)::integer from private.review_revisions),
  1,
  'правка сохраняет прежнюю версию, повтор без изменений — нет'
);
select ok(
  (select edited_at is not null and rating = 4 from public.reviews
    where place_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'правленый отзыв помечен'
);

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select throws_ok(
  $$ select public.save_review('aaaaaaaa-0000-0000-0000-000000000001', 1, 'Не был, но осуждаю') $$,
  'DL001', null,
  'без чекина в месте отзыв не оставить'
);

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select lives_ok(
  $$ select public.save_review('aaaaaaaa-0000-0000-0000-000000000001', 3, 'Нормально') $$,
  'друг с чекином тоже оставляет отзыв'
);

select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select lives_ok(
  $$ select public.save_review('aaaaaaaa-0000-0000-0000-000000000003', 2, 'Мусорно') $$,
  'заблокированный пишет отзыв о чужом (не A) месте'
);
select throws_ok(
  $$ select public.save_review('aaaaaaaa-0000-0000-0000-000000000001', 1) $$,
  'DL002', null,
  'в месте того, кто заблокировал, отзыв не оставить'
);

-- Отзывы: чтение --------------------------------------------------------------------------------

select pg_temp.act_as_anon();
select is(
  (select array_agg(rating order by created_at, author_username)
     from public.place_reviews('aaaaaaaa-0000-0000-0000-000000000001')),
  array[4, 3]::smallint[],
  'гость видит отзывы публичного места'
);
select is(
  (select array_agg(author_username) from public.place_reviews('aaaaaaaa-0000-0000-0000-000000000001', 'low')),
  array['friend', 'author'],
  'сортировка: сначала низкие'
);
select ok(
  (select reviews_count = 2 and rating_avg = 3.5 and stars = array[0, 0, 1, 1, 0] and not can_review
          and my_review_id is null
     from public.place_review_summary('aaaaaaaa-0000-0000-0000-000000000001')),
  'сводка: число, средняя, распределение по звёздам'
);
select is_empty(
  $$ select * from public.place_review_summary('aaaaaaaa-0000-0000-0000-000000000002') $$,
  'у места «для друзей» сводки отзывов нет'
);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select ok(
  (select can_review and my_rating = 4 and my_body = 'Отлично, но людно'
     from public.place_review_summary('aaaaaaaa-0000-0000-0000-000000000001')),
  'автор видит свой отзыв и может его править'
);
select is_empty(
  $$ select * from public.place_reviews('aaaaaaaa-0000-0000-0000-000000000003') $$,
  'отзыв заблокированного не виден'
);

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is(
  (select count(*)::integer from public.place_reviews('aaaaaaaa-0000-0000-0000-000000000003')),
  1,
  'остальным отзыв заблокированного виден'
);

select pg_temp.act_as_anon();
select ok(
  (select bool_and(is_own is not null and not is_own)
     from public.places_in_bbox(76.9, 43.8, 77.3, 44.0)),
  'гостю места на карте приходят с is_own = false, а не null'
);
select ok(
  (select is_own is not null and not is_own from public.place_card('aaaaaaaa-0000-0000-0000-000000000001'))
  and (select count(*) = 1 and bool_and(is_own is not null and not is_own)
         from public.place_reports('aaaaaaaa-0000-0000-0000-000000000001')),
  'карточка и отчёты места у гостя — тоже с is_own = false'
);

-- Реакции ----------------------------------------------------------------------------------------

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is(
  public.set_reaction('review', (select review_id from public.place_reviews('aaaaaaaa-0000-0000-0000-000000000001') where author_username = 'author'), true),
  1,
  'друг отмечает отзыв «полезно»'
);
select ok(
  (select author_username = 'author' and helpful_count = 1 and marked_helpful
     from public.place_reviews('aaaaaaaa-0000-0000-0000-000000000001', 'helpful') limit 1),
  'сортировка по полезности; своя отметка видна'
);
select is(
  public.set_reaction('trip', '77777777-0000-0000-0000-000000000001', true),
  1,
  'друг ставит «респект» поездке для друзей'
);
select is(
  public.set_reaction('trip', '77777777-0000-0000-0000-000000000001', true),
  1,
  'повторная реакция не удваивается'
);
select is(
  (select array_agg(target_kind::text || ':' || reactions_count || ':' || reacted order by target_kind)
     from public.reaction_summary(
       array['trip', 'checkin']::public.reaction_target[],
       array['77777777-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001']::uuid[])),
  array['trip:1:true', 'checkin:0:false'],
  'сводка реакций по списку объектов'
);
select throws_ok(
  $$ select public.set_reaction('checkin', (select id from public.checkins limit 1), true) $$,
  '22023', null,
  'на своё реакцию не поставить'
);

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select throws_ok(
  $$ select public.set_reaction('trip', '77777777-0000-0000-0000-000000000001', true) $$,
  'P0002', null,
  'на невидимую поездку реакцию не поставить'
);
select is_empty(
  $$ select * from public.reaction_summary(array['trip']::public.reaction_target[],
                                             array['77777777-0000-0000-0000-000000000001']::uuid[]) $$,
  'реакции невидимого объекта не отдаются'
);

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is(
  public.set_reaction('trip', '77777777-0000-0000-0000-000000000001', false),
  0,
  'реакцию можно снять'
);

select pg_temp.act_as_anon();
select throws_ok(
  $$ select public.set_reaction('trip', '77777777-0000-0000-0000-000000000001', true) $$,
  '42501', null,
  'гость реакции не ставит'
);

-- Удаление и восстановление отзыва ----------------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select lives_ok(
  $$ select public.delete_review((select id from public.reviews where place_id = 'aaaaaaaa-0000-0000-0000-000000000001')) $$,
  'автор удаляет отзыв'
);
select is(
  (select reviews_count from public.place_review_summary('aaaaaaaa-0000-0000-0000-000000000001')),
  1,
  'удалённый отзыв не считается'
);
select is(
  public.save_review('aaaaaaaa-0000-0000-0000-000000000001', 5),
  (select id from public.reviews where place_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'новый отзыв после удаления — та же запись'
);
select ok(
  (select deleted_at is null and edited_at is null and rating = 5
     from public.reviews where place_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'восстановленный отзыв — как новый, без пометки о правке'
);

-- Лента: отзывы друзей ---------------------------------------------------------------------------

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select ok(
  (select data->>'rating' = '5' and data->>'place_name' = 'Публичное P'
     from public.friends_feed(20) where kind = 'review'),
  'отзыв друга — в ленте'
);

-- Обсуждения -------------------------------------------------------------------------------------

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select lives_ok(
  $$ insert into public.threads (id, place_id, title, body) values
       ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
        ' Как проехать после дождя? ', 'Кто был на этой неделе — дорога живая?') $$,
  'обсуждение начинает любой, без чекина'
);
select throws_ok(
  $$ insert into public.threads (place_id, title, body) values
       ('aaaaaaaa-0000-0000-0000-000000000002', 'Вопрос', 'Текст') $$,
  'DL002', null,
  'в месте «для друзей» обсуждений нет'
);
select throws_ok(
  $$ insert into public.threads (place_id, title, body) values
       ('aaaaaaaa-0000-0000-0000-000000000001', 'Ок', 'Текст') $$,
  '23514', null,
  'заголовок — от 3 символов'
);
select throws_ok(
  $$ insert into public.threads (owner_id, place_id, title, body) values
       ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-0000-0000-0000-000000000001', 'Чужое имя', 'Текст') $$,
  '42501', null,
  'автора обсуждения задать нельзя'
);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.thread_posts (id, thread_id, body) values
  ('eeeeeeee-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000001', 'Вчера проехал на седане');

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select lives_ok(
  $$ insert into public.thread_posts (id, thread_id, body, quote_post_id) values
       ('eeeeeeee-0000-0000-0000-000000000002', 'dddddddd-0000-0000-0000-000000000001',
        'Подтверждаю', 'eeeeeeee-0000-0000-0000-000000000001') $$,
  'ответ с цитатой'
);

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
insert into public.threads (id, place_id, title, body) values
  ('dddddddd-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000003', 'Где наживка?', 'Рядом есть магазин?');
select throws_ok(
  $$ insert into public.thread_posts (thread_id, body, quote_post_id) values
       ('dddddddd-0000-0000-0000-000000000003', 'Цитата не отсюда', 'eeeeeeee-0000-0000-0000-000000000001') $$,
  '22023', null,
  'цитировать можно только ответ из того же обсуждения'
);
select is(
  (select posts_count from public.threads where id = 'dddddddd-0000-0000-0000-000000000001'),
  2,
  'счётчик ответов'
);

select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select throws_ok(
  $$ insert into public.thread_posts (thread_id, body) values ('dddddddd-0000-0000-0000-000000000001', 'Привет') $$,
  'P0002', null,
  'в обсуждении места того, кто заблокировал, не ответить'
);
insert into public.thread_posts (thread_id, body) values ('dddddddd-0000-0000-0000-000000000003', 'Есть, у трассы');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.thread_posts (thread_id, body) values ('dddddddd-0000-0000-0000-000000000003', 'Спасибо');
select is(
  (select array_agg(body) from public.thread_posts('dddddddd-0000-0000-0000-000000000003')),
  array['Спасибо'],
  'ответы заблокированного не видны'
);
select is(
  public.set_reaction('post', 'eeeeeeee-0000-0000-0000-000000000002', true),
  1,
  'реакция на ответ'
);

select pg_temp.act_as_anon();
select ok(
  (select title = 'Как проехать после дождя?' and posts_count = 2
     from public.place_threads('aaaaaaaa-0000-0000-0000-000000000001')),
  'гость видит обсуждения публичного места; заголовок без пробелов по краям'
);
select ok(
  (select quote->>'author_username' = 'author' and quote->>'body' = 'Вчера проехал на седане'
          and reactions_count = 1 and not reacted
     from public.thread_posts('dddddddd-0000-0000-0000-000000000001')
    where post_id = 'eeeeeeee-0000-0000-0000-000000000002'),
  'ответ с цитатой и числом реакций'
);
select is(
  (select array_agg(post_id) from public.thread_posts('dddddddd-0000-0000-0000-000000000001', 50,
     (select created_at from public.thread_posts('dddddddd-0000-0000-0000-000000000001') limit 1),
     'eeeeeeee-0000-0000-0000-000000000001')),
  array['eeeeeeee-0000-0000-0000-000000000002']::uuid[],
  'следующая страница ответов'
);
select ok(
  (select place_name = 'Публичное P' and not is_own from public.thread_view('dddddddd-0000-0000-0000-000000000001')),
  'обсуждение целиком — с названием места'
);

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
update public.thread_posts set deleted_at = now() where id = 'eeeeeeee-0000-0000-0000-000000000002';
select is(
  (select posts_count from public.place_threads('aaaaaaaa-0000-0000-0000-000000000001')),
  1,
  'удалённый ответ не считается и не показывается'
);

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
update public.threads set deleted_at = now() where id = 'dddddddd-0000-0000-0000-000000000001';
select is_empty(
  $$ select * from public.place_threads('aaaaaaaa-0000-0000-0000-000000000001') $$,
  'удалённое обсуждение скрыто'
);
select lives_ok(
  $$ insert into public.threads (place_id, title, body)
     select 'aaaaaaaa-0000-0000-0000-000000000003', 'Вопрос ' || i, 'Текст' from generate_series(1, 3) i $$,
  'до 5 обсуждений в день'
);
select throws_ok(
  $$ insert into public.threads (place_id, title, body) values ('aaaaaaaa-0000-0000-0000-000000000003', 'Шестое', 'Текст') $$,
  'DL003', null,
  'шестое обсуждение за день не создаётся'
);

select * from finish();
rollback;
