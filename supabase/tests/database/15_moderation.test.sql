-- Модерация (M6a): фильтр грубых слов в том, что видят другие; жалобы — только на видимое и не на
-- своё, одна на объект, лимит в сутки; таблица жалоб клиенту закрыта.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(26);

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

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local', '{}'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.local', '{}'),
  ('33333333-3333-3333-3333-333333333333', 'c@test.local', '{"full_name": "Иван Сукин"}');

-- Фильтр: словарь ---------------------------------------------------------------------------------

select is(
  (select array_agg(w order by w) from unnest(array['бля', 'Ну ты и сука!', 'ЗАЕБАЛ', 'xуй', 'пиздец', 'Fuck you', 'долбоёб']) w
    where private.has_banned_words(w)),
  (select array_agg(w order by w) from unnest(array['бля', 'Ну ты и сука!', 'ЗАЕБАЛ', 'xуй', 'пиздец', 'Fuck you', 'долбоёб']) w),
  'грубые слова находятся, в том числе латиницей вместо кириллицы'
);
select is_empty(
  $$ select w from unnest(array['рубля', 'бляха', 'хлеба', 'обед', 'подъезд', 'сукно', 'художник', 'страхуйте',
                                'похудеть', 'Сукин', 'shiitake', 'Scunthorpe', 'Охота на сазана']) w
      where private.has_banned_words(w) $$,
  'обычные слова, похожие на грубые, проходят'
);

-- Фильтр: в том, что видят другие -----------------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');

select throws_ok(
  $$ insert into public.places (type, name, geom, visibility)
     values ('fishing_spot', 'Место для мудаков', 'SRID=4326;POINT(77.00 43.90)', 'public') $$,
  'DL005', null,
  'публичное место с грубым названием не создаётся'
);
select lives_ok(
  $$ insert into public.places (id, type, name, geom, visibility)
     values ('aaaaaaaa-0000-0000-0000-000000000009', 'fishing_spot', 'Моё, блядь, место', 'SRID=4326;POINT(77.00 43.90)', 'private') $$,
  'в личном месте (видно только автору) текст не проверяется'
);
select throws_ok(
  $$ update public.places set visibility = 'friends' where id = 'aaaaaaaa-0000-0000-0000-000000000009' $$,
  'DL005', null,
  'личное место с грубым названием не открыть друзьям'
);
select lives_ok(
  $$ insert into public.places (id, type, name, description, geom, visibility)
     values ('aaaaaaaa-0000-0000-0000-000000000001', 'fishing_spot', 'Залив у рубля', 'Бляха на столбе',
             'SRID=4326;POINT(77.00 43.95)', 'public') $$,
  'обычный текст проходит'
);
select throws_ok(
  $$ update public.profiles set display_name = 'Fucking fisherman' where id = '11111111-1111-1111-1111-111111111111' $$,
  'DL005', null,
  'имя в профиле проверяется'
);

select pg_temp.act_as_admin();

select is(
  (select display_name from public.profiles where id = '33333333-3333-3333-3333-333333333333'),
  'Иван Сукин',
  'регистрация не ломается из-за фамилии'
);

update public.places set status = 'published' where id = 'aaaaaaaa-0000-0000-0000-000000000001';

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');

select throws_ok(
  $$ insert into public.checkins (place_id, note, visibility)
     values ('aaaaaaaa-0000-0000-0000-000000000001', 'Нихуя не клюёт', 'public') $$,
  'DL005', null,
  'заметка открытого чекина проверяется'
);
select lives_ok(
  $$ insert into public.checkins (id, place_id, note, visibility)
     values ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'Клюёт у камыша', 'public') $$,
  'обычная заметка проходит'
);
select throws_ok(
  $$ insert into public.threads (place_id, title, body)
     values ('aaaaaaaa-0000-0000-0000-000000000001', 'Кто тут был', 'Какой пиздец на дороге') $$,
  'DL005', null,
  'текст обсуждения проверяется'
);
select lives_ok(
  $$ insert into public.threads (id, place_id, title, body)
     values ('dddddddd-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'Дорога', 'Проехать можно') $$,
  'обычное обсуждение создаётся'
);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');

select throws_ok(
  $$ insert into public.thread_posts (thread_id, body) values ('dddddddd-0000-0000-0000-000000000001', 'Иди нахуй') $$,
  'DL005', null,
  'ответ в обсуждении проверяется'
);

-- Жалобы ------------------------------------------------------------------------------------------

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');

select lives_ok(
  $$ select public.report_content('place', 'aaaaaaaa-0000-0000-0000-000000000001', 'false_info', 'Такого места нет') $$,
  'жалоба на публичное место'
);
select lives_ok(
  $$ select public.report_content('place', 'aaaaaaaa-0000-0000-0000-000000000001', 'spam') $$,
  'повторная жалоба обновляет причину'
);
select throws_ok(
  $$ select public.report_content('place', 'aaaaaaaa-0000-0000-0000-000000000009', 'spam') $$,
  'P0002', null,
  'на чужое личное место (его не видно) пожаловаться нельзя'
);
select throws_ok(
  $$ select public.report_content('checkin', 'cccccccc-0000-0000-0000-000000000001', 'spam') $$,
  '22023', null,
  'на своё пожаловаться нельзя'
);
select lives_ok(
  $$ select public.report_content('user', '11111111-1111-1111-1111-111111111111', 'abuse') $$,
  'жалоба на человека'
);
select throws_ok(
  $$ select * from public.reports $$,
  '42501', null,
  'жалобы клиенту не видны'
);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');

select lives_ok(
  $$ select public.report_content('thread', 'dddddddd-0000-0000-0000-000000000001', 'abuse', 'Оскорбления') $$,
  'жалоба на обсуждение'
);
select lives_ok(
  $$ select public.report_content('checkin', 'cccccccc-0000-0000-0000-000000000001', 'poaching') $$,
  'жалоба на чекин'
);

select pg_temp.act_as_anon();

select throws_ok(
  $$ select public.report_content('place', 'aaaaaaaa-0000-0000-0000-000000000001', 'spam') $$,
  '42501', null,
  'гость не жалуется'
);

select pg_temp.act_as_admin();

select is(
  (select array[count(*)::integer, count(*) filter (where reason = 'spam')::integer]
     from public.reports where target_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  array[1, 1],
  'одна жалоба от человека на объект — с последней причиной'
);
select is(
  (select target_owner_id from public.reports where target_kind = 'checkin'),
  '22222222-2222-2222-2222-222222222222'::uuid,
  'в жалобе запомнен автор контента'
);
select is(
  (select count(*)::integer from private.moderation_queue),
  4,
  'очередь редакции — по объектам'
);

-- Лимит: 20 жалоб в сутки.
insert into auth.users (id, email)
select ('00000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid, 'u' || g || '@test.local'
  from generate_series(1, 21) g;

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select public.report_content('user', ('00000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid, 'spam')
  from generate_series(1, 18) g;

select throws_ok(
  $$ select public.report_content('user', '00000000-0000-0000-0000-000000000021', 'spam') $$,
  'DL003', null,
  'не больше 20 жалоб в сутки'
);

select * from finish();
rollback;
