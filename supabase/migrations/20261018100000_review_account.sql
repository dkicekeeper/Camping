-- Аккаунт для проверки Apple (Guideline 2.1(a)): вход по почте и паролю с готовым содержимым.
--
-- Apple проверяет бета-версию под демо-аккаунтом (имя и пароль в App Store Connect), а у нас вход
-- через Apple и Google. Поэтому приложение умеет входить по почте и паролю, но завести такой аккаунт
-- может только редакция: регистрация по почте из приложения и через API закрыта триггером.
--
-- Создать или обновить аккаунт (Supabase Studio → SQL Editor):
--   select private.create_review_account('почта', 'пароль');
-- Повторный вызов меняет пароль; содержимое (места, отчёты, уловы, поездка, сохранённые места)
-- добавляется один раз и только приватное: настоящие пользователи его не увидят. Эти же почту и пароль — в секреты GitHub ASC_DEMO_USER / ASC_DEMO_PASSWORD
-- (их передаёт в App Store Connect workflow TestFlight info).

-- Регистрация по почте — только из базы ---------------------------------------------------------

-- Supabase Auth создаёт пользователей от роли supabase_auth_admin — и при регистрации из приложения,
-- и из панели. Пользователя с почтой и паролем создаёт только владелец базы (create_review_account
-- из Studio). Функция без security definer: проверяется роль, от которой идёт запись.
create function private.auth_users_email_guard() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if coalesce(new.raw_app_meta_data ->> 'provider', '') = 'email'
     and current_user not in ('postgres', 'supabase_admin') then
    raise exception 'email sign-up is disabled' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger auth_users_email_guard before insert on auth.users
  for each row execute function private.auth_users_email_guard();

-- Аккаунт для проверки -----------------------------------------------------------------------------

create function private.create_review_account(p_email text, p_password text) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_id uuid;
  v_own_spot uuid;
  v_water uuid;
  v_checkin uuid;
  v_almaty extensions.geometry := extensions.st_setsrid(extensions.st_makepoint(76.95, 43.24), 4326);
begin
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'invalid email' using errcode = '22023';
  end if;
  if char_length(coalesce(p_password, '')) < 8 then
    raise exception 'password must be at least 8 characters' using errcode = '22023';
  end if;

  select u.id into v_id from auth.users u where lower(u.email) = v_email;
  if v_id is not null then
    if coalesce((select u.raw_app_meta_data ->> 'provider' from auth.users u where u.id = v_id), '') <> 'email' then
      raise exception 'this email belongs to an Apple or Google account' using errcode = '22023';
    end if;
    update auth.users
       set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')),
           email_confirmed_at = coalesce(email_confirmed_at, now()),
           banned_until = null,
           updated_at = now()
     where id = v_id;
  else
    v_id := gen_random_uuid();
    -- Пустые строки вместо NULL в служебных полях: иначе Supabase Auth не прочитает пользователя.
    insert into auth.users (
      id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
      confirmation_token, recovery_token, email_change_token_new, email_change,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at
    )
    values (
      v_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', v_email,
      extensions.crypt(p_password, extensions.gen_salt('bf')), now(),
      '', '', '', '',
      '{"provider": "email", "providers": ["email"]}'::jsonb,
      '{"full_name": "App Review"}'::jsonb, now(), now()
    );
    insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (
      v_id::text, v_id,
      jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true),
      'email', now(), now(), now()
    );
  end if;

  -- Профиль (его создаёт триггер регистрации): username и согласие с условиями — чтобы проверяющий
  -- сразу попал в приложение.
  update public.profiles
     set username = coalesce(username, 'appreview'),
         display_name = coalesce(display_name, 'App Review'),
         terms_version = greatest(coalesce(terms_version, 0), 1),
         terms_accepted_at = coalesce(terms_accepted_at, now())
   where id = v_id;

  -- Содержимое — один раз.
  if exists (select 1 from public.places where owner_id = v_id) then
    return v_id;
  end if;

  -- Всё содержимое — «только я»: в подборках, на карте и в отчётах чужих мест его никто не увидит.
  -- Свои места: точка ловли и стоянка с «Информацией».
  insert into public.places (owner_id, type, name, description, geom, attributes, visibility, approximate, status)
  values (
    v_id, 'fishing_spot', 'Секретная коса', 'Заход с южной стороны, глубина у бровки 3–4 м.',
    extensions.st_setsrid(extensions.st_makepoint(77.0512, 43.8861), 4326),
    '{"species": ["common_carp", "zander", "asp"], "access": ["dirt"], "fee": "free",
      "methods": ["shore", "feeder", "spinning"], "amenities": ["tent", "fireplace"],
      "signal": "weak", "months": [4, 5, 6, 9, 10], "features": "Коряги у берега, течение слабое"}'::jsonb,
    'private', false, 'published'
  )
  returning id into v_own_spot;

  insert into public.places (owner_id, type, name, description, geom, attributes, visibility, approximate, status)
  values (
    v_id, 'campsite', 'Стоянка на Или', 'Ровная площадка в тени, до воды 50 м.',
    extensions.st_setsrid(extensions.st_makepoint(77.4215, 43.9127), 4326),
    '{"access": ["dirt", "offroad"], "fee": "free", "amenities": ["shade", "tent", "fireplace", "parking"],
      "signal": "none", "months": [5, 6, 7, 8, 9]}'::jsonb,
    'private', false, 'published'
  );

  -- Ближайший к Алматы водоём редакции: свой отчёт с уловом (после него можно оставить отзыв).
  select p.id into v_water
    from public.places p
   where p.owner_id = private.editorial_id()
     and p.type = 'water_body'
     and p.deleted_at is null
     and p.status = 'published'
   order by p.geom operator(extensions.<->) v_almaty
   limit 1;

  insert into public.checkins (owner_id, place_id, at, conditions, note, visibility)
  values (
    v_id, v_own_spot, now() - interval '3 days',
    '{"bite": "good", "crowd": "empty", "water": "clear", "road": "fine"}'::jsonb,
    'Утром хорошо брал сазан на кукурузу.', 'private'
  )
  returning id into v_checkin;

  insert into public.catches (owner_id, checkin_id, place_id, species_id, weight_g, length_mm, method, bait, released, at, visibility)
  values (v_id, v_checkin, v_own_spot, 'common_carp', 3200, 560, 'feeder', 'кукуруза', true,
          now() - interval '3 days', 'private');

  if v_water is not null then
    insert into public.checkins (owner_id, place_id, at, conditions, note, visibility)
    values (
      v_id, v_water, now() - interval '1 day',
      '{"bite": "moderate", "crowd": "few", "water": "clear", "road": "fine"}'::jsonb,
      'Ветрено, клевало ближе к вечеру.', 'private'
    )
    returning id into v_checkin;

    insert into public.catches (owner_id, checkin_id, place_id, species_id, weight_g, method, released, at, visibility)
    values (v_id, v_checkin, v_water, 'perch', 350, 'spinning', false, now() - interval '1 day', 'private');
  end if;

  -- Сохранённые места: три водоёма редакции поблизости.
  insert into public.saved_places (owner_id, place_id)
  select v_id, p.id
    from public.places p
   where p.owner_id = private.editorial_id()
     and p.deleted_at is null
     and p.status = 'published'
   order by p.geom operator(extensions.<->) v_almaty
   limit 3
  on conflict do nothing;

  -- Поездка с треком (высота и время в каждой точке).
  insert into public.trips (owner_id, activity, title, note, started_at, ended_at, moving_seconds, distance_m,
                            elevation_gain_m, max_speed_mps, track, visibility)
  values (
    v_id, 'fishing', 'Вечерняя рыбалка на косе', 'Прошли вдоль берега до мыса.',
    now() - interval '3 days' - interval '2 hours', now() - interval '3 days', 3600, 2400, 12, 1.8,
    extensions.st_geomfromewkt(
      'SRID=4326;LINESTRING ZM (77.0450 43.8830 480 ' || extract(epoch from now() - interval '3 days 2 hours')::bigint
      || ', 77.0478 43.8842 482 ' || extract(epoch from now() - interval '3 days 90 minutes')::bigint
      || ', 77.0496 43.8851 486 ' || extract(epoch from now() - interval '3 days 60 minutes')::bigint
      || ', 77.0512 43.8861 492 ' || extract(epoch from now() - interval '3 days')::bigint || ')'
    ),
    'private'
  );

  return v_id;
end;
$$;

revoke execute on function private.create_review_account(text, text) from public;
