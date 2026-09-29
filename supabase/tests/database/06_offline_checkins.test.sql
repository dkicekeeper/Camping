-- Чекины из офлайн-очереди: время чекина, окно подтверждения, правки после отправки.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(8);

create function pg_temp.act_as(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111', 'a@test.local');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.places (id, type, name, geom, visibility) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'fishing_spot', 'Место', 'SRID=4326;POINT(77.00 43.90)', 'private');

-- Рядом с местом (~50 м): 5 часов назад, 4 дня назад, «завтра» (спешащие часы); далеко — сейчас.
insert into public.checkins (id, place_id, at, geom) values
  ('cccccccc-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001',
   now() - interval '5 hours', 'SRID=4326;POINT(77.00 43.9005)'),
  ('cccccccc-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001',
   now() - interval '4 days', 'SRID=4326;POINT(77.00 43.9005)'),
  ('cccccccc-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000001',
   now() + interval '1 day', 'SRID=4326;POINT(77.00 43.9005)'),
  ('cccccccc-0000-0000-0000-000000000004', 'aaaaaaaa-0000-0000-0000-000000000001',
   now(), 'SRID=4326;POINT(77.10 43.90)');

select ok(
  (select verified and at = now() - interval '5 hours'
     from public.checkins where id = 'cccccccc-0000-0000-0000-000000000001'),
  'отправленный через 5 часов чекин с места подтверждён и хранит своё время'
);
select ok(
  (select not verified from public.checkins where id = 'cccccccc-0000-0000-0000-000000000002'),
  'чекин старше 72 часов не подтверждается'
);
select ok(
  (select at = now() and verified from public.checkins where id = 'cccccccc-0000-0000-0000-000000000003'),
  'время из будущего приводится к текущему'
);
select ok(
  (select not verified from public.checkins where id = 'cccccccc-0000-0000-0000-000000000004'),
  'чекин далеко от места не подтверждён'
);

-- Правки после отправки. Чтобы изобразить «прошло 10 дней», сдвигаем время в обход триггера.
reset role;
alter table public.checkins disable trigger checkins_before_write;
update public.checkins set at = now() - interval '10 days'
 where id = 'cccccccc-0000-0000-0000-000000000001';
alter table public.checkins enable trigger checkins_before_write;

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
update public.checkins set note = 'Дописал через 10 дней' where id = 'cccccccc-0000-0000-0000-000000000001';
select ok(
  (select verified from public.checkins where id = 'cccccccc-0000-0000-0000-000000000001'),
  'правка заметки не снимает подтверждение'
);

update public.checkins set geom = 'SRID=4326;POINT(77.00 43.9006)'
 where id = 'cccccccc-0000-0000-0000-000000000001';
select ok(
  (select not verified from public.checkins where id = 'cccccccc-0000-0000-0000-000000000001'),
  'правка точки задним числом снимает подтверждение'
);

update public.checkins set at = now() - interval '1 hour'
 where id = 'cccccccc-0000-0000-0000-000000000004';
select ok(
  (select not verified from public.checkins where id = 'cccccccc-0000-0000-0000-000000000004'),
  'правка времени не делает чекин подтверждённым'
);

-- Улов из офлайн-очереди тоже хранит своё время.
insert into public.catches (id, checkin_id, species_id, at) values
  ('dddddddd-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000002', 'pike',
   now() - interval '4 days');
select ok(
  (select at = now() - interval '4 days' from public.catches where id = 'dddddddd-0000-0000-0000-000000000001'),
  'время улова задаёт телефон'
);

select * from finish();
rollback;
