-- «Мои места» и создание места так, как это делает приложение (PostgREST: JSON → запись).

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(6);

create function pg_temp.act_as(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('33333333-3333-3333-3333-333333333333', 's@test.local');

-- Приложение отправляет JSON; координаты — строкой EWKT.
select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.places (id, type, name, description, geom, visibility, approximate)
select id, type, name, description, geom, visibility, approximate
  from json_populate_record(null::public.places, '{
    "id": "aaaaaaaa-0000-0000-0000-000000000001",
    "type": "fishing_spot",
    "name": "Залив у Кербулака",
    "description": "Сазан на кукурузу",
    "geom": "SRID=4326;POINT(77.05 43.9)",
    "visibility": "public",
    "approximate": true
  }');
insert into public.places (id, type, name, geom, visibility)
values ('aaaaaaaa-0000-0000-0000-000000000002', 'campsite', 'Стоянка',
        'SRID=4326;POINT(77.2 43.95)', 'private');

select is((select count(*) from public.my_places()), 2::bigint, 'свои места, включая место на модерации');
select ok(
  (select lon = 77.05 and lat = 43.9 and not approximate and is_own
     from public.my_places() where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'в «Моих местах» свои координаты точные'
);
select is(
  (select status from public.my_places() where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'pending'::public.place_status,
  'первое публичное место — на модерации'
);
select is(
  (select visibility from public.my_places() where id = 'aaaaaaaa-0000-0000-0000-000000000002'),
  'private'::public.visibility,
  'видимость возвращается как сохранена'
);

select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select is((select count(*) from public.my_places()), 0::bigint, 'чужие места в «Моих местах» не видны');

select set_config('role', 'anon', true);
select set_config('request.jwt.claims', '{"role": "anon"}', true);
select throws_ok('select * from public.my_places()', '42501', null, 'гостю функция недоступна');

select * from finish();
rollback;
