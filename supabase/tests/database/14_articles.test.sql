-- Статьи и советы (M5c): опубликованные читают все, черновики не видны, писать может только редакция.

begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(10);

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

insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111', 'a@test.local');

insert into public.articles (id, category, title_ru, title_kk, title_en, summary_ru, summary_kk, summary_en,
                             body_ru, body_kk, body_en, is_published)
values ('draft_article', 'technique', 'Черновик', '', '', 'Ещё пишется', '', '', 'Текст', '', '', false);

-- Содержимое -------------------------------------------------------------------------------------

select is_empty(
  $$ select id from public.articles
      where is_published
        and (btrim(title_kk) = '' or btrim(title_en) = '' or btrim(summary_kk) = '' or btrim(summary_en) = ''
             or btrim(body_kk) = '' or btrim(body_en) = '') $$,
  'у опубликованных статей есть казахский и английский текст'
);

select is_empty(
  $$ select id from public.articles, unnest(array[body_ru, body_kk, body_en]) body
      where body ~ '!\[' or body ~ '<[a-zA-Z/]' or body ~ '(^|\n)(#[^#]|####)' $$,
  'в тексте только разметка, которую показывает приложение'
);

select throws_ok(
  $$ insert into public.articles (id, category, title_ru, title_kk, title_en, summary_ru, summary_kk, summary_en,
                                  body_ru, body_kk, body_en)
     values ('Bad Id', 'knots', 'Т', '', '', 'С', '', '', 'Т', '', '') $$,
  '23514', null,
  'id статьи — латиница в нижнем регистре, цифры и _'
);

-- Гость ------------------------------------------------------------------------------------------

select pg_temp.act_as_anon();

select is(
  (select count(*)::integer from public.articles),
  6,
  'гость видит шесть опубликованных статей'
);
select is_empty(
  $$ select id from public.articles where id = 'draft_article' $$,
  'черновик гостю не виден'
);
select throws_ok(
  $$ insert into public.articles (id, category, title_ru, title_kk, title_en, summary_ru, summary_kk, summary_en,
                                  body_ru, body_kk, body_en)
     values ('spam', 'knots', 'Т', '', '', 'С', '', '', 'Т', '', '') $$,
  '42501', null,
  'гость не пишет статьи'
);

-- Вошедший ---------------------------------------------------------------------------------------

select pg_temp.act_as('11111111-1111-1111-1111-111111111111');

select is(
  (select count(*)::integer from public.articles),
  6,
  'вошедший видит те же статьи'
);
select is_empty(
  $$ select id from public.articles where not is_published $$,
  'черновики не видны и вошедшему'
);
select throws_ok(
  $$ update public.articles set title_ru = 'Взлом' $$,
  '42501', null,
  'вошедший не меняет статьи'
);
select throws_ok(
  $$ delete from public.articles $$,
  '42501', null,
  'вошедший не удаляет статьи'
);

select * from finish();
rollback;
