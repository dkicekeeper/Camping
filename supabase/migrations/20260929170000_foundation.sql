-- Фундамент: расширения, служебная схема, типы, профили.
--
-- Правило для всего проекта: доступ к таблицам по умолчанию закрыт, права выдаются явно
-- (на уровне колонок, где клиент не должен менять служебные поля). Чужие данные
-- читаются только через RPC-функции — см. docs/03-architecture/02-backend.md.

create extension if not exists postgis with schema extensions;
create extension if not exists pg_trgm with schema extensions;
create extension if not exists unaccent with schema extensions;

-- Служебная схема: не открыта для API и для ролей anon/authenticated.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- Типы ---------------------------------------------------------------------------------------

create type public.visibility as enum ('public', 'friends', 'private');

-- Профили ------------------------------------------------------------------------------------

create table public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  username     text unique check (username ~ '^[a-z0-9_.]{3,30}$'),
  display_name text check (char_length(display_name) <= 60),
  avatar_path  text check (char_length(avatar_path) <= 300),
  city         text check (char_length(city) <= 60),
  language     text not null default 'ru' check (language in ('ru', 'kk', 'en')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

comment on table public.profiles is
  'Публичная часть профиля. Напрямую читается только своя строка; чужие профили — через RPC.';

alter table public.profiles enable row level security;

revoke all on table public.profiles from anon, authenticated;
grant select on table public.profiles to authenticated;
grant update (username, display_name, avatar_path, city, language) on table public.profiles to authenticated;

create policy "profiles: читать свой" on public.profiles
  for select to authenticated using (id = (select auth.uid()));

create policy "profiles: менять свой" on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- Общий триггер updated_at.
create function private.touch_updated_at() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_touch before update on public.profiles
  for each row execute function private.touch_updated_at();

-- Профиль создаётся автоматически при регистрации (Apple, Google).
create function private.handle_new_user() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, left(coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'), 60));
  return new;
end;
$$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function private.handle_new_user();
