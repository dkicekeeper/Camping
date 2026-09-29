-- Друзья, запросы в друзья, блокировки и общая функция видимости.
--
-- Дружба взаимная: запрос → принятие. Храним обе стороны (user_id → friend_id и обратно),
-- чтобы «мои друзья» было простым запросом. Меняется только через RPC.

create table public.friend_requests (
  id           uuid primary key default gen_random_uuid(),
  from_user    uuid not null references public.profiles (id) on delete cascade,
  to_user      uuid not null references public.profiles (id) on delete cascade,
  status       text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
  created_at   timestamptz not null default now(),
  responded_at timestamptz,
  check (from_user <> to_user)
);

-- Не больше одного ожидающего запроса на пару пользователей, в любую сторону.
create unique index friend_requests_one_pending
  on public.friend_requests (least(from_user, to_user), greatest(from_user, to_user))
  where status = 'pending';

create table public.friendships (
  user_id    uuid not null references public.profiles (id) on delete cascade,
  friend_id  uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, friend_id),
  check (user_id <> friend_id)
);

create table public.blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

alter table public.friend_requests enable row level security;
alter table public.friendships enable row level security;
alter table public.blocks enable row level security;

revoke all on table public.friend_requests, public.friendships, public.blocks from anon, authenticated;
grant select on table public.friend_requests, public.friendships to authenticated;
grant select, delete on table public.blocks to authenticated;
grant insert (blocked_id) on table public.blocks to authenticated;

create policy "friend_requests: свои входящие и исходящие" on public.friend_requests
  for select to authenticated
  using ((select auth.uid()) in (from_user, to_user));

create policy "friendships: свои" on public.friendships
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy "blocks: читать свои" on public.blocks
  for select to authenticated using (blocker_id = (select auth.uid()));

create policy "blocks: блокировать от своего имени" on public.blocks
  for insert to authenticated with check (blocker_id = (select auth.uid()));

create policy "blocks: снимать свои" on public.blocks
  for delete to authenticated using (blocker_id = (select auth.uid()));

alter table public.blocks alter column blocker_id set default auth.uid();

-- Блокировка разрывает дружбу и отменяет ожидающие запросы.
create function private.blocks_after_insert() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.friendships
   where (user_id = new.blocker_id and friend_id = new.blocked_id)
      or (user_id = new.blocked_id and friend_id = new.blocker_id);
  update public.friend_requests
     set status = 'declined', responded_at = now()
   where status = 'pending'
     and ((from_user = new.blocker_id and to_user = new.blocked_id)
       or (from_user = new.blocked_id and to_user = new.blocker_id));
  return new;
end;
$$;

create trigger blocks_after_insert after insert on public.blocks
  for each row execute function private.blocks_after_insert();

-- Помощники видимости ------------------------------------------------------------------------

create function private.are_friends(a uuid, b uuid) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.friendships f where f.user_id = a and f.friend_id = b);
$$;

create function private.is_blocked(a uuid, b uuid) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.blocks bl
     where (bl.blocker_id = a and bl.blocked_id = b)
        or (bl.blocker_id = b and bl.blocked_id = a)
  );
$$;

-- Единственная функция, которая решает «видит ли viewer объект owner с видимостью vis».
-- viewer = null — гость.
create function private.can_view(viewer uuid, owner uuid, vis public.visibility) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when viewer is not null and viewer = owner then true
    when viewer is not null and private.is_blocked(viewer, owner) then false
    when vis = 'public' then true
    when vis = 'friends' then viewer is not null and private.are_friends(viewer, owner)
    else false
  end;
$$;

-- RPC: друзья --------------------------------------------------------------------------------

-- Отправить запрос. Если встречный запрос уже ждёт — сразу становимся друзьями.
-- Возвращает 'sent' | 'accepted' | 'already_friends'.
create function public.send_friend_request(p_to uuid) returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  incoming uuid;
begin
  if me is null then
    raise exception 'auth required' using errcode = '28000';
  end if;
  if p_to is null or p_to = me or not exists (select 1 from public.profiles where id = p_to) then
    raise exception 'user not found' using errcode = 'P0002';
  end if;
  if private.is_blocked(me, p_to) then
    raise exception 'user not found' using errcode = 'P0002';
  end if;
  if private.are_friends(me, p_to) then
    return 'already_friends';
  end if;

  select id into incoming from public.friend_requests
   where from_user = p_to and to_user = me and status = 'pending';

  if incoming is not null then
    perform public.respond_friend_request(incoming, true);
    return 'accepted';
  end if;

  insert into public.friend_requests (from_user, to_user)
  values (me, p_to)
  on conflict do nothing;
  return 'sent';
end;
$$;

-- Принять или отклонить входящий запрос.
create function public.respond_friend_request(p_request uuid, p_accept boolean) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  req public.friend_requests;
begin
  select * into req from public.friend_requests
   where id = p_request and to_user = me and status = 'pending'
   for update;
  if not found then
    raise exception 'request not found' using errcode = 'P0002';
  end if;

  update public.friend_requests
     set status = case when p_accept then 'accepted' else 'declined' end,
         responded_at = now()
   where id = req.id;

  if p_accept then
    insert into public.friendships (user_id, friend_id)
    values (req.from_user, req.to_user), (req.to_user, req.from_user)
    on conflict do nothing;
  end if;
end;
$$;

create function public.remove_friend(p_friend uuid) returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.friendships
   where (user_id = auth.uid() and friend_id = p_friend)
      or (user_id = p_friend and friend_id = auth.uid());
$$;

-- Публичная карточка пользователя по username (без блокировавших друг друга).
create function public.profile_by_username(p_username text)
returns table (
  id uuid,
  username text,
  display_name text,
  avatar_path text,
  city text,
  is_friend boolean,
  request_status text
)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.username, p.display_name, p.avatar_path, p.city,
         private.are_friends(auth.uid(), p.id),
         (select case when r.from_user = auth.uid() then 'outgoing' else 'incoming' end
            from public.friend_requests r
           where r.status = 'pending'
             and ((r.from_user = auth.uid() and r.to_user = p.id)
               or (r.from_user = p.id and r.to_user = auth.uid()))
           limit 1)
    from public.profiles p
   where p.username = lower(p_username)
     and (auth.uid() is null or not private.is_blocked(auth.uid(), p.id));
$$;

-- Мои друзья с публичными полями профиля.
create function public.my_friends()
returns table (id uuid, username text, display_name text, avatar_path text, city text, since timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.username, p.display_name, p.avatar_path, p.city, f.created_at
    from public.friendships f
    join public.profiles p on p.id = f.friend_id
   where f.user_id = auth.uid()
   order by p.username;
$$;

revoke execute on function
  public.send_friend_request(uuid),
  public.respond_friend_request(uuid, boolean),
  public.remove_friend(uuid),
  public.profile_by_username(text),
  public.my_friends()
from public, anon;

grant execute on function
  public.send_friend_request(uuid),
  public.respond_friend_request(uuid, boolean),
  public.remove_friend(uuid),
  public.profile_by_username(text),
  public.my_friends()
to authenticated;
