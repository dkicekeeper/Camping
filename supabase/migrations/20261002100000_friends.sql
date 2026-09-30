-- Друзья: поиск людей, запросы, блокировки (M4a).
--
-- Сама дружба (запрос → принятие, обе стороны в friendships, блокировка разрывает дружбу) — с M0.
-- Здесь то, что нужно экранам: найти человека, увидеть входящие и исходящие запросы, отменить свой
-- запрос, увидеть, кого заблокировал. Заблокированные в обе стороны друг друга не находят.

-- Поиск: @username с начала или имя целиком (любая часть), от двух символов. Себя и тех, кто ещё
-- не выбрал username, не показываем.
create function public.search_profiles(p_query text, p_limit integer default 20)
returns table (
  id uuid,
  username text,
  display_name text,
  avatar_path text,
  is_friend boolean,
  request_status text
)
language sql
stable
security definer
set search_path = ''
as $$
  with q as (
    -- Символы шаблона LIKE в запросе — обычные символы.
    select replace(replace(replace(lower(trim(both '@ ' from p_query)), '\', '\\'), '%', '\%'), '_', '\_') as text
  )
  select p.id, p.username, p.display_name, p.avatar_path,
         private.are_friends(auth.uid(), p.id),
         (select case when r.from_user = auth.uid() then 'outgoing' else 'incoming' end
            from public.friend_requests r
           where r.status = 'pending'
             and ((r.from_user = auth.uid() and r.to_user = p.id)
               or (r.from_user = p.id and r.to_user = auth.uid()))
           limit 1)
    from public.profiles p, q
   where char_length(q.text) >= 2
     and p.username is not null
     and p.id <> auth.uid()
     and not private.is_blocked(auth.uid(), p.id)
     and (p.username like q.text || '%' or lower(p.display_name) like '%' || q.text || '%')
   order by (p.username like q.text || '%') desc, p.username
   limit least(greatest(p_limit, 1), 50);
$$;

-- Ожидающие запросы: входящие и исходящие, с профилем другой стороны.
create function public.my_friend_requests()
returns table (
  request_id uuid,
  direction text,
  user_id uuid,
  username text,
  display_name text,
  avatar_path text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select r.id,
         case when r.to_user = auth.uid() then 'incoming' else 'outgoing' end,
         p.id, p.username, p.display_name, p.avatar_path, r.created_at
    from public.friend_requests r
    join public.profiles p
      on p.id = case when r.to_user = auth.uid() then r.from_user else r.to_user end
   where r.status = 'pending'
     and auth.uid() in (r.from_user, r.to_user)
     and not private.is_blocked(auth.uid(), p.id)
   order by r.created_at desc;
$$;

-- Отменить свой запрос, пока его не приняли.
create function public.cancel_friend_request(p_request uuid) returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.friend_requests
   where id = p_request
     and from_user = auth.uid()
     and status = 'pending';
$$;

-- Кого я заблокировал — с профилем, чтобы можно было разблокировать.
create function public.my_blocks()
returns table (user_id uuid, username text, display_name text, avatar_path text, created_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.username, p.display_name, p.avatar_path, b.created_at
    from public.blocks b
    join public.profiles p on p.id = b.blocked_id
   where b.blocker_id = auth.uid()
   order by b.created_at desc;
$$;

revoke execute on function
  public.search_profiles(text, integer),
  public.my_friend_requests(),
  public.cancel_friend_request(uuid),
  public.my_blocks()
from public, anon;

grant execute on function
  public.search_profiles(text, integer),
  public.my_friend_requests(),
  public.cancel_friend_request(uuid),
  public.my_blocks()
to authenticated;
