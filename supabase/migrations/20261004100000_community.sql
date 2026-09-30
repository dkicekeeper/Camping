-- Отзывы, обсуждения мест и реакции (M4c).
--
-- Отзывы и обсуждения бывают только в публичных опубликованных местах и всегда публичны: их видят
-- все, кроме заблокированных (в обе стороны). Отзыв — один на человека и место, после чекина в этом
-- месте (любого, в том числе задним числом); прежние версии правленого отзыва сохраняются.
-- Реакции («респект», «полезно») ставятся на поездки, чекины, отзывы и сообщения — только на то,
-- что видишь, и не на своё.
--
-- Коды ошибок для приложения:
--   DL001 — отзыв без чекина в месте;
--   DL002 — отзывы и обсуждения только в публичных местах;
--   DL003 — слишком часто (лимит на обсуждения и сообщения).

-- Публичное опубликованное место, и зритель не заблокирован с его автором.
create function private.is_open_place(p_place uuid, p_viewer uuid) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.places p
     where p.id = p_place
       and p.deleted_at is null
       and p.status = 'published'
       and p.visibility = 'public'
       and (p_viewer is null or not private.is_blocked(p_viewer, p.owner_id))
  );
$$;

-- Отзывы -----------------------------------------------------------------------------------------

create table public.reviews (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references public.profiles (id) on delete cascade,
  place_id    uuid not null references public.places (id) on delete cascade,
  rating      smallint not null check (rating between 1 and 5),
  body        text check (char_length(body) <= 2000),
  visited_on  date,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  edited_at   timestamptz,
  deleted_at  timestamptz,
  unique (place_id, owner_id)
);

create index reviews_owner_idx on public.reviews (owner_id);

-- Прежние версии отзывов (для модерации). Клиенту не отдаются.
create table private.review_revisions (
  id          bigint generated always as identity primary key,
  review_id   uuid not null references public.reviews (id) on delete cascade,
  rating      smallint not null,
  body        text,
  visited_on  date,
  replaced_at timestamptz not null default now()
);

alter table public.reviews enable row level security;

-- Пишутся только через save_review / delete_review.
revoke all on table public.reviews from anon, authenticated;
grant select on table public.reviews to authenticated;

create policy "reviews: читать свои" on public.reviews
  for select to authenticated using (owner_id = (select auth.uid()));

-- Сохранить свой отзыв о месте: новый или правка прежнего (удалённый — восстанавливается).
-- Дата визита по умолчанию — день последнего чекина в месте (по Алматы).
create function public.save_review(
  p_place uuid,
  p_rating integer,
  p_body text default null,
  p_visited_on date default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  v_body text := nullif(btrim(coalesce(p_body, '')), '');
  v_visited date;
  existing public.reviews;
  changed boolean;
  result uuid;
begin
  if me is null then
    raise exception 'auth required' using errcode = '28000';
  end if;
  if p_rating is null or p_rating not between 1 and 5 then
    raise exception 'rating must be between 1 and 5' using errcode = '22023';
  end if;
  if v_body is not null and char_length(v_body) > 2000 then
    raise exception 'review is too long' using errcode = '22023';
  end if;
  if not private.is_open_place(p_place, me) then
    raise exception 'reviews are only for public places' using errcode = 'DL002';
  end if;

  select max((c.at at time zone 'Asia/Almaty')::date) into v_visited
    from public.checkins c
   where c.owner_id = me and c.place_id = p_place and c.deleted_at is null;
  if v_visited is null then
    raise exception 'check in at the place first' using errcode = 'DL001';
  end if;
  if p_visited_on is not null then
    if p_visited_on > (now() at time zone 'Asia/Almaty')::date or p_visited_on < date '2000-01-01' then
      raise exception 'invalid visit date' using errcode = '22023';
    end if;
    v_visited := p_visited_on;
  end if;

  select * into existing from public.reviews
   where place_id = p_place and owner_id = me
   for update;

  if not found then
    insert into public.reviews (owner_id, place_id, rating, body, visited_on)
    values (me, p_place, p_rating, v_body, v_visited)
    returning id into result;
    return result;
  end if;

  if existing.deleted_at is not null then
    -- Удалённый отзыв пишется заново: как новый.
    update public.reviews
       set rating = p_rating, body = v_body, visited_on = v_visited,
           created_at = now(), updated_at = now(), edited_at = null, deleted_at = null
     where id = existing.id;
    return existing.id;
  end if;

  changed := (existing.rating, existing.body, existing.visited_on)
             is distinct from (p_rating::smallint, v_body, v_visited);
  if changed then
    insert into private.review_revisions (review_id, rating, body, visited_on)
    values (existing.id, existing.rating, existing.body, existing.visited_on);
    update public.reviews
       set rating = p_rating, body = v_body, visited_on = v_visited,
           updated_at = now(), edited_at = now()
     where id = existing.id;
  end if;
  return existing.id;
end;
$$;

create function public.delete_review(p_review uuid) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.reviews
     set deleted_at = now(), updated_at = now()
   where id = p_review and owner_id = auth.uid() and deleted_at is null;
  if not found then
    raise exception 'review not found' using errcode = 'P0002';
  end if;
end;
$$;

-- Обсуждения ------------------------------------------------------------------------------------

create table public.threads (
  id               uuid primary key default gen_random_uuid(),
  owner_id         uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  place_id         uuid not null references public.places (id) on delete cascade,
  title            text not null check (char_length(title) between 3 and 120),
  body             text not null check (char_length(body) between 1 and 4000),
  posts_count      integer not null default 0,
  last_activity_at timestamptz not null default now(),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  edited_at        timestamptz,
  deleted_at       timestamptz
);

create index threads_place_idx on public.threads (place_id, last_activity_at desc);
create index threads_owner_idx on public.threads (owner_id, created_at desc);

create table public.thread_posts (
  id            uuid primary key default gen_random_uuid(),
  thread_id     uuid not null references public.threads (id) on delete cascade,
  owner_id      uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  body          text not null check (char_length(body) between 1 and 4000),
  -- Ответ с цитатой (один уровень, без веток).
  quote_post_id uuid references public.thread_posts (id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  edited_at     timestamptz,
  deleted_at    timestamptz
);

create index thread_posts_thread_idx on public.thread_posts (thread_id, created_at);
create index thread_posts_owner_idx on public.thread_posts (owner_id, created_at desc);

-- Лимиты для защиты от спама.
create function private.threads_per_day_limit() returns integer
language sql immutable
set search_path = ''
as $$ select 5 $$;

create function private.posts_per_hour_limit() returns integer
language sql immutable
set search_path = ''
as $$ select 60 $$;

create function private.threads_before_write() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  client boolean := private.is_client_request();
begin
  new.title := btrim(new.title);
  new.body := btrim(new.body);

  if tg_op = 'INSERT' then
    if client then
      new.owner_id := auth.uid();
    end if;
    if new.owner_id is null then
      raise exception 'auth required' using errcode = '28000';
    end if;
    new.created_at := now();
    new.last_activity_at := now();
    new.posts_count := 0;
    new.edited_at := null;
    new.deleted_at := null;
    if not private.is_open_place(new.place_id, new.owner_id) then
      raise exception 'discussions are only for public places' using errcode = 'DL002';
    end if;
    if client then
      perform pg_advisory_xact_lock(hashtext('threads:' || new.owner_id::text));
      if (select count(*) from public.threads
           where owner_id = new.owner_id and created_at > now() - interval '1 day')
         >= private.threads_per_day_limit() then
        raise exception 'too many discussions today' using errcode = 'DL003';
      end if;
    end if;
  else
    new.owner_id := old.owner_id;
    new.place_id := old.place_id;
    new.created_at := old.created_at;
    if (new.title, new.body) is distinct from (old.title, old.body) then
      new.edited_at := now();
    end if;
  end if;

  new.updated_at := now();
  return new;
end;
$$;

create trigger threads_before_write before insert or update on public.threads
  for each row execute function private.threads_before_write();

create function private.thread_posts_before_write() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  client boolean := private.is_client_request();
  th public.threads;
  quoted public.thread_posts;
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

    select * into th from public.threads where id = new.thread_id;
    if not found
       or th.deleted_at is not null
       or not private.is_open_place(th.place_id, new.owner_id)
       or private.is_blocked(new.owner_id, th.owner_id) then
      raise exception 'thread not found' using errcode = 'P0002';
    end if;

    if new.quote_post_id is not null then
      select * into quoted from public.thread_posts where id = new.quote_post_id;
      if not found
         or quoted.thread_id <> new.thread_id
         or quoted.deleted_at is not null
         or private.is_blocked(new.owner_id, quoted.owner_id) then
        raise exception 'quoted post not found' using errcode = '22023';
      end if;
    end if;

    if client then
      perform pg_advisory_xact_lock(hashtext('thread_posts:' || new.owner_id::text));
      if (select count(*) from public.thread_posts
           where owner_id = new.owner_id and created_at > now() - interval '1 hour')
         >= private.posts_per_hour_limit() then
        raise exception 'too many messages' using errcode = 'DL003';
      end if;
    end if;
  else
    new.owner_id := old.owner_id;
    new.thread_id := old.thread_id;
    new.quote_post_id := old.quote_post_id;
    new.created_at := old.created_at;
    if new.body is distinct from old.body then
      new.edited_at := now();
    end if;
  end if;

  new.updated_at := now();
  return new;
end;
$$;

create trigger thread_posts_before_write before insert or update on public.thread_posts
  for each row execute function private.thread_posts_before_write();

-- Счётчик ответов и время последней активности обсуждения.
create function private.thread_posts_after_write() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.threads t
     set posts_count = s.cnt,
         last_activity_at = greatest(t.created_at, coalesce(s.last_at, t.created_at))
    from (
      select count(*)::integer as cnt, max(p.created_at) as last_at
        from public.thread_posts p
       where p.thread_id = new.thread_id and p.deleted_at is null
    ) s
   where t.id = new.thread_id;
  return null;
end;
$$;

create trigger thread_posts_after_write after insert or update of deleted_at on public.thread_posts
  for each row execute function private.thread_posts_after_write();

alter table public.threads enable row level security;
alter table public.thread_posts enable row level security;

revoke all on table public.threads, public.thread_posts from anon, authenticated;
grant select on table public.threads, public.thread_posts to authenticated;
grant insert (id, place_id, title, body) on table public.threads to authenticated;
grant update (title, body, deleted_at) on table public.threads to authenticated;
grant insert (id, thread_id, body, quote_post_id) on table public.thread_posts to authenticated;
grant update (body, deleted_at) on table public.thread_posts to authenticated;

create policy "threads: читать свои" on public.threads
  for select to authenticated using (owner_id = (select auth.uid()));
create policy "threads: создавать свои" on public.threads
  for insert to authenticated with check (owner_id = (select auth.uid()));
create policy "threads: менять свои" on public.threads
  for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

create policy "thread_posts: читать свои" on public.thread_posts
  for select to authenticated using (owner_id = (select auth.uid()));
create policy "thread_posts: создавать свои" on public.thread_posts
  for insert to authenticated with check (owner_id = (select auth.uid()));
create policy "thread_posts: менять свои" on public.thread_posts
  for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

-- Реакции ---------------------------------------------------------------------------------------

create type public.reaction_target as enum ('trip', 'checkin', 'review', 'post');

create table public.reactions (
  target_kind public.reaction_target not null,
  target_id   uuid not null,
  owner_id    uuid not null references public.profiles (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (target_kind, target_id, owner_id)
);

create index reactions_owner_idx on public.reactions (owner_id);

alter table public.reactions enable row level security;

-- Ставятся и снимаются только через set_reaction (проверка видимости цели).
revoke all on table public.reactions from anon, authenticated;
grant select on table public.reactions to authenticated;

create policy "reactions: читать свои" on public.reactions
  for select to authenticated using (owner_id = (select auth.uid()));

-- Видит ли зритель объект реакции.
create function private.reaction_target_visible(
  p_viewer uuid,
  p_kind public.reaction_target,
  p_target uuid
) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case p_kind
    when 'trip' then exists (
      select 1 from public.trips t
       where t.id = p_target
         and t.deleted_at is null
         and private.can_view(p_viewer, t.owner_id, t.visibility))
    when 'checkin' then exists (
      select 1 from public.checkins c
        join public.places p on p.id = c.place_id
       where c.id = p_target
         and c.deleted_at is null
         and p.deleted_at is null
         and (p.status = 'published' or p.owner_id = p_viewer)
         and private.can_view(p_viewer, p.owner_id, p.visibility)
         and private.can_view(p_viewer, c.owner_id, c.visibility))
    when 'review' then exists (
      select 1 from public.reviews r
       where r.id = p_target
         and r.deleted_at is null
         and private.is_open_place(r.place_id, p_viewer)
         and (p_viewer is null or not private.is_blocked(p_viewer, r.owner_id)))
    when 'post' then exists (
      select 1 from public.thread_posts x
        join public.threads t on t.id = x.thread_id
       where x.id = p_target
         and x.deleted_at is null
         and t.deleted_at is null
         and private.is_open_place(t.place_id, p_viewer)
         and (p_viewer is null
              or (not private.is_blocked(p_viewer, x.owner_id)
                  and not private.is_blocked(p_viewer, t.owner_id))))
    else false
  end;
$$;

create function private.reaction_target_owner(p_kind public.reaction_target, p_target uuid) returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select case p_kind
    when 'trip' then (select owner_id from public.trips where id = p_target)
    when 'checkin' then (select owner_id from public.checkins where id = p_target)
    when 'review' then (select owner_id from public.reviews where id = p_target)
    when 'post' then (select owner_id from public.thread_posts where id = p_target)
  end;
$$;

-- Поставить (p_on) или снять реакцию. Возвращает число реакций у объекта.
create function public.set_reaction(p_kind public.reaction_target, p_target uuid, p_on boolean)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  total integer;
begin
  if me is null then
    raise exception 'auth required' using errcode = '28000';
  end if;
  if p_kind is null or p_target is null
     or not private.reaction_target_visible(me, p_kind, p_target) then
    raise exception 'not found' using errcode = 'P0002';
  end if;
  if private.reaction_target_owner(p_kind, p_target) = me then
    raise exception 'cannot react to own content' using errcode = '22023';
  end if;

  if coalesce(p_on, false) then
    insert into public.reactions (target_kind, target_id, owner_id)
    values (p_kind, p_target, me)
    on conflict do nothing;
  else
    delete from public.reactions
     where target_kind = p_kind and target_id = p_target and owner_id = me;
  end if;

  select count(*)::integer into total
    from public.reactions
   where target_kind = p_kind and target_id = p_target;
  return total;
end;
$$;

-- Реакции к списку объектов (пары p_kinds[i], p_ids[i]) — только к тем, что видит зритель.
create function public.reaction_summary(p_kinds public.reaction_target[], p_ids uuid[])
returns table (target_kind public.reaction_target, target_id uuid, reactions_count integer, reacted boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select i.kind, i.id,
         (select count(*)::integer from public.reactions x
           where x.target_kind = i.kind and x.target_id = i.id),
         auth.uid() is not null and exists (
           select 1 from public.reactions x
            where x.target_kind = i.kind and x.target_id = i.id and x.owner_id = auth.uid())
    from (
      select distinct u.kind, u.id
        from unnest(p_kinds[1:200], p_ids[1:200]) as u (kind, id)
       where u.kind is not null and u.id is not null
    ) i
   where private.reaction_target_visible(auth.uid(), i.kind, i.id);
$$;

-- RPC: отзывы места ---------------------------------------------------------------------------

-- Отзывы места, которые видит зритель. p_order: 'new' (по умолчанию), 'helpful', 'high', 'low'.
create function public.place_reviews(
  p_place uuid,
  p_order text default 'new',
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (
  review_id uuid,
  author_id uuid,
  author_username text,
  author_display_name text,
  author_avatar_path text,
  rating smallint,
  body text,
  visited_on date,
  created_at timestamptz,
  edited_at timestamptz,
  is_own boolean,
  helpful_count integer,
  marked_helpful boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select r.id, r.owner_id, pr.username, pr.display_name, pr.avatar_path,
         r.rating, r.body, r.visited_on, r.created_at, r.edited_at,
         r.owner_id is not distinct from auth.uid(),
         h.cnt, h.mine
    from public.reviews r
    join public.profiles pr on pr.id = r.owner_id
    cross join lateral (
      select count(*)::integer as cnt,
             coalesce(bool_or(x.owner_id = auth.uid()), false) as mine
        from public.reactions x
       where x.target_kind = 'review' and x.target_id = r.id
    ) h
   where r.place_id = p_place
     and r.deleted_at is null
     and private.is_open_place(p_place, auth.uid())
     and (auth.uid() is null or not private.is_blocked(auth.uid(), r.owner_id))
   order by
     case when p_order = 'helpful' then h.cnt end desc nulls last,
     case when p_order = 'high' then r.rating end desc nulls last,
     case when p_order = 'low' then r.rating end asc nulls last,
     r.created_at desc, r.id desc
   limit least(greatest(p_limit, 1), 100)
   offset greatest(p_offset, 0);
$$;

-- Сводка отзывов места: число, средняя оценка, распределение по звёздам (1…5), можно ли зрителю
-- оставить отзыв (есть чекин) и его отзыв. Не публичное место — пустой ответ.
create function public.place_review_summary(p_place uuid)
returns table (
  reviews_count integer,
  rating_avg numeric,
  stars integer[],
  can_review boolean,
  my_review_id uuid,
  my_rating smallint,
  my_body text,
  my_visited_on date
)
language sql
stable
security definer
set search_path = ''
as $$
  with visible as (
    select r.rating
      from public.reviews r
     where r.place_id = p_place
       and r.deleted_at is null
       and (auth.uid() is null or not private.is_blocked(auth.uid(), r.owner_id))
  )
  select (select count(*) from visible)::integer,
         (select round(avg(v.rating), 1) from visible v),
         array(select (select count(*) from visible v where v.rating = s)::integer
                 from generate_series(1, 5) s order by s),
         auth.uid() is not null and exists (
           select 1 from public.checkins c
            where c.owner_id = auth.uid() and c.place_id = p_place and c.deleted_at is null),
         mine.id, mine.rating, mine.body, mine.visited_on
    from (select 1) one
    left join public.reviews mine
      on mine.place_id = p_place and mine.owner_id = auth.uid() and mine.deleted_at is null
   where private.is_open_place(p_place, auth.uid());
$$;

-- RPC: обсуждения -------------------------------------------------------------------------------

-- Обсуждения места, свежие по активности сверху. Текст — начало (до 300 символов).
create function public.place_threads(p_place uuid, p_limit integer default 20, p_offset integer default 0)
returns table (
  thread_id uuid,
  author_id uuid,
  author_username text,
  author_display_name text,
  author_avatar_path text,
  title text,
  body_preview text,
  posts_count integer,
  last_activity_at timestamptz,
  created_at timestamptz,
  is_own boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select t.id, t.owner_id, pr.username, pr.display_name, pr.avatar_path,
         t.title, left(t.body, 300), t.posts_count, t.last_activity_at, t.created_at,
         t.owner_id is not distinct from auth.uid()
    from public.threads t
    join public.profiles pr on pr.id = t.owner_id
   where t.place_id = p_place
     and t.deleted_at is null
     and private.is_open_place(p_place, auth.uid())
     and (auth.uid() is null or not private.is_blocked(auth.uid(), t.owner_id))
   order by t.last_activity_at desc, t.id desc
   limit least(greatest(p_limit, 1), 100)
   offset greatest(p_offset, 0);
$$;

-- Обсуждение целиком (без ответов).
create function public.thread_view(p_thread uuid)
returns table (
  thread_id uuid,
  place_id uuid,
  place_name text,
  author_id uuid,
  author_username text,
  author_display_name text,
  author_avatar_path text,
  title text,
  body text,
  posts_count integer,
  last_activity_at timestamptz,
  created_at timestamptz,
  edited_at timestamptz,
  is_own boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select t.id, p.id, p.name, t.owner_id, pr.username, pr.display_name, pr.avatar_path,
         t.title, t.body, t.posts_count, t.last_activity_at, t.created_at, t.edited_at,
         t.owner_id is not distinct from auth.uid()
    from public.threads t
    join public.places p on p.id = t.place_id
    join public.profiles pr on pr.id = t.owner_id
   where t.id = p_thread
     and t.deleted_at is null
     and private.is_open_place(t.place_id, auth.uid())
     and (auth.uid() is null or not private.is_blocked(auth.uid(), t.owner_id));
$$;

-- Ответы в обсуждении по порядку. Следующая страница — после (created_at, id) последнего.
-- Цитата — автор и начало цитируемого ответа, если он виден; иначе null.
create function public.thread_posts(
  p_thread uuid,
  p_limit integer default 50,
  p_after_at timestamptz default null,
  p_after_id uuid default null
)
returns table (
  post_id uuid,
  author_id uuid,
  author_username text,
  author_display_name text,
  author_avatar_path text,
  body text,
  created_at timestamptz,
  edited_at timestamptz,
  is_own boolean,
  quote jsonb,
  reactions_count integer,
  reacted boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select x.id, x.owner_id, pr.username, pr.display_name, pr.avatar_path,
         x.body, x.created_at, x.edited_at, x.owner_id is not distinct from auth.uid(),
         (select jsonb_build_object(
                   'post_id', q.id,
                   'author_username', qp.username,
                   'author_display_name', qp.display_name,
                   'body', left(q.body, 200))
            from public.thread_posts q
            join public.profiles qp on qp.id = q.owner_id
           where q.id = x.quote_post_id
             and q.deleted_at is null
             and (auth.uid() is null or not private.is_blocked(auth.uid(), q.owner_id))),
         h.cnt, h.mine
    from public.thread_posts x
    join public.threads t on t.id = x.thread_id
    join public.profiles pr on pr.id = x.owner_id
    cross join lateral (
      select count(*)::integer as cnt,
             coalesce(bool_or(r.owner_id = auth.uid()), false) as mine
        from public.reactions r
       where r.target_kind = 'post' and r.target_id = x.id
    ) h
   where x.thread_id = p_thread
     and x.deleted_at is null
     and t.deleted_at is null
     and private.is_open_place(t.place_id, auth.uid())
     and (auth.uid() is null
          or (not private.is_blocked(auth.uid(), t.owner_id)
              and not private.is_blocked(auth.uid(), x.owner_id)))
     and (x.created_at, x.id) > (coalesce(p_after_at, '-infinity'::timestamptz),
                                 coalesce(p_after_id, '00000000-0000-0000-0000-000000000000'::uuid))
   order by x.created_at, x.id
   limit least(greatest(p_limit, 1), 200);
$$;

-- Лента друзей: плюс отзывы друзей -----------------------------------------------------------------

-- Как в миграции ленты (M4b), плюс kind 'review' (at — время отзыва). Старые версии приложения
-- записи незнакомого вида пропускают.
create or replace function public.friends_feed(
  p_limit integer default 20,
  p_before_at timestamptz default null,
  p_before_id uuid default null
)
returns table (
  kind text,
  id uuid,
  at timestamptz,
  author_id uuid,
  author_username text,
  author_display_name text,
  author_avatar_path text,
  data jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  viewer uuid := auth.uid();
  n integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  before_at timestamptz := coalesce(p_before_at, 'infinity'::timestamptz);
  before_id uuid := coalesce(p_before_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid);
begin
  if viewer is null then
    raise exception 'auth required' using errcode = '28000';
  end if;

  return query
  with friends as (
    select f.friend_id as id from public.friendships f where f.user_id = viewer
  ),
  items as (
    (select 'trip'::text as kind, t.id, t.ended_at as at, t.owner_id as author_id,
            jsonb_build_object(
              'activity', t.activity,
              'title', t.title,
              'note', t.note,
              'started_at', t.started_at,
              'ended_at', t.ended_at,
              'moving_seconds', t.moving_seconds,
              'distance_m', t.distance_m,
              'elevation_gain_m', t.elevation_gain_m
            ) as data
       from public.trips t
       join friends fr on fr.id = t.owner_id
      where t.deleted_at is null
        and (t.ended_at, t.id) < (before_at, before_id)
        and private.can_view(viewer, t.owner_id, t.visibility)
      order by t.ended_at desc, t.id desc
      limit n)
    union all
    (select 'checkin', c.id, c.at, c.owner_id,
            jsonb_build_object(
              'place_id', p.id,
              'place_name', p.name,
              'place_type', p.type,
              'verified', c.verified,
              'conditions', c.conditions,
              'note', c.note,
              'catches', private.checkin_catches_json(c.id, viewer),
              'media', private.checkin_media_json(c.id, viewer)
            )
       from public.checkins c
       join friends fr on fr.id = c.owner_id
       join public.places p on p.id = c.place_id
      where c.deleted_at is null
        and (c.at, c.id) < (before_at, before_id)
        and p.deleted_at is null
        and p.status = 'published'
        and private.can_view(viewer, p.owner_id, p.visibility)
        and private.can_view(viewer, c.owner_id, c.visibility)
      order by c.at desc, c.id desc
      limit n)
    union all
    (select 'place', p.id, p.created_at, p.owner_id,
            jsonb_build_object(
              'place_type', p.type,
              'name', p.name,
              'approximate', p.approximate
            )
       from public.places p
       join friends fr on fr.id = p.owner_id
      where p.deleted_at is null
        and p.status = 'published'
        and (p.created_at, p.id) < (before_at, before_id)
        and private.can_view(viewer, p.owner_id, p.visibility)
      order by p.created_at desc, p.id desc
      limit n)
    union all
    (select 'review', r.id, r.created_at, r.owner_id,
            jsonb_build_object(
              'place_id', p.id,
              'place_name', p.name,
              'place_type', p.type,
              'rating', r.rating,
              'body', r.body
            )
       from public.reviews r
       join friends fr on fr.id = r.owner_id
       join public.places p on p.id = r.place_id
      where r.deleted_at is null
        and (r.created_at, r.id) < (before_at, before_id)
        and private.is_open_place(r.place_id, viewer)
      order by r.created_at desc, r.id desc
      limit n)
  )
  select i.kind, i.id, i.at, i.author_id, pr.username, pr.display_name, pr.avatar_path, i.data
    from items i
    join public.profiles pr on pr.id = i.author_id
   order by i.at desc, i.id desc
   limit n;
end;
$$;

-- Права на функции ------------------------------------------------------------------------------

revoke execute on function
  public.save_review(uuid, integer, text, date),
  public.delete_review(uuid),
  public.set_reaction(public.reaction_target, uuid, boolean),
  public.reaction_summary(public.reaction_target[], uuid[]),
  public.place_reviews(uuid, text, integer, integer),
  public.place_review_summary(uuid),
  public.place_threads(uuid, integer, integer),
  public.thread_view(uuid),
  public.thread_posts(uuid, integer, timestamptz, uuid)
from public, anon;

grant execute on function
  public.save_review(uuid, integer, text, date),
  public.delete_review(uuid),
  public.set_reaction(public.reaction_target, uuid, boolean),
  public.reaction_summary(public.reaction_target[], uuid[])
to authenticated;

-- Отзывы и обсуждения публичных мест читают и гости.
grant execute on function
  public.place_reviews(uuid, text, integer, integer),
  public.place_review_summary(uuid),
  public.place_threads(uuid, integer, integer),
  public.thread_view(uuid),
  public.thread_posts(uuid, integer, timestamptz, uuid)
to anon, authenticated;
