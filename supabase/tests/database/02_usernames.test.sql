-- Username: формат, зарезервированные имена, занятость, нормализация.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(12);

create function pg_temp.act_as(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated')::text, true);
end $$;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.local');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
update public.profiles set username = 'Arman.K' where id = '11111111-1111-1111-1111-111111111111';

select is(
  (select username from public.profiles),
  'arman.k',
  'username приводится к нижнему регистру'
);
select ok(public.username_available('arman.k'), 'свой текущий username считается свободным');
select ok(public.username_available('new_name'), 'свободный username');

select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select ok(not public.username_available('arman.k'), 'занятый username');
select ok(not public.username_available('ARMAN.K'), 'занятость без учёта регистра');
select ok(not public.username_available('admin'), 'зарезервированное имя');
select ok(not public.username_available('ab'), 'слишком короткий');
select ok(not public.username_available('.arman'), 'точка в начале');
select ok(not public.username_available('arm..an'), 'две точки подряд');
select ok(not public.username_available('арман'), 'кириллица не допускается');

select throws_ok(
  $$ update public.profiles set username = 'dalada' where id = '22222222-2222-2222-2222-222222222222' $$,
  '22023', 'invalid username',
  'нельзя занять зарезервированное имя'
);
select throws_ok(
  $$ update public.profiles set username = 'arman.k' where id = '22222222-2222-2222-2222-222222222222' $$,
  '23505', null,
  'нельзя занять чужой username'
);

select * from finish();
rollback;
