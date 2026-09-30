-- Редакция (M6e): служебный аккаунт @dalada — автор редакционных мест.
--
-- Места редакции ведутся в supabase/data/places/places.csv; places.py собирает из таблицы миграцию
-- (см. supabase/data/places/README.md). Войти в этот аккаунт нельзя: у него нет почты и способа
-- входа, и он заблокирован в Auth. Username `dalada` зарезервирован — занять его из приложения нельзя.

create function private.editorial_id() returns uuid
language sql immutable
set search_path = ''
as $$ select 'da1ada00-0000-4000-8000-000000000001'::uuid $$;

-- Профиль создаёт триггер on_auth_user_created (имя — из full_name).
insert into auth.users (
  id, instance_id, aud, role, raw_app_meta_data, raw_user_meta_data, banned_until, created_at, updated_at
)
values (
  private.editorial_id(),
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  '{"provider": "editorial", "providers": []}'::jsonb,
  '{"full_name": "Dalada"}'::jsonb,
  '2999-12-31 00:00:00+00',
  now(),
  now()
)
on conflict (id) do nothing;

update public.profiles
   set username = 'dalada', display_name = 'Dalada'
 where id = private.editorial_id();

-- Приложение показывает у редакционных мест «Редакция Dalada» вместо @автора. Заблокировать
-- редакцию нельзя: иначе у человека пропали бы все её места.
create function private.blocks_not_editorial() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.blocked_id = private.editorial_id() then
    raise exception 'cannot block the editorial account' using errcode = '22023';
  end if;
  return new;
end;
$$;

create trigger blocks_not_editorial before insert or update on public.blocks
  for each row execute function private.blocks_not_editorial();
