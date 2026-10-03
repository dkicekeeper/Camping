-- M12: настройки уведомлений по видам и «тихие часы», запреты рядом с вашими местами, новое в вашем
-- публичном месте, решения модерации.
-- A — автор места (с телефоном), B — гость места (с телефоном), C — без телефона.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(20);

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

create function pg_temp.pushes(p_user uuid, p_kind public.push_kind) returns integer language sql as $$
  select count(*)::integer from private.push_outbox where user_id = p_user and kind = p_kind;
$$;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.local'),
  ('33333333-3333-3333-3333-333333333333', 'c@test.local');
update public.profiles set username = 'guest_b' where id = '22222222-2222-2222-2222-222222222222';

insert into public.devices (user_id, token, environment) values
  ('11111111-1111-1111-1111-111111111111', repeat('a1', 32), 'production'),
  ('22222222-2222-2222-2222-222222222222', repeat('b2', 32), 'production');

-- Места A далеко от настоящих зон: публичное (в тестовой зоне запрета) и приватное.
insert into public.places (id, owner_id, type, name, geom, visibility, status) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'water_body', 'Тестовое озеро',
   'SRID=4326;POINT(70.00 50.00)', 'public', 'published'),
  ('aaaaaaaa-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'fishing_spot', 'Секрет A',
   'SRID=4326;POINT(70.50 50.50)', 'private', 'published');
-- C сохранил публичное место A (телефона у C нет).
insert into public.saved_places (owner_id, place_id)
values ('33333333-3333-3333-3333-333333333333', 'aaaaaaaa-0000-0000-0000-000000000001');

insert into public.rule_zones (id, kind, basin, name_ru, name_kk, name_en, geom) values
  ('test_zone', 'lake', 'test', 'Тестовая зона', 'Сынақ аймағы', 'Test zone',
   'SRID=4326;MULTIPOLYGON(((69.9 49.9, 70.1 49.9, 70.1 50.1, 69.9 50.1, 69.9 49.9)))');
insert into public.regulations (id, kind, basin, zone_ids, start_month, start_day, end_month, end_day,
                                title_ru, title_kk, title_en, body_ru, body_kk, body_en,
                                source_title, source_url, source_clause, verified_on) values
  ('test_ban', 'fishing_ban', 'test', '{test_zone}', 5, 10, 6, 20,
   'Запрет', 'Тыйым', 'Ban', 'Текст', 'Мәтін', 'Text', 'Приказ', 'https://example.com', 'п. 1', '2026-10-01');

-- Запреты ----------------------------------------------------------------------------------------

select ok(private.ban_notifications('2027-05-09') >= 1, 'утренний обход кладёт уведомления');

select is(
  (select payload ->> 'zone_ru' || ' ' || (payload ->> 'starts') || ' ' || (payload ->> 'place_id')
     from private.push_outbox
    where user_id = '11111111-1111-1111-1111-111111111111' and kind = 'ban_start'
      and payload ->> 'regulation_id' = 'test_ban'),
  'Тестовая зона 2027-05-10 aaaaaaaa-0000-0000-0000-000000000001',
  'автору места в зоне — «завтра начинается запрет» с зоной, датой и местом'
);

select is(private.ban_notifications('2027-05-09'), 0, 'повторный обход в тот же день — без дублей');

select is(
  (select count(*)::integer from private.push_outbox
    where user_id = '33333333-3333-3333-3333-333333333333'),
  0,
  'без телефона — без уведомлений'
);

select is(private.ban_notifications('2027-05-20'), 0, 'в середине запрета — ничего');

select ok(private.ban_notifications('2027-06-21') >= 1, 'на следующий день после конца запрета');
select is(
  (select payload ->> 'ends' from private.push_outbox
    where user_id = '11111111-1111-1111-1111-111111111111' and kind = 'ban_end'
      and payload ->> 'regulation_id' = 'test_ban'),
  '2027-06-20',
  '«запрет закончился»'
);

update public.profiles set notify_bans = false where id = '11111111-1111-1111-1111-111111111111';
select is(private.ban_notifications('2028-05-09'), 0, 'уведомления о запретах можно выключить');
update public.profiles set notify_bans = true where id = '11111111-1111-1111-1111-111111111111';

-- Новое в публичном месте ---------------------------------------------------------------------------

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
insert into public.checkins (place_id, visibility) values ('aaaaaaaa-0000-0000-0000-000000000001', 'public');

select pg_temp.act_as_admin();
select is(
  (select payload ->> 'activity' || ' ' || (payload ->> 'place_name') || ' ' || (payload ->> 'actor')
     from private.push_outbox
    where user_id = '11111111-1111-1111-1111-111111111111' and kind = 'place_activity'),
  'checkin Тестовое озеро @guest_b',
  'отчёт в публичном месте — автору места'
);

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
insert into public.checkins (place_id, visibility) values ('aaaaaaaa-0000-0000-0000-000000000001', 'public');
select pg_temp.act_as_admin();
select is(pg_temp.pushes('11111111-1111-1111-1111-111111111111', 'place_activity'), 1,
  'второй отчёт в течение 6 часов — без уведомления');

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select public.save_review('aaaaaaaa-0000-0000-0000-000000000001', 5, 'Отличное место');
select pg_temp.act_as_admin();
select is(
  (select payload ->> 'rating' from private.push_outbox
    where user_id = '11111111-1111-1111-1111-111111111111' and kind = 'place_activity'
      and payload ->> 'activity' = 'review'),
  '5',
  'отзыв — автору места'
);

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
insert into public.checkins (place_id, visibility) values ('aaaaaaaa-0000-0000-0000-000000000002', 'public');
select pg_temp.act_as_admin();
select is(pg_temp.pushes('22222222-2222-2222-2222-222222222222', 'place_activity'), 0,
  'свои отчёты и приватные места — без уведомлений');

-- Решения модерации ---------------------------------------------------------------------------------

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
create temp table suggestion as
select public.suggest_place_change('aaaaaaaa-0000-0000-0000-000000000001', 'closed') as id;
select public.report_content('place', 'aaaaaaaa-0000-0000-0000-000000000001', 'spam');

select pg_temp.act_as_admin();
select private.accept_place_suggestion((select id from suggestion));
select is(
  (select payload ->> 'topic' || ' ' || (payload ->> 'status') || ' ' || (payload ->> 'place_name')
     from private.push_outbox
    where user_id = '22222222-2222-2222-2222-222222222222' and kind = 'moderation'),
  'suggestion accepted Тестовое озеро',
  'правку приняли — автору правки'
);

update public.reports set status = 'resolved'
 where reporter_id = '22222222-2222-2222-2222-222222222222';
select is(
  (select count(*)::integer from private.push_outbox
    where user_id = '22222222-2222-2222-2222-222222222222' and kind = 'moderation'
      and payload ->> 'topic' = 'report' and payload ->> 'status' = 'resolved'),
  1,
  'жалобу рассмотрели — тому, кто жаловался'
);

-- Настройки по видам -------------------------------------------------------------------------------

insert into public.trips (id, owner_id, title, started_at, ended_at, visibility) values
  ('77777777-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Поездка A',
   now() - interval '3 hours', now() - interval '1 hour', 'public');
update public.profiles set notify_comments = false where id = '11111111-1111-1111-1111-111111111111';

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
insert into public.comments (target_kind, target_id, body) values ('trip', '77777777-0000-0000-0000-000000000001', 'Класс');
select pg_temp.act_as_admin();
select is(pg_temp.pushes('11111111-1111-1111-1111-111111111111', 'comment'), 0,
  'выключенный вид уведомлений не кладётся в очередь');

select ok(
  private.push_allowed('11111111-1111-1111-1111-111111111111', 'moderation')
  and private.push_allowed('11111111-1111-1111-1111-111111111111', 'friend_post'),
  'остальные виды — включены'
);

-- Тихие часы -------------------------------------------------------------------------------------

update public.profiles
   set notify_comments = true,
       quiet_from = extract(hour from now() at time zone 'Asia/Almaty')::smallint,
       quiet_to = ((extract(hour from now() at time zone 'Asia/Almaty')::integer + 2) % 24)::smallint
 where id = '11111111-1111-1111-1111-111111111111';

select ok(
  private.push_deliver_after('11111111-1111-1111-1111-111111111111') > now(),
  'в тихие часы доставка откладывается до их конца'
);

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
insert into public.comments (target_kind, target_id, body) values ('trip', '77777777-0000-0000-0000-000000000001', 'Ещё раз');
select pg_temp.act_as_admin();

set local role service_role;
select is(
  (select count(*)::integer from public.push_claim(500) c where c.kind = 'comment'),
  0,
  'отложенное уведомление не уходит раньше времени'
);
reset role;

select ok(
  (select not_before > now() from private.push_outbox
    where user_id = '11111111-1111-1111-1111-111111111111' and kind = 'comment'),
  'а ждёт в очереди'
);

update public.profiles
   set quiet_from = ((extract(hour from now() at time zone 'Asia/Almaty')::integer + 2) % 24)::smallint,
       quiet_to = ((extract(hour from now() at time zone 'Asia/Almaty')::integer + 4) % 24)::smallint
 where id = '11111111-1111-1111-1111-111111111111';
select is(private.push_deliver_after('11111111-1111-1111-1111-111111111111'), null,
  'вне тихих часов — сразу');

select * from finish();
rollback;
