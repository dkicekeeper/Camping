-- Аккаунт для проверки Apple: создание с паролем и содержимым, повторный вызов, запрет регистрации
-- по почте для всех, кроме владельца базы.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(18);

create function pg_temp.act_as_authenticated() returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', '11111111-1111-1111-1111-111111111111', 'role', 'authenticated')::text, true);
end $$;

create function pg_temp.review_count(p_table text) returns integer language plpgsql as $$
declare
  n integer;
begin
  execute format(
    'select count(*)::integer from public.%I t join public.profiles p on p.id = t.owner_id where p.username = %L',
    p_table, 'appreview'
  ) into n;
  return n;
end $$;

create temp table review_id as
select private.create_review_account('  Review@Example.com ', 'first-pass-1') as id;

select isnt((select id from review_id), null, 'аккаунт создан');

select is(
  (select u.email || ' ' || (u.raw_app_meta_data ->> 'provider') from auth.users u where u.id = (select id from review_id)),
  'review@example.com email',
  'почта в нижнем регистре, вход по почте'
);

select ok(
  (select u.email_confirmed_at is not null
          and u.encrypted_password = extensions.crypt('first-pass-1', u.encrypted_password)
     from auth.users u where u.id = (select id from review_id)),
  'почта подтверждена, пароль совпадает'
);

select is(
  (select count(*)::integer from auth.identities i
    where i.user_id = (select id from review_id) and i.provider = 'email'),
  1,
  'есть identity для входа по почте'
);

select is(
  (select username || ' ' || terms_version from public.profiles where id = (select id from review_id)),
  'appreview 1',
  'username и согласие с условиями — сразу в приложение'
);

select is(
  array[pg_temp.review_count('places'), pg_temp.review_count('checkins'), pg_temp.review_count('catches'),
        pg_temp.review_count('reviews'), pg_temp.review_count('saved_places'), pg_temp.review_count('trips')],
  array[2, 2, 2, 0, 3, 1],
  'содержимое: места, отчёты, уловы, сохранённые места, поездка (отзывов нет)'
);

select is(
  (select count(*)::integer from (
     select visibility::text from public.places where owner_id = (select id from review_id)
     union all select visibility::text from public.checkins where owner_id = (select id from review_id)
     union all select visibility::text from public.catches where owner_id = (select id from review_id)
     union all select visibility::text from public.trips where owner_id = (select id from review_id)
   ) v where v.visibility <> 'private'),
  0,
  'всё содержимое приватное — настоящие пользователи его не видят'
);

select is(
  (select attributes ->> 'fee' from public.places
    where owner_id = (select id from review_id) and type = 'fishing_spot'),
  'free',
  'у своего места заполнена «Информация»'
);

-- Повторный вызов: тот же аккаунт, новый пароль, содержимое не удваивается.
select is(
  private.create_review_account('review@example.com', 'second-pass-2'),
  (select id from review_id),
  'повторный вызов — тот же аккаунт'
);

select ok(
  (select u.encrypted_password = extensions.crypt('second-pass-2', u.encrypted_password)
     from auth.users u where u.id = (select id from review_id)),
  'пароль обновлён'
);

select is(pg_temp.review_count('places'), 2, 'содержимое не удваивается');

select throws_ok(
  $$ select private.create_review_account('not-an-email', 'first-pass-1') $$,
  '22023', null, 'почта проверяется'
);

select throws_ok(
  $$ select private.create_review_account('other@example.com', 'short') $$,
  '22023', null, 'пароль — не короче 8 символов'
);

-- Почта занята аккаунтом Apple — не превращаем его в аккаунт с паролем.
insert into auth.users (id, email, raw_app_meta_data)
values ('77777777-7777-7777-7777-777777777777', 'apple@example.com', '{"provider": "apple", "providers": ["apple"]}');
select throws_ok(
  $$ select private.create_review_account('apple@example.com', 'first-pass-1') $$,
  '22023', null, 'почта аккаунта Apple — нельзя'
);

-- Регистрация по почте: Supabase Auth пишет от своей роли — проверяем триггер на копии таблицы, от
-- роли без особых прав (supabase_auth_admin в тесте не включить).
create temp table auth_users_copy (raw_app_meta_data jsonb);
create trigger auth_users_email_guard before insert on auth_users_copy
  for each row execute function private.auth_users_email_guard();
grant insert on auth_users_copy to authenticated;

select pg_temp.act_as_authenticated();

select throws_ok(
  $$ insert into auth_users_copy values ('{"provider": "email", "providers": ["email"]}') $$,
  '42501', null, 'регистрация по почте из Supabase Auth закрыта'
);

select lives_ok(
  $$ insert into auth_users_copy values ('{"provider": "apple", "providers": ["apple"]}') $$,
  'вход через Apple и Google не затронут'
);

select throws_ok(
  $$ select private.create_review_account('x@example.com', 'first-pass-1') $$,
  '42501', null, 'приложению функция недоступна'
);

reset role;
select lives_ok(
  $$ insert into auth_users_copy values ('{"provider": "email", "providers": ["email"]}') $$,
  'владелец базы (Studio) может'
);

select * from finish();
rollback;
