-- Правила и запреты (M5a): справочник для всех, только чтение; правила в точке на дату.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(20);

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

-- Точка внутри зоны (для проверок по датам).
create function pg_temp.inside(zone text) returns extensions.geometry language sql as $$
  select extensions.st_pointonsurface(geom) from public.rule_zones where id = zone;
$$;

insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111', 'a@test.local');

-- Целостность справочника ----------------------------------------------------------------------

select is(
  (select count(*)::integer from public.rule_zones where geom is not null and extensions.st_isvalid(geom)),
  10,
  'у всех зон бассейна — корректные границы'
);
select is_empty(
  $$ select r.id from public.regulations r, unnest(r.zone_ids) z
      where not exists (select 1 from public.rule_zones where id = z) $$,
  'правила ссылаются только на существующие зоны'
);
select is_empty(
  $$ select r.id, k from public.regulations r, jsonb_object_keys(r.min_sizes) k
      where not exists (select 1 from public.fish_species where id = k) $$,
  'промысловая мера — только для видов из справочника рыб'
);
select is_empty(
  $$ select id from public.regulations where source_url not like 'https://adilet.zan.kz/%' $$,
  'у каждого правила — ссылка на первоисточник'
);
select throws_ok(
  $$ insert into public.regulations (id, kind, basin, start_month, start_day, end_month, end_day,
       title_ru, title_kk, title_en, body_ru, body_kk, body_en, source_title, source_url, source_clause, verified_on)
     values ('bad_date', 'fishing_ban', 'x', 4, 31, 5, 1, 't', 't', 't', 'b', 'b', 'b', 's', 'https://adilet.zan.kz/x', 'c', current_date) $$,
  '22008', null,
  'несуществующая дата в сроке не сохраняется'
);

-- Доступ ----------------------------------------------------------------------------------------

select pg_temp.act_as_anon();
select is(
  (select count(*)::integer from public.rule_zones),
  10,
  'гость читает зоны'
);
select ok(
  (select count(*) > 0 from public.regulations),
  'гость читает правила'
);
select throws_ok(
  $$ update public.regulations set title_ru = 'Взлом' where id = 'kapshagay_spawning' $$,
  '42501', null,
  'гость не меняет правила'
);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select throws_ok(
  $$ insert into public.rule_zones (id, kind, basin, name_ru, name_kk, name_en) values ('fake', 'lake', 'x', 'a', 'b', 'c') $$,
  '42501', null,
  'пользователь не добавляет зоны'
);

-- Правила в точке на дату -----------------------------------------------------------------------

select pg_temp.act_as_anon();
select ok(
  (select active and period_start = '2027-04-05' and period_end = '2027-05-20'
     from public.regulations_at(
       extensions.st_x(pg_temp.inside('kapshagay')), extensions.st_y(pg_temp.inside('kapshagay')), '2027-04-10')
    where regulation_id = 'kapshagay_spawning'),
  'Капшагай, 10 апреля: нерестовый запрет действует (5 апреля – 20 мая)'
);
select ok(
  (select not active and period_start = '2028-04-05'
     from public.regulations_at(
       extensions.st_x(pg_temp.inside('kapshagay')), extensions.st_y(pg_temp.inside('kapshagay')), '2027-06-01')
    where regulation_id = 'kapshagay_spawning'),
  'после запрета — не действует, показан следующий период'
);
select ok(
  (select min_sizes->>'common_carp' = '40' and min_sizes->>'wels_catfish' = '80'
     from public.regulations_at(
       extensions.st_x(pg_temp.inside('kapshagay')), extensions.st_y(pg_temp.inside('kapshagay')), '2027-06-01')
    where regulation_id = 'min_size_kapshagay'),
  'на Капшагае — своя промысловая мера (сазан 40 см, сом 80 см)'
);
select ok(
  (select active from public.regulations_at(
       extensions.st_x(pg_temp.inside('balkhash_east')), extensions.st_y(pg_temp.inside('balkhash_east')), '2027-06-05')
    where regulation_id = 'balkhash_east_spawning')
  and not (select active from public.regulations_at(
       extensions.st_x(pg_temp.inside('balkhash_west')), extensions.st_y(pg_temp.inside('balkhash_west')), '2027-06-05')
    where regulation_id = 'balkhash_west_spawning'),
  '5 июня: на востоке Балхаша запрет ещё идёт (до 10 июня), на западе уже нет (до 1 июня)'
);
select ok(
  (select active and period_start is null
     from public.regulations_at(
       extensions.st_x(pg_temp.inside('ile_backwater')), extensions.st_y(pg_temp.inside('ile_backwater')), '2027-09-01')
    where regulation_id = 'ile_backwater_rest'),
  'зона покоя на Иле — запрет круглый год'
);
select is(
  (select gear::text from public.regulations_at(
       extensions.st_x(pg_temp.inside('ile_sharyn_china')), extensions.st_y(pg_temp.inside('ile_sharyn_china')), '2027-04-01')
    where regulation_id = 'ile_sharyn_china_spawning'),
  'amateur',
  'на Иле выше Шарына запрет касается любительских орудий'
);
select is(
  (select array_agg(regulation_id order by regulation_id) from public.regulations_at(76.9, 43.25, '2027-04-10')),
  array['methods_ban', 'undersize_release'],
  'в Алматы — только общие правила'
);

-- Период через Новый год и 29 февраля -------------------------------------------------------------

select pg_temp.act_as_admin();
select is(
  private.rule_period(12::smallint, 1::smallint, 2::smallint, 28::smallint, '2027-01-15'),
  daterange('2026-12-01', '2027-02-28', '[]'),
  'зимний период (1 декабря – 28 февраля) в январе — начался в прошлом году'
);
select is(
  private.rule_period(12::smallint, 1::smallint, 2::smallint, 28::smallint, '2027-06-01'),
  daterange('2027-12-01', '2028-02-28', '[]'),
  'летом — ближайший зимний период'
);
select is(
  private.rule_period(2::smallint, 29::smallint, 3::smallint, 10::smallint, '2027-01-01'),
  daterange('2027-02-28', '2027-03-10', '[]'),
  '29 февраля в невисокосный год — 28 февраля'
);
select is(
  private.rule_period(null, null, null, null, '2027-01-01'),
  null::daterange,
  'круглый год — без периода'
);

select * from finish();
rollback;
