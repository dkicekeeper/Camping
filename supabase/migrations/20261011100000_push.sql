-- Пуш-уведомления (M6d, базово): ответ в обсуждении, запрос в друзья, запрос принят.
--
-- Как работает:
--   1. Приложение регистрирует токен APNs (register_device) и убирает его при выходе.
--   2. Триггеры кладут уведомления в очередь private.push_outbox — только тем, у кого есть
--      устройство, и не между заблокированными.
--   3. Раз в минуту pg_cron вызывает private.push_kick: если очередь не пуста и настроены секреты
--      Vault (push_function_url, push_worker_secret), он дёргает Edge Function `push`
--      (supabase/functions/push), та забирает пачку (push_claim), отправляет в APNs и отчитывается
--      (push_finish). Не настроено — уведомления просто ждут в очереди сутки.
-- Тексты уведомлений собирает функция на языке устройства.

create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron;

-- Устройства ------------------------------------------------------------------------------------

-- sandbox — сборки из Xcode; production — TestFlight и App Store.
create type public.push_environment as enum ('sandbox', 'production');

create table public.devices (
  token        text primary key check (token ~ '^[0-9a-f]+$' and char_length(token) between 64 and 512),
  user_id      uuid not null references public.profiles (id) on delete cascade,
  environment  public.push_environment not null,
  language     text not null default 'ru' check (language in ('ru', 'kk', 'en')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index devices_user_idx on public.devices (user_id, updated_at desc);

-- Только через register_device / unregister_device.
alter table public.devices enable row level security;
revoke all on table public.devices from anon, authenticated;

-- Не больше стольких устройств на человека (старые вытесняются).
create function private.devices_limit() returns integer
language sql immutable
set search_path = ''
as $$ select 10 $$;

create function public.register_device(
  p_token text,
  p_environment public.push_environment,
  p_language text default 'ru'
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  v_token text := lower(btrim(coalesce(p_token, '')));
  v_language text := case when p_language in ('ru', 'kk', 'en') then p_language else 'ru' end;
begin
  if me is null then
    raise exception 'auth required' using errcode = '28000';
  end if;
  if v_token !~ '^[0-9a-f]+$' or char_length(v_token) not between 64 and 512 then
    raise exception 'invalid device token' using errcode = '22023';
  end if;

  -- Телефон мог перейти к другому аккаунту: токен теперь его.
  insert into public.devices (token, user_id, environment, language)
  values (v_token, me, p_environment, v_language)
  on conflict (token) do update
    set user_id = excluded.user_id,
        environment = excluded.environment,
        language = excluded.language,
        updated_at = now();

  delete from public.devices d
   where d.user_id = me
     and d.token in (
       select x.token from public.devices x
        where x.user_id = me
        order by x.updated_at desc
       offset private.devices_limit());
end;
$$;

create function public.unregister_device(p_token text) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'auth required' using errcode = '28000';
  end if;
  delete from public.devices
   where token = lower(btrim(coalesce(p_token, ''))) and user_id = auth.uid();
end;
$$;

revoke execute on function public.register_device(text, public.push_environment, text) from public;
revoke execute on function public.unregister_device(text) from public;
grant execute on function public.register_device(text, public.push_environment, text) to authenticated;
grant execute on function public.unregister_device(text) to authenticated;

-- Очередь уведомлений ---------------------------------------------------------------------------

-- thread_reply — ответ в вашем обсуждении или на ваш ответ; friend_request — запрос в друзья;
-- friend_accept — ваш запрос приняли.
create type public.push_kind as enum ('thread_reply', 'friend_request', 'friend_accept');

create table private.push_outbox (
  id               bigint generated always as identity primary key,
  user_id          uuid not null references public.profiles (id) on delete cascade,
  kind             public.push_kind not null,
  -- Кто и что: actor (имя для текста), username (для ссылки), thread_id, title, snippet.
  payload          jsonb not null default '{}',
  created_at       timestamptz not null default now(),
  attempts         integer not null default 0,
  last_attempt_at  timestamptz,
  sent_at          timestamptz,
  last_error       text
);

create index push_outbox_pending_idx on private.push_outbox (created_at) where sent_at is null;

alter table private.push_outbox enable row level security;

-- Сколько попыток и как долго уведомление имеет смысл.
create function private.push_max_attempts() returns integer
language sql immutable
set search_path = ''
as $$ select 5 $$;

-- Имя для текста уведомления: имя, иначе @username.
create function private.push_actor_label(p_user uuid) returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(nullif(btrim(p.display_name), ''), '@' || p.username, 'Dalada')
    from public.profiles p
   where p.id = p_user;
$$;

-- Положить уведомление, если у получателя есть устройство и они с автором не заблокированы.
create function private.push_enqueue(
  p_recipient uuid,
  p_actor uuid,
  p_kind public.push_kind,
  p_payload jsonb
) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_recipient is null or p_recipient = p_actor then
    return;
  end if;
  if private.is_blocked(p_recipient, p_actor) then
    return;
  end if;
  if not exists (select 1 from public.devices d where d.user_id = p_recipient) then
    return;
  end if;
  insert into private.push_outbox (user_id, kind, payload)
  values (
    p_recipient,
    p_kind,
    p_payload || jsonb_build_object(
      'actor', private.push_actor_label(p_actor),
      'username', (select p.username from public.profiles p where p.id = p_actor)
    )
  );
end;
$$;

-- Ответ в обсуждении: автору обсуждения и автору процитированного ответа.
create function private.thread_posts_push() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  t public.threads;
  quoted_owner uuid;
  payload jsonb;
begin
  select * into t from public.threads where id = new.thread_id;
  if not found or t.deleted_at is not null then
    return null;
  end if;
  payload := jsonb_build_object(
    'thread_id', t.id,
    'title', t.title,
    'snippet', left(regexp_replace(new.body, '\s+', ' ', 'g'), 120)
  );
  perform private.push_enqueue(t.owner_id, new.owner_id, 'thread_reply', payload);

  if new.quote_post_id is not null then
    select p.owner_id into quoted_owner
      from public.thread_posts p
     where p.id = new.quote_post_id and p.deleted_at is null;
    if quoted_owner is distinct from t.owner_id then
      perform private.push_enqueue(quoted_owner, new.owner_id, 'thread_reply', payload);
    end if;
  end if;
  return null;
end;
$$;

create trigger thread_posts_push after insert on public.thread_posts
  for each row execute function private.thread_posts_push();

-- Запрос в друзья и «запрос принят».
create function private.friend_requests_push() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' and new.status = 'pending' then
    perform private.push_enqueue(new.to_user, new.from_user, 'friend_request', '{}'::jsonb);
  elsif tg_op = 'UPDATE' and new.status = 'accepted' and old.status is distinct from 'accepted' then
    perform private.push_enqueue(new.from_user, new.to_user, 'friend_accept', '{}'::jsonb);
  end if;
  return null;
end;
$$;

create trigger friend_requests_push after insert or update of status on public.friend_requests
  for each row execute function private.friend_requests_push();

-- Отправка (для Edge Function `push`, роль service_role) ---------------------------------------------

-- Забрать пачку: уведомления, которые ещё не отправлены, не старше суток, не исчерпали попыток и
-- не взяты в работу в последнюю минуту, — по строке на каждое устройство получателя.
create function public.push_claim(p_limit integer default 100)
returns table (
  outbox_id bigint,
  kind public.push_kind,
  payload jsonb,
  token text,
  environment public.push_environment,
  language text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  ids bigint[];
begin
  select array_agg(o.id) into ids
    from (
      select x.id
        from private.push_outbox x
       where x.sent_at is null
         and x.attempts < private.push_max_attempts()
         and x.created_at > now() - interval '1 day'
         and (x.last_attempt_at is null or x.last_attempt_at < now() - interval '1 minute')
       order by x.created_at
       limit greatest(1, least(coalesce(p_limit, 100), 500))
         for update skip locked
    ) o;

  if ids is null then
    return;
  end if;

  update private.push_outbox
     set attempts = attempts + 1, last_attempt_at = now()
   where id = any (ids);

  return query
    select o.id, o.kind, o.payload, d.token, d.environment, d.language
      from private.push_outbox o
      join public.devices d on d.user_id = o.user_id
     where o.id = any (ids)
     order by o.id;
end;
$$;

-- Итог отправки: доставленные уведомления, токены, которые APNs больше не принимает, и ошибки
-- ({"<outbox_id>": "текст"}).
create function public.push_finish(
  p_sent bigint[],
  p_dead_tokens text[] default '{}',
  p_errors jsonb default '{}'
) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update private.push_outbox
     set sent_at = now(), last_error = null
   where id = any (coalesce(p_sent, '{}'));

  delete from public.devices where token = any (coalesce(p_dead_tokens, '{}'));

  update private.push_outbox o
     set last_error = left(e.value, 500)
    from jsonb_each_text(coalesce(p_errors, '{}')) e
   where o.id = e.key::bigint and o.sent_at is null;
end;
$$;

revoke execute on function public.push_claim(integer) from public, anon, authenticated;
revoke execute on function public.push_finish(bigint[], text[], jsonb) from public, anon, authenticated;
grant execute on function public.push_claim(integer) to service_role;
grant execute on function public.push_finish(bigint[], text[], jsonb) to service_role;

-- Раз в минуту: есть что отправить — вызвать Edge Function. Адрес функции и общий секрет — в Vault
-- (см. docs/04-beta/M6-beta-readiness.md), пока их нет — ничего не делает.
create function private.push_kick() returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_secret text;
begin
  if not exists (
    select 1 from private.push_outbox
     where sent_at is null
       and attempts < private.push_max_attempts()
       and created_at > now() - interval '1 day'
  ) then
    return;
  end if;

  select s.decrypted_secret into v_url from vault.decrypted_secrets s where s.name = 'push_function_url';
  select s.decrypted_secret into v_secret from vault.decrypted_secrets s where s.name = 'push_worker_secret';
  if v_url is null or v_secret is null then
    return;
  end if;

  perform net.http_post(
    url := v_url,
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', v_secret),
    timeout_milliseconds := 30000
  );
end;
$$;

select cron.schedule('push-worker', '* * * * *', 'select private.push_kick()');
