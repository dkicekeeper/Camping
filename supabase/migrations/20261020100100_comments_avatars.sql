-- «Главная», продолжение (M10c): фото профиля, комментарии к постам, уведомления о постах друзей.
--
-- Фото профиля — файл в бакете `media` в своей папке: `<owner_id>/<uuid>.jpg`, путь — в
-- profiles.avatar_path. Видно вошедшим, кроме заблокированных (как имя в профиле); гостю — инициалы.
--
-- Комментарии — к поездке, отчёту (чекину) и отзыву: видны тем, кто видит сам пост, кроме
-- комментариев заблокированных. Удалить комментарий может автор и автор поста. Автору поста —
-- уведомление.
--
-- Пост друга (поездка, отчёт) — уведомление друзьям, которые его видят и не выключили такие
-- уведомления: не чаще раза в 3 часа от одного друга и один раз на пост.

-- Фото профиля ----------------------------------------------------------------------------------

alter table public.profiles
  add constraint profiles_avatar_path_own check (
    avatar_path is null
    or avatar_path ~ ('^' || id::text || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$')
  );

-- Уведомления о новых поездках и отчётах друзей (выключаются в настройках профиля).
alter table public.profiles add column notify_friend_posts boolean not null default true;

grant update (notify_friend_posts) on table public.profiles to authenticated;

-- Чтение файла бакета `media`: свои файлы, фото видимых чекинов и фото профиля (вошедшим, кроме
-- заблокированных). Фото профиля — только файл, указанный в профиле владельца папки.
create or replace function rls.can_read_media_object(object_name text) returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  viewer uuid := auth.uid();
  parts text[] := regexp_match(
    object_name,
    '^([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})(_thumb)?\.jpg$'
  );
begin
  if parts is null then
    return false;
  end if;
  -- Свои файлы — всегда (строки `media` ещё может не быть: она создаётся после загрузки).
  if viewer is not null and parts[1] = viewer::text then
    return true;
  end if;
  if viewer is not null and parts[3] is null and exists (
    select 1 from public.profiles p
     where p.id = parts[1]::uuid
       and p.avatar_path = object_name
       and not private.is_blocked(viewer, p.id)
  ) then
    return true;
  end if;
  return private.media_visible(viewer, parts[2]::uuid);
end;
$$;

-- Комментарии -----------------------------------------------------------------------------------

create table public.comments (
  id           uuid primary key default gen_random_uuid(),
  target_kind  public.reaction_target not null check (target_kind in ('trip', 'checkin', 'review')),
  target_id    uuid not null,
  owner_id     uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  body         text not null check (char_length(body) between 1 and 1000),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  edited_at    timestamptz,
  deleted_at   timestamptz
);

create index comments_target_idx on public.comments (target_kind, target_id, created_at);
create index comments_owner_idx on public.comments (owner_id, created_at desc);

create function private.comments_per_hour_limit() returns integer
language sql immutable
set search_path = ''
as $$ select 60 $$;

create function private.comments_before_write() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  client boolean := private.is_client_request();
begin
  new.body := btrim(new.body);

  if tg_op = 'INSERT' then
    if client then
      new.owner_id := auth.uid();
    end if;
    if new.owner_id is null then
      raise exception 'auth required' using errcode = '28000';
    end if;
    new.created_at := now();
    new.edited_at := null;
    new.deleted_at := null;
    if new.target_kind not in ('trip', 'checkin', 'review') then
      raise exception 'comments are for trips, reports and reviews' using errcode = '22023';
    end if;
    -- Комментировать можно то, что видишь (блокировки учтены в видимости).
    if not private.reaction_target_visible(new.owner_id, new.target_kind, new.target_id) then
      raise exception 'post not found' using errcode = 'P0002';
    end if;
    if client then
      perform pg_advisory_xact_lock(hashtext('comments:' || new.owner_id::text));
      if (select count(*) from public.comments
           where owner_id = new.owner_id and created_at > now() - interval '1 hour')
         >= private.comments_per_hour_limit() then
        raise exception 'too many comments' using errcode = 'DL003';
      end if;
    end if;
  else
    new.owner_id := old.owner_id;
    new.target_kind := old.target_kind;
    new.target_id := old.target_id;
    new.created_at := old.created_at;
    if new.body is distinct from old.body then
      new.edited_at := now();
    end if;
  end if;

  new.updated_at := now();
  return new;
end;
$$;

create trigger comments_before_write before insert or update on public.comments
  for each row execute function private.comments_before_write();

create trigger comments_word_filter before insert or update on public.comments
  for each row execute function private.word_filter('body');

alter table public.comments enable row level security;

revoke all on table public.comments from anon, authenticated;
grant select on table public.comments to authenticated;
grant insert (id, target_kind, target_id, body) on table public.comments to authenticated;
grant update (body) on table public.comments to authenticated;

create policy "comments: читать свои" on public.comments
  for select to authenticated using (owner_id = (select auth.uid()));
create policy "comments: создавать свои" on public.comments
  for insert to authenticated with check (owner_id = (select auth.uid()));
create policy "comments: менять свои" on public.comments
  for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

-- Комментарии поста, которые видит зритель: пост виден, автор комментария не заблокирован.
create function public.post_comments(
  p_kind public.reaction_target,
  p_target uuid,
  p_limit integer default 100
)
returns table (
  id uuid,
  author_id uuid,
  author_username text,
  author_display_name text,
  author_avatar_path text,
  body text,
  created_at timestamptz,
  edited_at timestamptz,
  can_delete boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id, c.owner_id, pr.username, pr.display_name, pr.avatar_path, c.body, c.created_at, c.edited_at,
         auth.uid() is not null
         and (c.owner_id = auth.uid() or private.reaction_target_owner(c.target_kind, c.target_id) = auth.uid())
    from public.comments c
    join public.profiles pr on pr.id = c.owner_id
   where c.target_kind = p_kind
     and c.target_id = p_target
     and c.deleted_at is null
     and private.reaction_target_visible(auth.uid(), p_kind, p_target)
     and (auth.uid() is null or not private.is_blocked(auth.uid(), c.owner_id))
   order by c.created_at, c.id
   limit least(greatest(coalesce(p_limit, 100), 1), 200);
$$;

-- Число комментариев у постов (пары p_kinds[i], p_ids[i]) — только у тех, что видит зритель.
create function public.comment_summary(p_kinds public.reaction_target[], p_ids uuid[])
returns table (target_kind public.reaction_target, target_id uuid, comments_count integer)
language sql
stable
security definer
set search_path = ''
as $$
  select i.kind, i.id,
         (select count(*)::integer from public.comments c
           where c.target_kind = i.kind and c.target_id = i.id and c.deleted_at is null
             and (auth.uid() is null or not private.is_blocked(auth.uid(), c.owner_id)))
    from (
      select distinct u.kind, u.id
        from unnest(p_kinds[1:200], p_ids[1:200]) as u (kind, id)
       where u.kind is not null and u.id is not null
    ) i
   where private.reaction_target_visible(auth.uid(), i.kind, i.id);
$$;

-- Удалить комментарий: свой или под своим постом.
create function public.delete_comment(p_comment uuid) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  c public.comments;
begin
  if me is null then
    raise exception 'auth required' using errcode = '28000';
  end if;
  select * into c from public.comments where id = p_comment and deleted_at is null;
  if not found
     or (c.owner_id <> me and private.reaction_target_owner(c.target_kind, c.target_id) is distinct from me) then
    raise exception 'comment not found' using errcode = 'P0002';
  end if;
  update public.comments set deleted_at = now() where id = c.id;
end;
$$;

revoke execute on function public.post_comments(public.reaction_target, uuid, integer) from public;
revoke execute on function public.comment_summary(public.reaction_target[], uuid[]) from public;
revoke execute on function public.delete_comment(uuid) from public;
grant execute on function public.post_comments(public.reaction_target, uuid, integer) to anon, authenticated;
grant execute on function public.comment_summary(public.reaction_target[], uuid[]) to anon, authenticated;
grant execute on function public.delete_comment(uuid) to authenticated;

-- Жалоба на комментарий -------------------------------------------------------------------------

create or replace function public.report_content(
  p_kind public.report_target,
  p_target uuid,
  p_reason public.report_reason,
  p_note text default null
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_owner uuid;
  v_visible boolean := false;
  recent integer;
begin
  if me is null then
    raise exception 'auth required' using errcode = '28000';
  end if;
  if v_note is not null and char_length(v_note) > 1000 then
    raise exception 'note is too long' using errcode = '22023';
  end if;

  case p_kind
    when 'place' then
      select p.owner_id,
             p.deleted_at is null
             and (p.status = 'published' or p.owner_id = me)
             and private.can_view(me, p.owner_id, p.visibility)
        into v_owner, v_visible
        from public.places p
       where p.id = p_target;
    when 'thread' then
      select t.owner_id,
             t.deleted_at is null
             and private.is_open_place(t.place_id, me)
             and not private.is_blocked(me, t.owner_id)
        into v_owner, v_visible
        from public.threads t
       where t.id = p_target;
    when 'user' then
      select pr.id, true into v_owner, v_visible
        from public.profiles pr
       where pr.id = p_target;
    when 'comment' then
      select c.owner_id,
             c.deleted_at is null
             and private.reaction_target_visible(me, c.target_kind, c.target_id)
             and not private.is_blocked(me, c.owner_id)
        into v_owner, v_visible
        from public.comments c
       where c.id = p_target;
    else
      v_visible := private.reaction_target_visible(me, p_kind::text::public.reaction_target, p_target);
      v_owner := private.reaction_target_owner(p_kind::text::public.reaction_target, p_target);
  end case;

  if not coalesce(v_visible, false) then
    raise exception 'not found' using errcode = 'P0002';
  end if;
  if v_owner = me then
    raise exception 'cannot report own content' using errcode = '22023';
  end if;

  select count(*) into recent
    from public.reports r
   where r.reporter_id = me and r.created_at > now() - interval '1 day';
  if recent >= 20 then
    raise exception 'too many reports today' using errcode = 'DL003';
  end if;

  insert into public.reports (reporter_id, target_kind, target_id, target_owner_id, reason, note)
  values (me, p_kind, p_target, v_owner, p_reason, v_note)
  on conflict (reporter_id, target_kind, target_id) do update
    set reason = excluded.reason,
        note = excluded.note,
        status = 'open',
        updated_at = now();
end;
$$;

-- Уведомления -----------------------------------------------------------------------------------

-- Комментарий — автору поста.
create function private.comments_push() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.push_enqueue(
    private.reaction_target_owner(new.target_kind, new.target_id),
    new.owner_id,
    'comment',
    jsonb_build_object(
      'target_kind', new.target_kind,
      'target_id', new.target_id,
      'snippet', left(regexp_replace(new.body, '\s+', ' ', 'g'), 120)
    )
  );
  return null;
end;
$$;

create trigger comments_push after insert on public.comments
  for each row execute function private.comments_push();

-- Пост друга — друзьям, которые его видят: один раз на пост и не чаще раза в 3 часа от автора.
create function private.friend_post_push(
  p_kind public.reaction_target,
  p_target uuid,
  p_author uuid,
  p_payload jsonb
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r uuid;
begin
  for r in
    select f.friend_id
      from public.friendships f
      join public.profiles pr on pr.id = f.friend_id
     where f.user_id = p_author
       and pr.notify_friend_posts
  loop
    if private.reaction_target_visible(r, p_kind, p_target)
       and not exists (
         select 1 from private.push_outbox o
          where o.user_id = r
            and o.kind = 'friend_post'
            and (o.payload ->> 'target_id' = p_target::text
                 or (o.payload ->> 'author_id' = p_author::text and o.created_at > now() - interval '3 hours'))
       ) then
      perform private.push_enqueue(
        r, p_author, 'friend_post',
        p_payload || jsonb_build_object('target_kind', p_kind, 'target_id', p_target, 'author_id', p_author)
      );
    end if;
  end loop;
end;
$$;

-- Поездка: новая (или открыта друзьям) и закончилась не раньше двух дней назад.
create function private.trips_friend_push() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.deleted_at is not null
     or new.visibility = 'private'
     or new.ended_at < now() - interval '2 days'
     or (tg_op = 'UPDATE' and old.visibility <> 'private') then
    return null;
  end if;
  perform private.friend_post_push(
    'trip', new.id, new.owner_id,
    jsonb_build_object('title', new.title, 'distance_m', new.distance_m)
  );
  return null;
end;
$$;

create trigger trips_friend_push after insert or update of visibility on public.trips
  for each row execute function private.trips_friend_push();

-- Отчёт: новый (или открыт другим) и не старше суток.
create function private.checkins_friend_push() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  p public.places;
begin
  if new.deleted_at is not null
     or new.visibility = 'private'
     or new.at < now() - interval '1 day'
     or (tg_op = 'UPDATE' and old.visibility <> 'private') then
    return null;
  end if;
  select * into p from public.places where id = new.place_id;
  if not found then
    return null;
  end if;
  perform private.friend_post_push(
    'checkin', new.id, new.owner_id,
    jsonb_build_object('place_id', p.id, 'place_name', p.name)
  );
  return null;
end;
$$;

create trigger checkins_friend_push after insert or update of visibility on public.checkins
  for each row execute function private.checkins_friend_push();
