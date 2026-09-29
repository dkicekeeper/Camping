-- Чекины из офлайн-очереди (M2c).
--
-- Телефон сохраняет чекин без сети и отправляет, когда сеть появится, — иногда через несколько
-- часов или дней. Время чекина (`at`) — момент, когда человек был на месте, а не время отправки.
--
-- Изменения в правилах подтверждения:
-- 1. Окно — 72 часа от `at` до получения сервером (было 1 час): отчёт с рыбалки без связи,
--    отправленный вечером или на следующий день, остаётся подтверждённым.
-- 2. `at` в будущем (часы телефона спешат) приводится к текущему времени.
-- 3. При изменении чекина подтверждение пересчитывается, только если поменялись точка или время
--    (тогда оно снимается). Правка заметки через день больше не снимает подтверждение.

create function private.checkin_verify_window() returns interval
language sql immutable
set search_path = ''
as $$ select interval '72 hours' $$;

create or replace function private.checkins_before_write() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  pl public.places;
begin
  if tg_op = 'INSERT' then
    if private.is_client_request() then
      new.owner_id := auth.uid();
    end if;
    new.created_at := now();
  else
    new.owner_id := old.owner_id;
    new.created_at := old.created_at;
    new.place_id := old.place_id;
  end if;

  if new.owner_id is null then
    raise exception 'auth required' using errcode = '28000';
  end if;

  select * into pl from public.places where id = new.place_id;
  if not found
     or pl.deleted_at is not null
     or (pl.status <> 'published' and pl.owner_id <> new.owner_id)
     or not private.can_view(new.owner_id, pl.owner_id, pl.visibility) then
    raise exception 'place not found' using errcode = 'P0002';
  end if;

  -- Чекин не может быть видимее места.
  if pl.visibility = 'private' then
    new.visibility := 'private';
  elsif pl.visibility = 'friends' and new.visibility = 'public' then
    new.visibility := 'friends';
  end if;

  -- Время из будущего — это спешащие часы телефона.
  if new.at > now() + interval '5 minutes' then
    new.at := now();
  end if;

  -- Точки сравниваем как байты: операторы PostGIS при пустом search_path не находятся.
  if tg_op = 'UPDATE'
     and new.at = old.at
     and extensions.st_asewkb(new.geom) is not distinct from extensions.st_asewkb(old.geom) then
    new.verified := old.verified;
  elsif tg_op = 'UPDATE' then
    -- Точку или время поменяли задним числом — подтверждения больше нет.
    new.verified := false;
  else
    -- Подтверждён, если телефон был рядом с местом и чекин получен не позже 72 часов.
    new.verified := new.geom is not null
      and new.at > now() - private.checkin_verify_window()
      and extensions.st_dwithin(
            new.geom::extensions.geography,
            pl.geom::extensions.geography,
            private.checkin_radius_m());
  end if;

  new.updated_at := now();
  return new;
end;
$$;
