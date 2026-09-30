-- Модерация (M6a): жалобы на контент и людей, фильтр грубых слов.
--
-- Жалоба — одна от человека на объект (повторная обновляет причину); принимается только на то, что
-- жалующийся видит, и не на своё; не больше 20 в сутки. Жалобы разбирает редакция в Supabase Studio:
-- очередь — private.moderation_queue; скрыть контент — пометить deleted_at у объекта, решение —
-- status у жалоб.
--
-- Фильтр: грубые слова (шаблоны в private.banned_patterns, меняются в Studio) не пропускаются в
-- то, что видят другие: имя и username, названия и описания мест, заметки чекинов, поездки,
-- отзывы, обсуждения и ответы. Личное (видимость «только я») не проверяется.
--
-- Коды ошибок для приложения:
--   DL003 — слишком часто (лимит жалоб);
--   DL005 — в тексте грубые слова.

-- Фильтр грубых слов ------------------------------------------------------------------------------

-- Регулярные выражения PostgreSQL; текст перед проверкой переводится в нижний регистр, а латинские
-- буквы, похожие на кириллицу, проверяются и как кириллица («xуй» → «хуй»). \m — начало слова.
create table private.banned_patterns (
  id       bigint generated always as identity primary key,
  pattern  text not null unique,
  lang     text not null check (lang in ('ru', 'kk', 'en')),
  note     text
);

insert into private.banned_patterns (pattern, lang, note) values
  ('\m(на|за|вы|по|у|от|отъ|до|раз|разъ|рас|об|объ|под|подъ|про|съ|вз|въ|при|пере)?[её]б(а|у|л|н|ы|и|е|ё|о|т|ш|щ)', 'ru', 'корень «еб»'),
  ('\mдолбо[её]б', 'ru', null),
  ('\m(на|ни|по|от|до|рас|об|под|про|с|о)?ху[йеяиюё]', 'ru', 'корень «хуй»; не «художник»'),
  ('пизд', 'ru', null),
  ('\mбля(д|т|\M)', 'ru', 'не «бляха», не «рубля»'),
  ('\mсук(а|и|у|ой|ам|ами|ах)\M', 'ru', 'не фамилия «Сукин»'),
  ('\mмуда(к|ч|ц|ил)', 'ru', null),
  ('\mпид(о|а)р', 'ru', null),
  ('\mгандон', 'ru', null),
  ('\mшлюх', 'ru', null),
  ('\mзалуп', 'ru', null),
  ('\mсіг(ей|ем|ер|іп|у\M|ті|сін)', 'kk', null),
  ('\mқотақ', 'kk', null),
  ('\mfuck', 'en', null),
  ('\mmotherfuck', 'en', null),
  ('\mshit(\M|s\M|ty|head)', 'en', 'не «shiitake»'),
  ('\mcunt', 'en', null),
  ('\mnigg(er|a)', 'en', null),
  ('\mfaggot', 'en', null),
  ('\mbitch', 'en', null),
  ('\masshole', 'en', null),
  ('\mdickhead', 'en', null);

alter table private.banned_patterns enable row level security;

-- Есть ли в тексте грубые слова.
create function private.has_banned_words(p_text text) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_text is not null and exists (
    select 1
      from private.banned_patterns b
     where lower(p_text) ~ b.pattern
        or translate(lower(p_text), 'aeopcxykmtbh', 'аеорсхукмтвн') ~ b.pattern
  );
$$;

-- Триггер: проверяет перечисленные в аргументах колонки при вставке и когда они меняются (или
-- когда личное становится видно другим). Строки с видимостью private не проверяются.
create function private.word_filter() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  n jsonb := to_jsonb(new);
  o jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) end;
  widened boolean := false;
  col text;
begin
  if n ? 'visibility' then
    if n ->> 'visibility' = 'private' then
      return new;
    end if;
    widened := o is not null and o ->> 'visibility' = 'private';
  end if;
  foreach col in array tg_argv loop
    if (o is null or widened or (n ->> col) is distinct from (o ->> col))
       and private.has_banned_words(n ->> col) then
      raise exception 'text contains banned words' using errcode = 'DL005', detail = col;
    end if;
  end loop;
  return new;
end;
$$;

-- Профиль — только при правке: при регистрации имя приходит от Apple или Google, и вход не должен
-- ломаться из-за фамилии, похожей на грубое слово.
create trigger profiles_word_filter before update on public.profiles
  for each row execute function private.word_filter('username', 'display_name');
create trigger places_word_filter before insert or update on public.places
  for each row execute function private.word_filter('name', 'description');
create trigger checkins_word_filter before insert or update on public.checkins
  for each row execute function private.word_filter('note');
create trigger trips_word_filter before insert or update on public.trips
  for each row execute function private.word_filter('title', 'note');
create trigger reviews_word_filter before insert or update on public.reviews
  for each row execute function private.word_filter('body');
create trigger threads_word_filter before insert or update on public.threads
  for each row execute function private.word_filter('title', 'body');
create trigger thread_posts_word_filter before insert or update on public.thread_posts
  for each row execute function private.word_filter('body');

-- Жалобы ------------------------------------------------------------------------------------------

create type public.report_target as enum ('place', 'checkin', 'trip', 'review', 'thread', 'post', 'user');

-- spam — реклама и спам; abuse — оскорбления; nsfw — непристойное; poaching — браконьерство;
-- private_place — раскрыто чужое место; false_info — неправда; other — другое.
create type public.report_reason as enum (
  'spam', 'abuse', 'nsfw', 'poaching', 'private_place', 'false_info', 'other'
);

create type public.report_status as enum ('open', 'resolved', 'dismissed');

create table public.reports (
  id               uuid primary key default gen_random_uuid(),
  reporter_id      uuid not null references public.profiles (id) on delete cascade,
  target_kind      public.report_target not null,
  target_id        uuid not null,
  -- Автор контента на момент жалобы (для «на кого жалуются чаще»).
  target_owner_id  uuid references public.profiles (id) on delete set null,
  reason           public.report_reason not null,
  note             text check (char_length(note) <= 1000),
  status           public.report_status not null default 'open',
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  resolved_at      timestamptz,
  resolution_note  text,
  unique (reporter_id, target_kind, target_id)
);

create index reports_open_idx on public.reports (target_kind, target_id) where status = 'open';
create index reports_reporter_idx on public.reports (reporter_id, created_at);

-- Только через report_content; читает редакция.
alter table public.reports enable row level security;
revoke all on table public.reports from anon, authenticated;

-- Пожаловаться на то, что видишь (не на своё). Повторная жалоба на тот же объект обновляет причину.
create function public.report_content(
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

revoke execute on function public.report_content(public.report_target, uuid, public.report_reason, text) from public;
grant execute on function public.report_content(public.report_target, uuid, public.report_reason, text) to authenticated;

-- Очередь для редакции (Supabase Studio): открытые жалобы по объектам, сначала — с большим числом
-- жалобщиков.
create view private.moderation_queue as
select r.target_kind,
       r.target_id,
       r.target_owner_id,
       count(*) as reports,
       array_agg(distinct r.reason) as reasons,
       array_remove(array_agg(r.note order by r.created_at), null) as notes,
       min(r.created_at) as first_reported_at,
       max(r.updated_at) as last_reported_at
  from public.reports r
 where r.status = 'open'
 group by r.target_kind, r.target_id, r.target_owner_id
 order by count(*) desc, max(r.updated_at) desc;
