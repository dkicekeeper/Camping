-- Username для онбординга (веха M1): формат, зарезервированные имена, проверка занятости.
--
-- Правила: 3–30 символов, латиница в нижнем регистре, цифры, «_» и «.»; точка не в начале,
-- не в конце и не две подряд. Клиент может прислать «Arman.K» — сохраняется «arman.k».

create function private.username_is_valid(u text) returns boolean
language sql immutable
set search_path = ''
as $$
  select u is not null
     and u ~ '^[a-z0-9_.]{3,30}$'
     and u !~ '(^[.])|([.]$)|([.]{2})'
     and u <> all (array[
       'admin', 'administrator', 'dalada', 'support', 'help', 'moderator', 'mod', 'root',
       'system', 'api', 'app', 'www', 'official', 'team', 'null', 'undefined', 'me',
       'settings', 'profile', 'places', 'map', 'feed', 'search', 'login', 'signup'
     ]);
$$;

alter table public.profiles
  add constraint profiles_username_dots check (username !~ '(^[.])|([.]$)|([.]{2})');

-- Приводим к нижнему регистру и проверяем правила при смене username из приложения.
create function private.profiles_before_update() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.username is distinct from old.username and new.username is not null then
    new.username := lower(trim(new.username));
    if private.is_client_request() and not private.username_is_valid(new.username) then
      raise exception 'invalid username' using errcode = '22023';
    end if;
  end if;
  return new;
end;
$$;

create trigger profiles_before_update before update on public.profiles
  for each row execute function private.profiles_before_update();

-- Свободен ли username (для подсказки на экране онбординга). Свой текущий — считается свободным.
create function public.username_available(p_username text) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.username_is_valid(lower(trim(p_username)))
     and not exists (
       select 1 from public.profiles
        where username = lower(trim(p_username))
          and id is distinct from auth.uid()
     );
$$;

revoke execute on function public.username_available(text) from public, anon;
grant execute on function public.username_available(text) to authenticated;
