-- Фото к чекинам и уловам (M2b).
--
-- Файлы лежат в закрытом бакете `media`: `<owner_id>/<media_id>.jpg` (до 1600 px) и
-- `<owner_id>/<media_id>_thumb.jpg` (до 400 px). Телефон сжимает фото и убирает метаданные
-- (в том числе геометку) до загрузки.
--
-- Своего поля видимости у фото нет: фото видно тем, кто видит его чекин, место и улов (если фото
-- привязано к улову). Поменяли видимость чекина — поменялась видимость фото.
--
-- Порядок загрузки: чекин → уловы → файлы → строки `media`. Строка появляется, только когда файлы
-- уже загружены.

-- Фото -------------------------------------------------------------------------------------------

create table public.media (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  checkin_id    uuid not null references public.checkins (id) on delete cascade,
  catch_id      uuid references public.catches (id) on delete cascade,
  place_id      uuid references public.places (id) on delete cascade,
  storage_path  text generated always as (owner_id::text || '/' || id::text || '.jpg') stored,
  width         integer check (width between 1 and 10000),
  height        integer check (height between 1 and 10000),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);

create index media_checkin_idx on public.media (checkin_id, created_at);
create index media_owner_idx on public.media (owner_id, created_at desc);
create index media_catch_idx on public.media (catch_id) where catch_id is not null;

-- Больше фото на один чекин не принимаем (в приложении — до 5 к чекину и по одному к улову).
create function private.media_per_checkin_limit() returns integer
language sql immutable
set search_path = ''
as $$ select 20 $$;

create function private.media_before_write() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  ch public.checkins;
  k public.catches;
begin
  if tg_op = 'INSERT' then
    if private.is_client_request() then
      new.owner_id := auth.uid();
    end if;
    new.created_at := now();
  else
    new.owner_id := old.owner_id;
    new.checkin_id := old.checkin_id;
    new.catch_id := old.catch_id;
    new.created_at := old.created_at;
  end if;

  if new.owner_id is null then
    raise exception 'auth required' using errcode = '28000';
  end if;

  -- Фото только к своему чекину; место берём из чекина.
  select * into ch from public.checkins where id = new.checkin_id;
  if not found or ch.owner_id <> new.owner_id or ch.deleted_at is not null then
    raise exception 'checkin not found' using errcode = 'P0002';
  end if;
  new.place_id := ch.place_id;

  -- Фото улова: улов свой и из того же чекина.
  if new.catch_id is not null then
    select * into k from public.catches where id = new.catch_id;
    if not found
       or k.owner_id <> new.owner_id
       or k.checkin_id is distinct from new.checkin_id
       or k.deleted_at is not null then
      raise exception 'catch not found' using errcode = 'P0002';
    end if;
  end if;

  if tg_op = 'INSERT'
     and (select count(*) from public.media m
           where m.checkin_id = new.checkin_id and m.deleted_at is null)
         >= private.media_per_checkin_limit() then
    raise exception 'too many photos' using errcode = '54000';
  end if;

  new.updated_at := now();
  return new;
end;
$$;

create trigger media_before_write before insert or update on public.media
  for each row execute function private.media_before_write();

alter table public.media enable row level security;

revoke all on table public.media from anon, authenticated;
grant select on table public.media to authenticated;
grant insert (id, checkin_id, catch_id, width, height) on table public.media to authenticated;
grant update (deleted_at) on table public.media to authenticated;

create policy "media: читать свои" on public.media
  for select to authenticated using (owner_id = (select auth.uid()));

create policy "media: создавать свои" on public.media
  for insert to authenticated with check (owner_id = (select auth.uid()));

create policy "media: менять свои" on public.media
  for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

-- Видит ли зритель фото: своё — всегда; чужое — если видит место, чекин и улов.
create function private.media_visible(viewer uuid, p_media uuid) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.media m
      join public.checkins c on c.id = m.checkin_id
      join public.places p on p.id = c.place_id
      left join public.catches k on k.id = m.catch_id
     where m.id = p_media
       and m.deleted_at is null
       and (
         (viewer is not null and m.owner_id = viewer)
         or (
           c.deleted_at is null
           and p.deleted_at is null
           and (p.status = 'published' or p.owner_id = viewer)
           and private.can_view(viewer, p.owner_id, p.visibility)
           and private.can_view(viewer, c.owner_id, c.visibility)
           and (m.catch_id is null
                or (k.deleted_at is null and private.can_view(viewer, k.owner_id, k.visibility)))
         )
       )
  );
$$;

-- Хранилище -------------------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('media', 'media', false, 5242880, array['image/jpeg'])
on conflict (id) do nothing;

-- Функции для политик хранилища. Политики выполняются от имени клиента, а схема `private` для
-- него закрыта, поэтому нужна отдельная схема с одной функцией. Через API она не доступна:
-- открыты только `public` и `graphql_public`.
create schema if not exists rls;
revoke all on schema rls from public;
grant usage on schema rls to anon, authenticated;

-- Можно ли читать объект бакета `media` (в том числе подписывать ссылку на него).
create function rls.can_read_media_object(object_name text) returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  parts text[] := regexp_match(
    object_name,
    '^([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})(_thumb)?\.jpg$'
  );
begin
  if parts is null then
    return false;
  end if;
  -- Свои файлы — всегда (строки `media` ещё может не быть: она создаётся после загрузки).
  if auth.uid() is not null and parts[1] = auth.uid()::text then
    return true;
  end if;
  return private.media_visible(auth.uid(), parts[2]::uuid);
end;
$$;

revoke execute on function rls.can_read_media_object(text) from public;
grant execute on function rls.can_read_media_object(text) to anon, authenticated;

create policy "media: загружать в свою папку" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'media'
    and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}(_thumb)?\.jpg$'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "media: читать видимые" on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'media' and rls.can_read_media_object(name));

create policy "media: удалять свои" on storage.objects
  for delete to authenticated
  using (bucket_id = 'media' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- Отчёты места с фото ---------------------------------------------------------------------------

-- Как `place_reports` из миграции уловов, плюс `media`: фото чекина и уловов, которые видит
-- зритель, — пути к файлу и превью в бакете `media`.
drop function public.place_reports(uuid, integer);

create function public.place_reports(p_place uuid, p_limit integer default 20)
returns table (
  checkin_id uuid,
  author_id uuid,
  author_username text,
  author_display_name text,
  at timestamptz,
  verified boolean,
  conditions jsonb,
  note text,
  is_own boolean,
  catches jsonb,
  media jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id, c.owner_id, pr.username, pr.display_name, c.at, c.verified, c.conditions, c.note,
         c.owner_id = auth.uid(),
         coalesce((
           select jsonb_agg(jsonb_build_object(
                    'id', k.id,
                    'species_id', k.species_id,
                    'count', k.count,
                    'released', k.released,
                    'weight_g', case when k.hide_size and k.owner_id is distinct from auth.uid() then null else k.weight_g end,
                    'length_mm', case when k.hide_size and k.owner_id is distinct from auth.uid() then null else k.length_mm end
                  ) order by k.at)
             from public.catches k
            where k.checkin_id = c.id
              and k.deleted_at is null
              and private.can_view(auth.uid(), k.owner_id, k.visibility)
         ), '[]'::jsonb),
         coalesce((
           select jsonb_agg(jsonb_build_object(
                    'id', m.id,
                    'catch_id', m.catch_id,
                    'path', m.storage_path,
                    'thumb_path', m.owner_id::text || '/' || m.id::text || '_thumb.jpg',
                    'width', m.width,
                    'height', m.height
                  ) order by m.created_at, m.id)
             from public.media m
            where m.checkin_id = c.id
              and private.media_visible(auth.uid(), m.id)
         ), '[]'::jsonb)
    from public.checkins c
    join public.places p on p.id = c.place_id
    join public.profiles pr on pr.id = c.owner_id
   where c.place_id = p_place
     and c.deleted_at is null
     and p.deleted_at is null
     and (p.status = 'published' or p.owner_id = auth.uid())
     and private.can_view(auth.uid(), p.owner_id, p.visibility)
     and private.can_view(auth.uid(), c.owner_id, c.visibility)
   order by c.at desc
   limit least(greatest(p_limit, 1), 100);
$$;

revoke execute on function public.place_reports(uuid, integer) from public;
grant execute on function public.place_reports(uuid, integer) to anon, authenticated;
