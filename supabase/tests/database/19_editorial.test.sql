-- Редакция (M6e): служебный аккаунт @dalada и его места — публичные, точные, видны всем;
-- войти в аккаунт, изменить его места или заблокировать его нельзя.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(12);

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

-- Аккаунт ----------------------------------------------------------------------------------------

select is(
  (select array[username, display_name] from public.profiles where id = private.editorial_id()),
  array['dalada', 'Dalada'],
  'профиль редакции — @dalada'
);
select ok(
  (select email is null and phone is null and banned_until > now() + interval '100 years'
     from auth.users where id = private.editorial_id()),
  'войти в аккаунт редакции нельзя: ни почты, ни телефона, заблокирован в Auth'
);

-- Места ------------------------------------------------------------------------------------------

select ok(
  (select count(*) >= 150 from public.places where owner_id = private.editorial_id() and deleted_at is null),
  'к бете — 150+ мест редакции'
);
select is_empty(
  $$ select id from public.places
      where owner_id = private.editorial_id()
        and (visibility <> 'public' or approximate or status <> 'published') $$,
  'все места редакции публичные, точные и опубликованные'
);
select is_empty(
  $$ select id from public.places
      where owner_id = private.editorial_id()
        and attributes ->> 'source' not in ('osm', 'editorial') $$,
  'у каждого места редакции указан источник'
);

-- Тестовое место редакции.
insert into public.places (id, owner_id, type, name, geom, visibility, attributes)
values ('aaaaaaaa-0000-0000-0000-000000000001', private.editorial_id(), 'spring', 'Тестовый родник',
        'SRID=4326;POINT(70.000001 40.000001)', 'public', '{"source": "osm", "osm": "n1"}');

select pg_temp.act_as_anon();
select is(
  (select array[lon::text, lat::text, approximate::text, is_own::text]
     from public.places_in_bbox(69.99, 39.99, 70.01, 40.01)),
  array['70.000001', '40.000001', 'false', 'false'],
  'гость видит место редакции на карте в точной точке'
);
select is(
  (select array[owner_username, attributes ->> 'source']
     from public.place_card('aaaaaaaa-0000-0000-0000-000000000001')),
  array['dalada', 'osm'],
  'в карточке — @dalada и источник OpenStreetMap'
);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
update public.places set name = 'Мой родник' where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select is(
  (select name from public.place_card('aaaaaaaa-0000-0000-0000-000000000001')),
  'Тестовый родник',
  'человек не может изменить место редакции'
);

select throws_ok(
  $$ insert into public.places (owner_id, type, name, geom, visibility)
     values ('da1ada00-0000-4000-8000-000000000001', 'spring', 'Подделка', 'SRID=4326;POINT(70.0001 40.0001)', 'public') $$,
  '42501', null,
  'создать место от имени редакции нельзя'
);

select throws_ok(
  $$ insert into public.blocks (blocked_id) values ('da1ada00-0000-4000-8000-000000000001') $$,
  '22023', null,
  'заблокировать редакцию нельзя'
);
select is(
  public.username_available('dalada'),
  false,
  'username dalada занять нельзя'
);

-- Людей по-прежнему можно блокировать.
select lives_ok(
  $$ insert into public.blocks (blocked_id) values ('22222222-2222-2222-2222-222222222222') $$,
  'обычная блокировка работает'
);

select * from finish();
rollback;
