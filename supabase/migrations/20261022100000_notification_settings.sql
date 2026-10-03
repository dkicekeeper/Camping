-- Уведомления, продолжение (M12): настройки по видам и «тихие часы»; запреты рядом с вашими местами;
-- новый отзыв или отчёт в вашем публичном месте; решение по вашей правке или жалобе.
--
-- Настройки — колонки профиля (по умолчанию всё включено). «Тихие часы» — по времени Алматы: что
-- пришло в это время, доставляется, когда они закончатся (push_outbox.not_before).
--
-- Запреты: каждое утро (09:00 по Алматы) — «завтра начинается запрет» и «запрет закончился» тем, у
-- кого в зоне запрета сохранённое или своё место. Одно уведомление на человека, правило и дату.

-- Настройки -------------------------------------------------------------------------------------

alter table public.profiles
  add column notify_replies boolean not null default true,
  add column notify_friend_requests boolean not null default true,
  add column notify_comments boolean not null default true,
  add column notify_bans boolean not null default true,
  add column notify_place_activity boolean not null default true,
  add column quiet_from smallint check (quiet_from between 0 and 23),
  add column quiet_to smallint check (quiet_to between 0 and 23),
  add constraint profiles_quiet_hours_pair check ((quiet_from is null) = (quiet_to is null));

grant update (notify_replies, notify_friend_requests, notify_comments, notify_bans, notify_place_activity,
              quiet_from, quiet_to)
  on table public.profiles to authenticated;

alter table private.push_outbox add column not_before timestamptz;

-- Хочет ли человек уведомления этого вида. Решения модерации и проверочное — всегда.
create function private.push_allowed(p_user uuid, p_kind public.push_kind) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select case p_kind
      when 'thread_reply' then p.notify_replies
      when 'friend_request' then p.notify_friend_requests
      when 'friend_accept' then p.notify_friend_requests
      when 'comment' then p.notify_comments
      when 'friend_post' then p.notify_friend_posts
      when 'ban_start' then p.notify_bans
      when 'ban_end' then p.notify_bans
      when 'place_activity' then p.notify_place_activity
      else true
    end
      from public.profiles p
     where p.id = p_user
  ), false);
$$;

-- Когда доставить: null — сразу; во время «тихих часов» — когда они закончатся (по Алматы).
create function private.push_deliver_after(p_user uuid, p_now timestamptz default now()) returns timestamptz
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  f smallint;
  t smallint;
  local_now timestamp := p_now at time zone 'Asia/Almaty';
  h integer := extract(hour from local_now)::integer;
  quiet boolean;
  ends timestamp;
begin
  select p.quiet_from, p.quiet_to into f, t from public.profiles p where p.id = p_user;
  if f is null or t is null or f = t then
    return null;
  end if;
  quiet := case when f < t then h >= f and h < t else h >= f or h < t end;
  if not quiet then
    return null;
  end if;
  ends := date_trunc('day', local_now) + make_interval(hours => t);
  if ends <= local_now then
    ends := ends + interval '1 day';
  end if;
  return ends at time zone 'Asia/Almaty';
end;
$$;

-- Положить уведомление: есть устройство, вид включён, с автором не заблокированы; в «тихие часы» —
-- с отложенной доставкой.
create or replace function private.push_enqueue(
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
  if p_actor is not null and private.is_blocked(p_recipient, p_actor) then
    return;
  end if;
  if not exists (select 1 from public.devices d where d.user_id = p_recipient) then
    return;
  end if;
  if not private.push_allowed(p_recipient, p_kind) then
    return;
  end if;
  insert into private.push_outbox (user_id, kind, payload, not_before)
  values (
    p_recipient,
    p_kind,
    p_payload || jsonb_build_object(
      'actor', private.push_actor_label(p_actor),
      'username', (select p.username from public.profiles p where p.id = p_actor)
    ),
    private.push_deliver_after(p_recipient)
  );
end;
$$;

-- Отправка: отложенные — не раньше not_before; сутки считаются от времени доставки.
create or replace function public.push_claim(p_limit integer default 100)
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
         and (x.not_before is null or x.not_before <= now())
         and coalesce(x.not_before, x.created_at) > now() - interval '1 day'
         and (x.last_attempt_at is null or x.last_attempt_at < now() - interval '1 minute')
       order by coalesce(x.not_before, x.created_at)
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

create or replace function private.push_kick() returns void
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
       and (not_before is null or not_before <= now())
       and coalesce(not_before, created_at) > now() - interval '1 day'
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

-- Запреты рядом с вашими местами ------------------------------------------------------------------

-- Утренний обход (p_today — день по Алматы): запреты, которые начинаются завтра или закончились
-- вчера, и люди, у которых в зоне запрета сохранённое или своё место. Возвращает, сколько уведомлений
-- положено в очередь.
create function private.ban_notifications(p_today date default null) returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  d date := coalesce(p_today, (now() at time zone 'Asia/Almaty')::date);
  r public.regulations;
  ev record;
  rec record;
  before_id bigint := coalesce((select max(o.id) from private.push_outbox o), 0);
begin
  for r in
    select * from public.regulations
     where kind = 'fishing_ban' and start_month is not null and cardinality(zone_ids) > 0
  loop
    for ev in
      select 'ban_start'::public.push_kind as kind, lower(p) as starts, upper(p) - 1 as ends, d + 1 as event_day
        from (select private.rule_period(r.start_month, r.start_day, r.end_month, r.end_day, d + 1) as p) x
       where lower(p) = d + 1
      union all
      select 'ban_end'::public.push_kind, lower(p), upper(p) - 1, d - 1
        from (select private.rule_period(r.start_month, r.start_day, r.end_month, r.end_day, d - 1) as p) x
       where upper(p) - 1 = d - 1
    loop
      for rec in
        select distinct on (u.user_id) u.user_id, u.place_id, z.name_ru, z.name_kk, z.name_en
          from (
            select s.owner_id as user_id, p.id as place_id, p.geom
              from public.saved_places s
              join public.places p on p.id = s.place_id
             where p.deleted_at is null
            union all
            select p.owner_id, p.id, p.geom
              from public.places p
             where p.deleted_at is null
          ) u
          join public.rule_zones z
            on z.id = any (r.zone_ids)
           and z.geom is not null
           and extensions.st_intersects(z.geom, u.geom)
         order by u.user_id, z.sort_order, u.place_id
      loop
        if not exists (
          select 1 from private.push_outbox o
           where o.user_id = rec.user_id
             and o.kind = ev.kind
             and o.payload ->> 'regulation_id' = r.id
             and o.payload ->> 'day' = ev.event_day::text
        ) then
          perform private.push_enqueue(
            rec.user_id, null, ev.kind,
            jsonb_build_object(
              'regulation_id', r.id,
              'day', ev.event_day,
              'starts', ev.starts,
              'ends', ev.ends,
              'place_id', rec.place_id,
              'zone_ru', rec.name_ru,
              'zone_kk', rec.name_kk,
              'zone_en', rec.name_en
            )
          );
        end if;
      end loop;
    end loop;
  end loop;
  return (
    select count(*)::integer from private.push_outbox o
     where o.id > before_id and o.kind in ('ban_start', 'ban_end')
  );
end;
$$;

revoke execute on function private.ban_notifications(date) from public;

-- 03:00 UTC — 09:00 по Алматы.
select cron.schedule('ban-notifications', '0 3 * * *', 'select private.ban_notifications()');

-- Новое в вашем публичном месте ----------------------------------------------------------------

-- Отзыв — автору места (кроме своих отзывов).
create function private.reviews_place_push() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  p public.places;
begin
  select * into p from public.places where id = new.place_id;
  if not found or p.deleted_at is not null or p.visibility <> 'public' or p.status <> 'published' then
    return null;
  end if;
  perform private.push_enqueue(
    p.owner_id, new.owner_id, 'place_activity',
    jsonb_build_object('activity', 'review', 'place_id', p.id, 'place_name', p.name, 'rating', new.rating)
  );
  return null;
end;
$$;

create trigger reviews_place_push after insert on public.reviews
  for each row execute function private.reviews_place_push();

-- Отчёт, который автор места видит, — не чаще раза в 6 часов на место.
create function private.checkins_place_push() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  p public.places;
begin
  select * into p from public.places where id = new.place_id;
  if not found or p.deleted_at is not null or p.visibility <> 'public' or p.status <> 'published'
     or p.owner_id = new.owner_id
     or new.deleted_at is not null
     or new.at < now() - interval '1 day'
     or not private.reaction_target_visible(p.owner_id, 'checkin', new.id) then
    return null;
  end if;
  if exists (
    select 1 from private.push_outbox o
     where o.user_id = p.owner_id
       and o.kind = 'place_activity'
       and o.payload ->> 'activity' = 'checkin'
       and o.payload ->> 'place_id' = p.id::text
       and o.created_at > now() - interval '6 hours'
  ) then
    return null;
  end if;
  perform private.push_enqueue(
    p.owner_id, new.owner_id, 'place_activity',
    jsonb_build_object('activity', 'checkin', 'place_id', p.id, 'place_name', p.name)
  );
  return null;
end;
$$;

create trigger checkins_place_push after insert on public.checkins
  for each row execute function private.checkins_place_push();

-- Решения модерации -------------------------------------------------------------------------------

-- Правку приняли или отклонили — автору правки.
create function private.place_suggestions_decision_push() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status = 'open' and new.status in ('accepted', 'rejected') then
    perform private.push_enqueue(
      new.author_id, null, 'moderation',
      jsonb_build_object(
        'topic', 'suggestion',
        'status', new.status,
        'place_id', new.place_id,
        'place_name', (select p.name from public.places p where p.id = new.place_id)
      )
    );
  end if;
  return null;
end;
$$;

create trigger place_suggestions_decision_push after update of status on public.place_suggestions
  for each row execute function private.place_suggestions_decision_push();

-- Жалобу рассмотрели — тому, кто жаловался.
create function private.reports_decision_push() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status = 'open' and new.status in ('resolved', 'dismissed') then
    perform private.push_enqueue(
      new.reporter_id, null, 'moderation',
      jsonb_build_object('topic', 'report', 'status', new.status)
    );
  end if;
  return null;
end;
$$;

create trigger reports_decision_push after update of status on public.reports
  for each row execute function private.reports_decision_push();
