-- Экипировка, чеклисты и шаблоны сборов (M5b): своё видит и меняет только владелец,
-- «последняя правка побеждает», проверка пунктов и лимиты; шаблоны читают все.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(33);

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

-- Шаблоны ---------------------------------------------------------------------------------------

select pg_temp.act_as_anon();

select is(
  (select count(*)::integer from public.checklist_templates),
  6,
  'гость видит шесть шаблонов редакции'
);

select pg_temp.act_as_admin();

select is_empty(
  $$ select t.id, i ->> 'id'
       from public.checklist_templates t, jsonb_array_elements(t.items) i
      where not (i ->> 'category' = any (enum_range(null::public.gear_category)::text[]))
         or coalesce(btrim(i ->> 'title_ru'), '') = ''
         or coalesce(btrim(i ->> 'title_kk'), '') = ''
         or coalesce(btrim(i ->> 'title_en'), '') = ''
         or not private.checklist_items_valid(jsonb_build_array(
              jsonb_build_object('id', i ->> 'id', 'title', i ->> 'title_ru'))) $$,
  'у каждого пункта шаблона — категория и название на трёх языках'
);

select is_empty(
  $$ select i ->> 'id'
       from public.checklist_templates t, jsonb_array_elements(t.items) i
      group by i ->> 'id'
     having count(distinct (i ->> 'category', i ->> 'title_ru', i ->> 'title_kk', i ->> 'title_en')) > 1 $$,
  'один предмет называется одинаково во всех шаблонах'
);

select is_empty(
  $$ select id from public.checklist_templates
      where btrim(title_kk) = '' or btrim(title_en) = '' or jsonb_array_length(items) = 0 $$,
  'у шаблонов есть переводы и пункты'
);

-- Экипировка: доступ -----------------------------------------------------------------------------

select pg_temp.act_as_anon();

select throws_ok(
  $$ select * from public.gear_items $$,
  '42501', null,
  'гость не читает экипировку'
);
select throws_ok(
  $$ insert into public.gear_items (name) values ('Удилище') $$,
  '42501', null,
  'гость не создаёт экипировку на сервере'
);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');

select lives_ok(
  $$ insert into public.gear_items (id, name, category, brand, weight_grams, quantity, status, updated_at)
     values ('aaaaaaaa-0000-0000-0000-000000000001', 'Фидер 3,6 м', 'rods', 'Shimano', 310, 2, 'ok',
             now() - interval '1 hour') $$,
  'владелец добавляет предмет'
);
select throws_ok(
  $$ insert into public.gear_items (id, owner_id, name)
     values ('aaaaaaaa-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'Чужой') $$,
  '42501', null,
  'владельца не выбрать'
);
select throws_ok(
  $$ insert into public.gear_items (name, synced_at) values ('Катушка', now() - interval '1 year') $$,
  '42501', null,
  'время синхронизации ставит только сервер'
);
select throws_ok(
  $$ update public.gear_items set owner_id = '22222222-2222-2222-2222-222222222222' $$,
  '42501', null,
  'владельца не сменить'
);

select pg_temp.act_as_admin();

select is(
  (select owner_id from public.gear_items where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  '11111111-1111-1111-1111-111111111111'::uuid,
  'владелец — автор запроса'
);

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');

select is_empty(
  $$ select id from public.gear_items $$,
  'чужую экипировку не видно'
);

update public.gear_items set name = 'Взлом' where id = 'aaaaaaaa-0000-0000-0000-000000000001';

select throws_ok(
  $$ insert into public.gear_items (id, name) values ('aaaaaaaa-0000-0000-0000-000000000001', 'Взлом')
     on conflict (id) do update set name = excluded.name $$,
  '42501', null,
  'чужой предмет не перезаписать через upsert'
);

select pg_temp.act_as_admin();

select is(
  (select name from public.gear_items where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'Фидер 3,6 м',
  'чужой не меняет предмет'
);

-- Экипировка: последняя правка побеждает ----------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');

update public.gear_items set name = 'Старая правка', updated_at = now() - interval '2 hours'
 where id = 'aaaaaaaa-0000-0000-0000-000000000001';

select is(
  (select name from public.gear_items where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'Фидер 3,6 м',
  'правка старше сохранённой не применяется'
);

insert into public.gear_items (id, name, category, updated_at)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'Фидер 3,9 м', 'rods', now() - interval '30 minutes')
on conflict (id) do update
  set name = excluded.name, category = excluded.category, updated_at = excluded.updated_at;

select is(
  (select name from public.gear_items where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'Фидер 3,9 м',
  'свежая правка через upsert применяется'
);

select is(
  (select brand from public.gear_items where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'Shimano',
  'поля, которых нет в правке, не стираются'
);

insert into public.gear_items (id, name, updated_at)
values ('aaaaaaaa-0000-0000-0000-000000000003', 'Палатка', now() + interval '1 day');

select is(
  (select updated_at from public.gear_items where id = 'aaaaaaaa-0000-0000-0000-000000000003'),
  now(),
  'правка «из будущего» (спешат часы) считается сделанной сейчас'
);

update public.gear_items set deleted_at = now(), updated_at = now()
 where id = 'aaaaaaaa-0000-0000-0000-000000000003';

select isnt(
  (select deleted_at from public.gear_items where id = 'aaaaaaaa-0000-0000-0000-000000000003'),
  null,
  'удалённый предмет остаётся с пометкой — о нём узнают другие устройства'
);

select throws_ok(
  $$ insert into public.gear_items (name, quantity) values ('Грузила', 0) $$,
  '23514', null,
  'количество — от 1'
);

-- Чеклисты ---------------------------------------------------------------------------------------

select lives_ok(
  $$ insert into public.checklists (id, kind, title, template_id, trip_date, remind_minutes, items)
     values ('cccccccc-0000-0000-0000-000000000001', 'packing', 'Капшагай, суббота', 'fishing_day',
             current_date + 3, 20 * 60,
             '[{"id": "rods", "title": "Удилища", "category": "rods", "checked": true},
               {"id": "x1", "title": "Сачок", "category": null, "gear_id": null, "checked": false},
               {"id": "x2", "title": "Кофе"}]') $$,
  'владелец создаёт сборы с пунктами'
);

select throws_ok(
  $$ insert into public.checklists (title, items) values ('Плохо', '{"id": "a"}') $$,
  '23514', null,
  'пункты — только массив'
);
select throws_ok(
  $$ insert into public.checklists (title, items) values ('Плохо', '[{"id": "a", "title": "  "}]') $$,
  '23514', null,
  'у пункта должно быть название'
);
select throws_ok(
  $$ insert into public.checklists (title, items) values ('Плохо', '[{"id": "a", "title": "Нож", "checked": "да"}]') $$,
  '23514', null,
  'отметка пункта — да или нет'
);
select throws_ok(
  $$ insert into public.checklists (title, items)
     select 'Плохо', jsonb_agg(jsonb_build_object('id', 'i' || g, 'title', 'Пункт ' || g))
       from generate_series(1, 301) g $$,
  '23514', null,
  'не больше 300 пунктов'
);
select throws_ok(
  $$ insert into public.checklists (title, remind_minutes) values ('Плохо', 1440) $$,
  '23514', null,
  'время напоминания — в пределах суток'
);

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');

select is_empty(
  $$ select id from public.checklists $$,
  'чужие чеклисты не видно'
);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');

update public.checklists
   set items = '[{"id": "rods", "title": "Удилища", "checked": false}]', updated_at = now() - interval '1 day'
 where id = 'cccccccc-0000-0000-0000-000000000001';

select is(
  (select jsonb_array_length(items) from public.checklists where id = 'cccccccc-0000-0000-0000-000000000001'),
  3,
  'опоздавшая правка чеклиста не затирает свежую'
);

select lives_ok(
  $$ update public.checklists set items = 'null'::jsonb, updated_at = now() - interval '1 day'
      where id = 'cccccccc-0000-0000-0000-000000000001' $$,
  'опоздавшая правка отбрасывается до проверки пунктов'
);

-- Лимиты -----------------------------------------------------------------------------------------

insert into public.checklists (title) select 'Чеклист ' || g from generate_series(1, 199) g;

select throws_ok(
  $$ insert into public.checklists (title) values ('Двести первый') $$,
  'DL004', null,
  'не больше 200 чеклистов'
);

update public.checklists set deleted_at = now() where title = 'Чеклист 1';

select lives_ok(
  $$ insert into public.checklists (title) values ('Вместо удалённого') $$,
  'удалённые чеклисты не считаются'
);

insert into public.gear_items (name) select 'Предмет ' || g from generate_series(1, 999) g;

select throws_ok(
  $$ insert into public.gear_items (name) values ('Тысяча первый') $$,
  'DL004', null,
  'не больше 1000 предметов экипировки'
);

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');

select lives_ok(
  $$ insert into public.gear_items (name) values ('Свой предмет') $$,
  'лимит считается для каждого отдельно'
);

select * from finish();
rollback;
