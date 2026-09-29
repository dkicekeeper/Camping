-- «Мои места» для вкладки «Места» (веха M1b): свои места любой видимости, включая
-- места на модерации. Форма ответа — как у places_in_bbox, чтобы клиент разбирал её одинаково.
-- security invoker: работает под RLS таблицы places (только свои строки).

create function public.my_places()
returns table (
  id uuid,
  owner_id uuid,
  type public.place_type,
  name text,
  lon double precision,
  lat double precision,
  approximate boolean,
  radius_m integer,
  visibility public.visibility,
  status public.place_status,
  is_own boolean
)
language sql
stable
security invoker
set search_path = ''
as $$
  select p.id, p.owner_id, p.type, p.name,
         extensions.st_x(p.geom), extensions.st_y(p.geom),
         false, 0,
         p.visibility, p.status, true
    from public.places p
   where p.owner_id = auth.uid()
     and p.deleted_at is null
   order by p.created_at desc;
$$;

revoke execute on function public.my_places() from public, anon;
grant execute on function public.my_places() to authenticated;
