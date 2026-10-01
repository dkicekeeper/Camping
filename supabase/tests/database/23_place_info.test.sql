-- Карточка места (M8d): атрибуты места от приложения и предложения правок.
-- Атрибуты: только известные ключи и значения, служебные source/osm не трогаются, фильтр слов.
-- Предложения: «зритель × место × видимость», лимит, видимость своих строк, решение редакции.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(50);

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

-- Места A: публичное, «для друзей», на модерации, приватное, публичное из OSM; место S из OSM.
insert into public.places (id, owner_id, type, name, geom, attributes, visibility, status) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'water_body',
   'Публичное озеро', st_setsrid(st_makepoint(77.00, 43.90), 4326), '{}', 'public', 'published'),
  ('aaaaaaaa-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'fishing_spot',
   'Для друзей', st_setsrid(st_makepoint(77.10, 43.90), 4326), '{}', 'friends', 'published'),
  ('aaaaaaaa-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'fishing_spot',
   'На модерации', st_setsrid(st_makepoint(77.20, 43.90), 4326), '{}', 'public', 'pending'),
  ('aaaaaaaa-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111', 'fishing_spot',
   'Тайная яма', st_setsrid(st_makepoint(77.30, 43.90), 4326), '{}', 'private', 'published'),
  ('aaaaaaaa-0000-0000-0000-000000000005', '11111111-1111-1111-1111-111111111111', 'spring',
   'Родник из OSM', st_setsrid(st_makepoint(77.40, 43.90), 4326), '{"source": "osm", "osm": "n2"}',
   'public', 'published'),
  ('aaaaaaaa-0000-0000-0000-000000000006', '33333333-3333-3333-3333-333333333333', 'spring',
   'Родник S', st_setsrid(st_makepoint(77.50, 43.90), 4326), '{"source": "osm", "osm": "n1"}',
   'public', 'published');

-- Атрибуты: что принимается от приложения --------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');

-- Все ключи и все значения списков сразу — заодно проверка, что фильтр слов их не задевает.
select lives_ok($$
  update public.places set attributes = '{
    "species": ["pike", "perch"],
    "access": ["asphalt", "dirt", "offroad", "foot", "boat"],
    "fee": "paid", "price_kzt": 3000, "price_unit": "kg", "contact": "+7 701 000 00 00",
    "methods": ["shore", "boat", "spinning", "feeder", "float", "fly", "bottom", "ice"],
    "amenities": ["parking", "toilet", "shade", "tent", "fireplace", "drinking_water", "shop", "boat_rental"],
    "signal": "weak", "months": [5, 6, 9], "features": "Глубина до 4 м, коряги у берега"
  }' where id = 'aaaaaaaa-0000-0000-0000-000000000001'
$$, 'автор: все атрибуты с допустимыми значениями');

select lives_ok($$
  update public.places set attributes = '{"fee": "free", "signal": "none", "price_unit": "entry"}'
   where id = 'aaaaaaaa-0000-0000-0000-000000000002'
$$, 'автор: остальные значения стоимости и связи');

select lives_ok($$
  update public.places set attributes = '{"signal": "good", "price_unit": "hour"}'
   where id = 'aaaaaaaa-0000-0000-0000-000000000002'
$$, 'автор: «хорошая связь», цена за час');

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is(
  (select c.attributes -> 'species' from public.place_card('aaaaaaaa-0000-0000-0000-000000000001') c),
  '["pike", "perch"]'::jsonb,
  'чужой видит атрибуты в карточке места'
);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select throws_ok($$
  update public.places set attributes = '{"depth": 4}' where id = 'aaaaaaaa-0000-0000-0000-000000000001'
$$, '22023', null, 'неизвестный ключ не принимается');

select throws_ok($$
  update public.places set attributes = '{"fee": "cheap"}' where id = 'aaaaaaaa-0000-0000-0000-000000000001'
$$, '22023', null, 'неизвестное значение стоимости не принимается');

select throws_ok($$
  update public.places set attributes = '{"species": ["kraken"]}' where id = 'aaaaaaaa-0000-0000-0000-000000000001'
$$, '22023', null, 'рыба — только из справочника');

select throws_ok($$
  update public.places set attributes = '{"months": [5, 13]}' where id = 'aaaaaaaa-0000-0000-0000-000000000001'
$$, '22023', null, 'месяц — от 1 до 12');

select throws_ok($$
  update public.places set attributes = '{"methods": ["shore", "shore"]}' where id = 'aaaaaaaa-0000-0000-0000-000000000001'
$$, '22023', null, 'значения в списке без повторов');

select throws_ok($$
  update public.places set attributes = '{"price_kzt": 1500.5}' where id = 'aaaaaaaa-0000-0000-0000-000000000001'
$$, '22023', null, 'цена — целое число тенге');

select throws_ok($$
  update public.places set attributes = jsonb_build_object('features', repeat('я', 1001))
   where id = 'aaaaaaaa-0000-0000-0000-000000000001'
$$, '22023', null, 'особенности — не длиннее 1000 символов');

select throws_ok($$
  update public.places set attributes = '{"fee": null}' where id = 'aaaaaaaa-0000-0000-0000-000000000001'
$$, '22023', null, 'пустое значение — не ключ с null, а без ключа');

-- Служебные ключи
select lives_ok($$
  insert into public.places (id, type, name, geom, attributes, visibility) values
    ('aaaaaaaa-0000-0000-0000-000000000007', 'fishing_spot', 'Новое',
     st_setsrid(st_makepoint(77.60, 43.90), 4326), '{"source": "editorial", "fee": "free"}', 'private')
$$, 'автор: новое место с атрибутами');

select is(
  (select attributes from public.places where id = 'aaaaaaaa-0000-0000-0000-000000000007'),
  '{"fee": "free"}'::jsonb,
  'source из приложения не сохраняется — отметку редакции не подделать'
);

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
update public.places set attributes = '{"fee": "paid"}' where id = 'aaaaaaaa-0000-0000-0000-000000000006';
select is(
  (select attributes from public.places where id = 'aaaaaaaa-0000-0000-0000-000000000006'),
  '{"fee": "paid", "source": "osm", "osm": "n1"}'::jsonb,
  'правка атрибутов автором сохраняет source и osm'
);

update public.places set attributes = '{"source": "editorial"}' where id = 'aaaaaaaa-0000-0000-0000-000000000006';
select is(
  (select attributes from public.places where id = 'aaaaaaaa-0000-0000-0000-000000000006'),
  '{"source": "osm", "osm": "n1"}'::jsonb,
  'source из приложения не меняет служебный'
);

-- Старые атрибуты с другими ключами не мешают править остальное.
select pg_temp.act_as_admin();
update public.places set attributes = '{"legacy": 1, "source": "osm"}' where id = 'aaaaaaaa-0000-0000-0000-000000000006';
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select lives_ok($$
  update public.places set name = 'Родник S (правка)' where id = 'aaaaaaaa-0000-0000-0000-000000000006'
$$, 'атрибуты не менялись — не проверяются');

-- Фильтр слов в тексте атрибутов
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select throws_ok($$
  update public.places set attributes = '{"features": "тут одни мудаки"}' where id = 'aaaaaaaa-0000-0000-0000-000000000001'
$$, 'DL005', null, 'грубые слова в особенностях публичного места не принимаются');

select lives_ok($$
  update public.places set attributes = '{"features": "тут одни мудаки"}' where id = 'aaaaaaaa-0000-0000-0000-000000000004'
$$, 'в своём приватном месте фильтра нет');

-- Редакция (Studio) пишет как угодно.
select pg_temp.act_as_admin();
select lives_ok($$
  update public.places set attributes = attributes || '{"note_for_editors": true}'
   where id = 'aaaaaaaa-0000-0000-0000-000000000005'
$$, 'служебная запись атрибутов не ограничена');
update public.places set attributes = '{"source": "osm", "osm": "n2"}' where id = 'aaaaaaaa-0000-0000-0000-000000000005';

-- Предложения правок: кто и к чему -----------------------------------------------------------------

select pg_temp.act_as_anon();
select throws_ok($$
  select public.suggest_place_change('aaaaaaaa-0000-0000-0000-000000000001', 'closed')
$$, '42501', null, 'гостю предлагать правки нельзя');

select throws_ok('select * from public.place_suggestions', '42501', null, 'гостю таблица предложений закрыта');

-- id предложений между шагами теста.
select pg_temp.act_as_admin();
create temp table s_edit (id uuid);
create temp table s_osm (id uuid);
grant all on s_edit, s_osm to authenticated;

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select throws_ok($$
  select public.suggest_place_change(
    'aaaaaaaa-0000-0000-0000-000000000001', 'edit', '{"attributes": {"species": ["kraken"]}}')
$$, '22023', null, 'в правке атрибуты проверяются так же');

insert into s_edit
select public.suggest_place_change(
  'aaaaaaaa-0000-0000-0000-000000000001', 'edit',
  '{"name": "  Озеро Публичное  ", "description": "Пологий берег", "attributes": {"fee": "free", "species": ["pike"]}}',
  'Название устарело'
);
select isnt((select id from s_edit), null, 'чужой: правка к публичному месту принята');

select is(
  (select changes ->> 'name' from public.place_suggestions where id = (select id from s_edit)),
  'Озеро Публичное',
  'название в правке — без пробелов по краям'
);

select is(
  (select count(*)::integer from public.place_suggestions),
  1,
  'автор видит своё предложение'
);

select is(
  public.suggest_place_change(
    'aaaaaaaa-0000-0000-0000-000000000001', 'edit', '{"name": "Озеро Публичное (северный берег)"}', 'Уточнил'
  ),
  (select id from s_edit),
  'повторная правка того же вида обновляет открытую'
);

select is(
  (select note from public.place_suggestions where id = (select id from s_edit)),
  'Уточнил',
  'обновлены текст и изменения'
);

select isnt(
  public.suggest_place_change('aaaaaaaa-0000-0000-0000-000000000001', 'closed', null, 'Зимой закрыто'),
  (select id from s_edit),
  'сообщение о проблеме — отдельное предложение'
);

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select is(
  (select count(*)::integer from public.place_suggestions),
  0,
  'чужие предложения не видны'
);

select throws_ok($$
  select public.suggest_place_change('aaaaaaaa-0000-0000-0000-000000000002', 'closed')
$$, 'P0002', null, 'место «для друзей» — нет (даже другу)');

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select throws_ok($$
  select public.suggest_place_change('aaaaaaaa-0000-0000-0000-000000000003', 'closed')
$$, 'P0002', null, 'место на модерации — нет');

select throws_ok($$
  select public.suggest_place_change('aaaaaaaa-0000-0000-0000-000000000004', 'closed')
$$, 'P0002', null, 'приватное место — нет');

select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select throws_ok($$
  select public.suggest_place_change('aaaaaaaa-0000-0000-0000-000000000001', 'closed')
$$, 'P0002', null, 'заблокированный автором места — нет');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select throws_ok($$
  select public.suggest_place_change('aaaaaaaa-0000-0000-0000-000000000001', 'closed')
$$, '22023', null, 'своё место правят напрямую');

-- Что принимается в правке
select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select throws_ok($$
  select public.suggest_place_change('aaaaaaaa-0000-0000-0000-000000000001', 'edit', '{}')
$$, '22023', null, 'пустая правка — нет');

select throws_ok($$
  select public.suggest_place_change('aaaaaaaa-0000-0000-0000-000000000001', 'edit', '{"visibility": "private"}')
$$, '22023', null, 'видимость и прочее чужое не предложить');

select throws_ok($$
  select public.suggest_place_change('aaaaaaaa-0000-0000-0000-000000000001', 'edit', '{"name": "   "}')
$$, '22023', null, 'пустое название — нет');

select throws_ok($$
  select public.suggest_place_change('aaaaaaaa-0000-0000-0000-000000000001', 'edit', '{"type": "castle"}')
$$, '22023', null, 'тип — только из списка');

select throws_ok($$
  select public.suggest_place_change('aaaaaaaa-0000-0000-0000-000000000001', 'duplicate', '{"name": "X"}')
$$, '22023', null, 'изменения — только у правки');

select throws_ok($$
  select public.suggest_place_change('aaaaaaaa-0000-0000-0000-000000000001', 'dangerous', null, repeat('я', 1001))
$$, '22023', null, 'текст — не длиннее 1000 символов');

select throws_ok($$
  select public.suggest_place_change('aaaaaaaa-0000-0000-0000-000000000001', 'dangerous', null, 'хозяин мудак')
$$, 'DL005', null, 'грубые слова — нет');

select throws_ok($$
  insert into public.place_suggestions (place_id, author_id, kind)
  values ('aaaaaaaa-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', 'closed')
$$, '42501', null, 'напрямую в таблицу не записать');

-- Правка места из OSM — для проверки решения редакции ниже.
insert into s_osm
select public.suggest_place_change(
  'aaaaaaaa-0000-0000-0000-000000000005', 'edit', '{"attributes": {"fee": "free"}}'
);

-- Лимит в сутки: у S уже 3, добавим 17 решённых.
select pg_temp.act_as_admin();
insert into public.place_suggestions (place_id, author_id, kind, status)
select 'aaaaaaaa-0000-0000-0000-000000000006', '33333333-3333-3333-3333-333333333333', 'closed', 'rejected'
  from generate_series(1, 17);

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select throws_ok($$
  select public.suggest_place_change('aaaaaaaa-0000-0000-0000-000000000001', 'duplicate')
$$, 'DL003', null, 'не больше 20 предложений в сутки');

select lives_ok($$
  select public.suggest_place_change('aaaaaaaa-0000-0000-0000-000000000001', 'closed', null, 'Закрыто до весны')
$$, 'обновить открытое предложение можно и после лимита');

-- Решение редакции -------------------------------------------------------------------------------

select pg_temp.act_as_admin();
select is(
  (select count(*)::integer from private.place_suggestion_queue where place_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  2,
  'очередь редакции: открытые предложения'
);

select private.accept_place_suggestion((select id from s_edit), 'Спасибо');
select is(
  (select name from public.places where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'Озеро Публичное (северный берег)',
  'принятая правка применена к месту'
);

select is(
  (select status::text from public.place_suggestions where id = (select id from s_edit)),
  'accepted',
  'правка отмечена принятой'
);

-- Атрибуты из правки заменяют прежние, а source и osm остаются.
select private.accept_place_suggestion((select id from s_osm));
select is(
  (select attributes from public.places where id = 'aaaaaaaa-0000-0000-0000-000000000005'),
  '{"fee": "free", "source": "osm", "osm": "n2"}'::jsonb,
  'принятые атрибуты сохраняют source и osm'
);

select private.reject_place_suggestion(
  (select id from public.place_suggestions
    where place_id = 'aaaaaaaa-0000-0000-0000-000000000001' and kind = 'closed' and status = 'open')
);
select is(
  (select count(*)::integer from private.place_suggestion_queue where place_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  0,
  'отклонённое уходит из очереди'
);

select * from finish();
rollback;
