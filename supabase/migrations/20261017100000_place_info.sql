-- Карточка места (M8d): «Информация» о месте и предложения правок.
--
-- Атрибуты (`places.attributes`) — то, что не меняется от поездки к поездке: рыба, подъезд,
-- стоимость, способы ловли, удобства, связь, лучшие месяцы, особенности. Своё место автор меняет
-- напрямую (колонка уже открыта на запись), места редакции — редакция в Studio. От приложения
-- принимаются только известные ключи с допустимыми значениями; служебные `source` и `osm`
-- приложение не ставит и не меняет. Текст («особенности», контакты) проходит фильтр слов.
--
-- Свежие условия (клёв, вода, людность, дорога) — в чекинах, а не здесь.
--
-- Предложение правки (название, тип, описание, атрибуты) или сообщение о проблеме (не та точка,
-- закрыто, не существует, дубль, опасно) — к чужому публичному опубликованному месту, только через
-- suggest_place_change. Разбирает редакция в Studio: очередь — private.place_suggestion_queue,
-- принять правку — private.accept_place_suggestion(id). Автор видит только свои предложения.
--
-- Коды ошибок: 22023 — неверные данные; P0002 — место не найдено (или не видно); DL003 — слишком
-- часто; DL005 — грубые слова.

-- Атрибуты места ----------------------------------------------------------------------------------

-- Массив разных строк из списка допустимых.
create function private.jsonb_text_set_valid(p jsonb, allowed text[]) returns boolean
language sql
immutable
set search_path = ''
as $$
  select jsonb_typeof(p) = 'array'
     and jsonb_array_length(p) <= cardinality(allowed)
     and not exists (
       select 1 from jsonb_array_elements(p) e
        where jsonb_typeof(e) <> 'string' or (e #>> '{}') <> all (allowed)
     )
     and (select count(distinct e) = count(*) from jsonb_array_elements(p) e);
$$;

-- Атрибуты, которые может записать приложение (без служебных `source` и `osm`).
create function private.place_attributes_valid(p jsonb) returns boolean
language plpgsql
stable
set search_path = ''
as $$
begin
  if p is null or jsonb_typeof(p) <> 'object' or octet_length(p::text) > 4000 then
    return false;
  end if;
  if exists (
    select 1 from jsonb_object_keys(p) k
     where k not in ('species', 'access', 'fee', 'price_kzt', 'price_unit', 'contact', 'methods',
                     'amenities', 'signal', 'months', 'features')
  ) then
    return false;
  end if;

  -- Рыба: id из справочника, без повторов.
  if p ? 'species' and not (
    jsonb_typeof(p -> 'species') = 'array'
    and jsonb_array_length(p -> 'species') <= 40
    and not exists (
      select 1 from jsonb_array_elements(p -> 'species') e
       where jsonb_typeof(e) <> 'string'
          or not exists (select 1 from public.fish_species s where s.id = e #>> '{}')
    )
    and (select count(distinct e) = count(*) from jsonb_array_elements(p -> 'species') e)
  ) then
    return false;
  end if;

  -- Подъезд: асфальт, грунт, только 4×4, пешком, на лодке.
  if p ? 'access'
     and not private.jsonb_text_set_valid(p -> 'access', array['asphalt', 'dirt', 'offroad', 'foot', 'boat']) then
    return false;
  end if;

  -- Стоимость: бесплатно или платно; цена в тенге и за что (вход, сутки, час, кг улова); контакты.
  if p ? 'fee' and coalesce(p ->> 'fee', '') not in ('free', 'paid') then
    return false;
  end if;
  if p ? 'price_kzt' and not (
    jsonb_typeof(p -> 'price_kzt') = 'number'
    and (p ->> 'price_kzt')::numeric between 0 and 1000000
    and (p ->> 'price_kzt')::numeric = trunc((p ->> 'price_kzt')::numeric)
  ) then
    return false;
  end if;
  if p ? 'price_unit' and coalesce(p ->> 'price_unit', '') not in ('entry', 'day', 'hour', 'kg') then
    return false;
  end if;
  if p ? 'contact' and not (
    jsonb_typeof(p -> 'contact') = 'string' and char_length(p ->> 'contact') between 1 and 100
  ) then
    return false;
  end if;

  -- Способы ловли: с берега, с лодки, спиннинг, фидер, поплавок, нахлыст, донка, зимняя.
  if p ? 'methods' and not private.jsonb_text_set_valid(
    p -> 'methods', array['shore', 'boat', 'spinning', 'feeder', 'float', 'fly', 'bottom', 'ice']
  ) then
    return false;
  end if;

  -- Удобства: парковка, туалет, тень, место под палатку, костровище, питьевая вода, магазин рядом,
  -- прокат лодок.
  if p ? 'amenities' and not private.jsonb_text_set_valid(
    p -> 'amenities',
    array['parking', 'toilet', 'shade', 'tent', 'fireplace', 'drinking_water', 'shop', 'boat_rental']
  ) then
    return false;
  end if;

  -- Связь: нет, слабая, хорошая.
  if p ? 'signal' and coalesce(p ->> 'signal', '') not in ('none', 'weak', 'good') then
    return false;
  end if;

  -- Лучшие месяцы: 1–12 без повторов.
  if p ? 'months' and not (
    jsonb_typeof(p -> 'months') = 'array'
    and jsonb_array_length(p -> 'months') <= 12
    and not exists (
      select 1 from jsonb_array_elements(p -> 'months') e
       where jsonb_typeof(e) <> 'number'
          or (e #>> '{}')::numeric not in (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12)
    )
    and (select count(distinct e) = count(*) from jsonb_array_elements(p -> 'months') e)
  ) then
    return false;
  end if;

  -- Особенности: глубина, дно, коряги, течение — свободный текст.
  if p ? 'features' and not (
    jsonb_typeof(p -> 'features') = 'string' and char_length(p ->> 'features') between 1 and 1000
  ) then
    return false;
  end if;

  return true;
end;
$$;

-- Служебные ключи атрибутов: откуда место (редакция, OpenStreetMap). Ставит только редакция.
create function private.place_service_attributes(p jsonb) returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(
    (select jsonb_object_agg(e.key, e.value)
       from jsonb_each(coalesce(p, '{}'::jsonb)) e
      where e.key in ('source', 'osm')),
    '{}'::jsonb
  );
$$;

-- Запись из приложения: служебные ключи — как были (у нового места — никаких), остальное проверяем.
-- Если атрибуты не менялись, не проверяем: старые места редакции могут хранить другие ключи.
create function private.places_attributes_guard() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_client_request() then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.attributes is not distinct from old.attributes then
    return new;
  end if;
  new.attributes := coalesce(new.attributes, '{}'::jsonb);
  if jsonb_typeof(new.attributes) <> 'object'
     or not private.place_attributes_valid(new.attributes - 'source' - 'osm') then
    raise exception 'invalid place attributes' using errcode = '22023';
  end if;
  new.attributes := (new.attributes - 'source' - 'osm')
    || case when tg_op = 'UPDATE' then private.place_service_attributes(old.attributes) else '{}'::jsonb end;
  return new;
end;
$$;

-- Имя «places_attributes_…» — раньше places_before_write и фильтра слов (триггеры идут по алфавиту).
create trigger places_attributes_guard before insert or update on public.places
  for each row execute function private.places_attributes_guard();

-- Фильтр слов — и для текста в атрибутах (особенности, контакты).
drop trigger places_word_filter on public.places;
create trigger places_word_filter before insert or update on public.places
  for each row execute function private.word_filter('name', 'description', 'attributes');

-- Предложения правок ------------------------------------------------------------------------------

-- edit — правка полей; wrong_location — не та точка; closed — закрыто; not_exists — не существует;
-- duplicate — дубль; dangerous — опасно.
create type public.place_suggestion_kind as enum (
  'edit', 'wrong_location', 'closed', 'not_exists', 'duplicate', 'dangerous'
);

create type public.place_suggestion_status as enum ('open', 'accepted', 'rejected');

create table public.place_suggestions (
  id            uuid primary key default gen_random_uuid(),
  place_id      uuid not null references public.places (id) on delete cascade,
  author_id     uuid not null references public.profiles (id) on delete cascade,
  kind          public.place_suggestion_kind not null,
  -- Только у edit: предложенные name, type, description, attributes.
  changes       jsonb not null default '{}'::jsonb check (jsonb_typeof(changes) = 'object'),
  note          text check (char_length(note) <= 1000),
  status        public.place_suggestion_status not null default 'open',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  decided_at    timestamptz,
  decision_note text
);

-- Открытое предложение одного вида от человека к месту — одно (повторное его обновляет).
create unique index place_suggestions_open_idx
  on public.place_suggestions (author_id, place_id, kind) where status = 'open';
create index place_suggestions_place_idx on public.place_suggestions (place_id);
create index place_suggestions_author_idx on public.place_suggestions (author_id, created_at);

alter table public.place_suggestions enable row level security;

revoke all on table public.place_suggestions from anon, authenticated;
-- Пишется только через suggest_place_change; свои строки можно прочитать («на проверке»).
grant select on table public.place_suggestions to authenticated;

create policy "place_suggestions: читать свои" on public.place_suggestions
  for select to authenticated using (author_id = (select auth.uid()));

-- Предложений в сутки от одного человека.
create function private.place_suggestions_daily_limit() returns integer
language sql immutable
set search_path = ''
as $$ select 20 $$;

create function public.suggest_place_change(
  p_place uuid,
  p_kind public.place_suggestion_kind,
  p_changes jsonb default null,
  p_note text default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_changes jsonb := coalesce(p_changes, '{}'::jsonb);
  v_place public.places;
  v_name text;
  v_id uuid;
begin
  if me is null then
    raise exception 'auth required' using errcode = '28000';
  end if;
  if p_kind is null then
    raise exception 'kind required' using errcode = '22023';
  end if;
  if v_note is not null and char_length(v_note) > 1000 then
    raise exception 'note is too long' using errcode = '22023';
  end if;

  -- Только чужое публичное опубликованное место, которое человек видит. Своё правят напрямую,
  -- в местах «для друзей» проще написать автору.
  select p.* into v_place
    from public.places p
   where p.id = p_place
     and p.deleted_at is null
     and p.status = 'published'
     and p.visibility = 'public'
     and private.can_view(me, p.owner_id, p.visibility);
  if not found then
    raise exception 'place not found' using errcode = 'P0002';
  end if;
  if v_place.owner_id = me then
    raise exception 'own place: edit it directly' using errcode = '22023';
  end if;

  if jsonb_typeof(v_changes) <> 'object' then
    raise exception 'invalid changes' using errcode = '22023';
  end if;
  if p_kind = 'edit' then
    if v_changes = '{}'::jsonb
       or exists (
         select 1 from jsonb_object_keys(v_changes) k
          where k not in ('name', 'type', 'description', 'attributes')
       ) then
      raise exception 'invalid changes' using errcode = '22023';
    end if;
    if v_changes ? 'name' then
      v_name := btrim(coalesce(v_changes ->> 'name', ''));
      if jsonb_typeof(v_changes -> 'name') <> 'string' or char_length(v_name) not between 1 and 80 then
        raise exception 'invalid name' using errcode = '22023';
      end if;
      v_changes := jsonb_set(v_changes, '{name}', to_jsonb(v_name));
    end if;
    if v_changes ? 'type' and (
      jsonb_typeof(v_changes -> 'type') <> 'string'
      or not ((v_changes ->> 'type') = any (enum_range(null::public.place_type)::text[]))
    ) then
      raise exception 'invalid type' using errcode = '22023';
    end if;
    if v_changes ? 'description' and (
      jsonb_typeof(v_changes -> 'description') <> 'string'
      or char_length(v_changes ->> 'description') > 2000
    ) then
      raise exception 'invalid description' using errcode = '22023';
    end if;
    if v_changes ? 'attributes' and not private.place_attributes_valid(v_changes -> 'attributes') then
      raise exception 'invalid place attributes' using errcode = '22023';
    end if;
  elsif v_changes <> '{}'::jsonb then
    raise exception 'changes only for edit' using errcode = '22023';
  end if;

  -- Предложения видит только редакция, но принятая правка станет видна всем.
  if private.has_banned_words(v_changes::text) or private.has_banned_words(v_note) then
    raise exception 'text contains banned words' using errcode = 'DL005';
  end if;

  perform pg_advisory_xact_lock(hashtext('place_suggestions:' || me::text));
  select s.id into v_id
    from public.place_suggestions s
   where s.author_id = me and s.place_id = p_place and s.kind = p_kind and s.status = 'open';
  if v_id is not null then
    update public.place_suggestions
       set changes = v_changes, note = v_note, updated_at = now()
     where id = v_id;
    return v_id;
  end if;

  if (select count(*) from public.place_suggestions s
       where s.author_id = me and s.created_at > now() - interval '1 day')
     >= private.place_suggestions_daily_limit() then
    raise exception 'too many suggestions today' using errcode = 'DL003';
  end if;

  insert into public.place_suggestions (place_id, author_id, kind, changes, note)
  values (p_place, me, p_kind, v_changes, v_note)
  returning id into v_id;
  return v_id;
end;
$$;

revoke execute on function public.suggest_place_change(uuid, public.place_suggestion_kind, jsonb, text) from public;
grant execute on function public.suggest_place_change(uuid, public.place_suggestion_kind, jsonb, text) to authenticated;

-- Для редакции (Studio) -----------------------------------------------------------------------------

-- Открытые предложения: место, автор, что предлагают; сначала места, о которых пишут чаще.
create view private.place_suggestion_queue as
select s.id,
       s.kind,
       s.place_id,
       p.name as place_name,
       p.owner_id as place_owner_id,
       pr.username as author_username,
       s.changes,
       s.note,
       s.created_at,
       s.updated_at,
       count(*) over (partition by s.place_id) as place_open_suggestions
  from public.place_suggestions s
  join public.places p on p.id = s.place_id
  join public.profiles pr on pr.id = s.author_id
 where s.status = 'open'
 order by count(*) over (partition by s.place_id) desc, s.created_at;

-- Принять: правка применяется к месту (атрибуты заменяются целиком, служебные ключи остаются),
-- о проблеме — только отметка (скрыть или удалить место редакция решает сама).
create function private.accept_place_suggestion(p_id uuid, p_note text default null) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.place_suggestions;
begin
  select * into s from public.place_suggestions where id = p_id and status = 'open' for update;
  if not found then
    raise exception 'open suggestion not found' using errcode = 'P0002';
  end if;
  if s.kind = 'edit' then
    update public.places p
       set name = coalesce(s.changes ->> 'name', p.name),
           type = coalesce((s.changes ->> 'type')::public.place_type, p.type),
           description = case
             when s.changes ? 'description' then nullif(btrim(s.changes ->> 'description'), '')
             else p.description
           end,
           attributes = case
             when s.changes ? 'attributes'
               then (s.changes -> 'attributes') || private.place_service_attributes(p.attributes)
             else p.attributes
           end
     where p.id = s.place_id;
  end if;
  update public.place_suggestions
     set status = 'accepted', decided_at = now(), decision_note = p_note, updated_at = now()
   where id = p_id;
end;
$$;

create function private.reject_place_suggestion(p_id uuid, p_note text default null) returns void
language sql
security definer
set search_path = ''
as $$
  update public.place_suggestions
     set status = 'rejected', decided_at = now(), decision_note = p_note, updated_at = now()
   where id = p_id and status = 'open';
$$;
