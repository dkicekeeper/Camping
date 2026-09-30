-- Согласие с условиями (M6c): записывает только accept_terms, версия не уменьшается.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(6);

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

insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111', 'a@test.local');

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');

select is(
  (select terms_version from public.profiles),
  null,
  'новый человек ещё ничего не принял'
);
select lives_ok($$ select public.accept_terms(2) $$, 'человек принимает условия');
select is(
  (select array[terms_version::text, (terms_accepted_at is not null)::text] from public.profiles),
  array['2', 'true'],
  'версия и время сохранены'
);
select public.accept_terms(1);
select is(
  (select terms_version from public.profiles),
  2,
  'принятая версия не уменьшается'
);
select throws_ok(
  $$ update public.profiles set terms_version = 99 $$,
  '42501', null,
  'напрямую версию не записать'
);

select pg_temp.act_as_anon();
select throws_ok(
  $$ select public.accept_terms(1) $$,
  '42501', null,
  'гость не принимает условия'
);

select * from finish();
rollback;
