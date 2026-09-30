-- Экипировка и чеклисты сборов (M5b).
--
-- Своё: экипировку и чеклисты видит и меняет только владелец. Приложение хранит их на телефоне
-- (работают без сети и без аккаунта) и синхронизирует с сервером: побеждает последняя правка.
--   updated_at — время правки на телефоне (присылает приложение; из будущего не принимается);
--   synced_at  — когда строку принял сервер: по нему приложение забирает правки с других устройств;
--   deleted_at — удаление (строка остаётся, чтобы об удалении узнали другие устройства).
-- Шаблоны чеклистов — справочник редакции на трёх языках, читают все (и гости).
--
-- Коды ошибок для приложения:
--   DL004 — слишком много (лимит на число предметов экипировки или чеклистов).

-- Категории экипировки и пунктов чеклиста.
create type public.gear_category as enum (
  'rods', 'reels', 'tackle', 'clothing', 'camp', 'kitchen', 'power', 'navigation',
  'first_aid', 'boat', 'documents', 'other'
);

-- В порядке / в ремонте / купить.
create type public.gear_status as enum ('ok', 'repair', 'buy');

-- list — свой чеклист (заготовка); packing — сборы на конкретную поездку (копия с отметками).
create type public.checklist_kind as enum ('list', 'packing');

-- Лимиты на человека (без удалённых).
create function private.gear_items_limit() returns integer
language sql immutable
set search_path = ''
as $$ select 1000 $$;

create function private.checklists_limit() returns integer
language sql immutable
set search_path = ''
as $$ select 200 $$;

-- Пункты чеклиста — массив до 300 объектов {id, title, category?, gear_id?, checked?}.
create function private.checklist_items_valid(p_items jsonb) returns boolean
language sql immutable
set search_path = ''
as $$
  select case
    when p_items is null or jsonb_typeof(p_items) <> 'array' then false
    when jsonb_array_length(p_items) > 300 then false
    else not exists (
      select 1
        from jsonb_array_elements(p_items) e
       where jsonb_typeof(e) <> 'object'
          or jsonb_typeof(e -> 'id') is distinct from 'string'
          or char_length(e ->> 'id') not between 1 and 40
          or jsonb_typeof(e -> 'title') is distinct from 'string'
          or char_length(btrim(e ->> 'title')) not between 1 and 200
          or coalesce(jsonb_typeof(e -> 'checked'), 'boolean') <> 'boolean'
          or coalesce(jsonb_typeof(e -> 'category'), 'null') not in ('string', 'null')
          or char_length(coalesce(e ->> 'category', '')) > 40
          or coalesce(jsonb_typeof(e -> 'gear_id'), 'null') not in ('string', 'null')
          or char_length(coalesce(e ->> 'gear_id', '')) > 40
    )
  end;
$$;

-- Общая часть триггеров своих списков: владелец, служебные даты, «последняя правка побеждает».
-- Возвращает null, если пришла правка старше сохранённой (строка не меняется).
create function private.own_list_before_write() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing integer;
begin
  -- Часы телефона могут спешить: правку «из будущего» считаем сделанной сейчас.
  new.updated_at := least(coalesce(new.updated_at, now()), now());

  if tg_op = 'INSERT' then
    if private.is_client_request() then
      new.owner_id := auth.uid();
    end if;
    if new.owner_id is null then
      raise exception 'auth required' using errcode = '28000';
    end if;
    new.created_at := now();

    if new.deleted_at is null then
      if tg_table_name = 'gear_items' then
        select count(*) into existing from public.gear_items
         where owner_id = new.owner_id and deleted_at is null;
        if existing >= private.gear_items_limit() then
          raise exception 'too many gear items' using errcode = 'DL004';
        end if;
      else
        select count(*) into existing from public.checklists
         where owner_id = new.owner_id and deleted_at is null;
        if existing >= private.checklists_limit() then
          raise exception 'too many checklists' using errcode = 'DL004';
        end if;
      end if;
    end if;
  else
    new.owner_id := old.owner_id;
    new.created_at := old.created_at;
    -- Правка, сделанная раньше сохранённой (пришла с другого устройства с опозданием), — не нужна.
    if new.updated_at < old.updated_at then
      return null;
    end if;
  end if;

  new.synced_at := now();
  return new;
end;
$$;

-- Экипировка -------------------------------------------------------------------------------------

create table public.gear_items (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null references public.profiles (id) on delete cascade,
  name          text not null check (char_length(btrim(name)) between 1 and 100),
  category      public.gear_category not null default 'other',
  brand         text check (char_length(brand) <= 100),
  weight_grams  integer check (weight_grams between 0 and 1000000),
  quantity      integer not null default 1 check (quantity between 1 and 999),
  status        public.gear_status not null default 'ok',
  note          text check (char_length(note) <= 1000),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  created_at    timestamptz not null default now(),
  synced_at     timestamptz not null default now()
);

create index gear_items_owner_sync_idx on public.gear_items (owner_id, synced_at);

create trigger gear_items_before_write before insert or update on public.gear_items
  for each row execute function private.own_list_before_write();

alter table public.gear_items enable row level security;

revoke all on table public.gear_items from anon, authenticated;
grant select on table public.gear_items to authenticated;
grant insert (id, name, category, brand, weight_grams, quantity, status, note, updated_at, deleted_at)
  on table public.gear_items to authenticated;
grant update (name, category, brand, weight_grams, quantity, status, note, updated_at, deleted_at)
  on table public.gear_items to authenticated;

create policy "gear_items: читать свои" on public.gear_items
  for select to authenticated using (owner_id = (select auth.uid()));

create policy "gear_items: создавать свои" on public.gear_items
  for insert to authenticated with check (owner_id = (select auth.uid()));

create policy "gear_items: менять свои" on public.gear_items
  for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

-- Чеклисты и сборы -------------------------------------------------------------------------------

create table public.checklists (
  id              uuid primary key default gen_random_uuid(),
  owner_id        uuid not null references public.profiles (id) on delete cascade,
  kind            public.checklist_kind not null default 'list',
  title           text not null check (char_length(btrim(title)) between 1 and 100),
  -- Шаблон, из которого сделан чеклист (без внешнего ключа: шаблон могут убрать).
  template_id     text check (char_length(template_id) <= 40),
  -- Сборы: день поездки и напоминание накануне в это время (минуты от полуночи; null — без него).
  trip_date       date,
  remind_minutes  integer check (remind_minutes between 0 and 1439),
  items           jsonb not null default '[]',
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  created_at      timestamptz not null default now(),
  synced_at       timestamptz not null default now()
);

create index checklists_owner_sync_idx on public.checklists (owner_id, synced_at);

-- Проверка пунктов — в триггере: функции схемы private клиенту не видны.
create function private.checklists_validate_items() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.checklist_items_valid(new.items) then
    raise exception 'invalid checklist items' using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger checklists_before_write before insert or update on public.checklists
  for each row execute function private.own_list_before_write();

-- Выполняется после checklists_before_write (триггеры идут по имени) и только если правка принята.
create trigger checklists_validate_items before insert or update on public.checklists
  for each row execute function private.checklists_validate_items();

alter table public.checklists enable row level security;

revoke all on table public.checklists from anon, authenticated;
grant select on table public.checklists to authenticated;
grant insert (id, kind, title, template_id, trip_date, remind_minutes, items, updated_at, deleted_at)
  on table public.checklists to authenticated;
grant update (kind, title, template_id, trip_date, remind_minutes, items, updated_at, deleted_at)
  on table public.checklists to authenticated;

create policy "checklists: читать свои" on public.checklists
  for select to authenticated using (owner_id = (select auth.uid()));

create policy "checklists: создавать свои" on public.checklists
  for insert to authenticated with check (owner_id = (select auth.uid()));

create policy "checklists: менять свои" on public.checklists
  for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

-- Шаблоны чеклистов (редакция) -------------------------------------------------------------------

create table public.checklist_templates (
  id          text primary key check (id ~ '^[a-z0-9_]{2,40}$'),
  sort_order  integer not null default 100,
  title_ru    text not null,
  title_kk    text not null,
  title_en    text not null,
  note_ru     text,
  note_kk     text,
  note_en     text,
  -- [{id, category, title_ru, title_kk, title_en}]; id одного предмета одинаков во всех шаблонах.
  items       jsonb not null check (jsonb_typeof(items) = 'array')
);

alter table public.checklist_templates enable row level security;

revoke all on table public.checklist_templates from anon, authenticated;
grant select on table public.checklist_templates to anon, authenticated;

create policy "checklist_templates: читать всем" on public.checklist_templates
  for select to anon, authenticated using (true);

-- Черновик на трёх языках: казахский и английский — на вычитку.
insert into public.checklist_templates
  (id, sort_order, title_ru, title_kk, title_en, note_ru, note_kk, note_en, items)
values
  ('fishing_day', 10,
   'Рыбалка на день', 'Бір күндік балық аулау', 'Day fishing',
   'На водоём и обратно в тот же день.',
   'Бір күнде су айдынына барып қайту.',
   'There and back on the same day.',
   '[
     {"id": "rods", "category": "rods", "title_ru": "Удилища", "title_kk": "Қармақсаптар", "title_en": "Fishing rods"},
     {"id": "reels", "category": "reels", "title_ru": "Катушки", "title_kk": "Катушкалар", "title_en": "Reels"},
     {"id": "line", "category": "tackle", "title_ru": "Леска и запасная шпуля", "title_kk": "Қармақ жібі және қосалқы шпуля", "title_en": "Line and a spare spool"},
     {"id": "terminal_tackle", "category": "tackle", "title_ru": "Крючки, грузила, поплавки", "title_kk": "Ілмектер, батырғыштар, қалтқылар", "title_en": "Hooks, sinkers, floats"},
     {"id": "lures", "category": "tackle", "title_ru": "Приманки", "title_kk": "Жасанды жемдер", "title_en": "Lures"},
     {"id": "bait", "category": "tackle", "title_ru": "Наживка и прикормка", "title_kk": "Жем және жемдеме", "title_en": "Bait and groundbait"},
     {"id": "landing_net", "category": "tackle", "title_ru": "Подсачек", "title_kk": "Балық сүзгіш тор (подсачек)", "title_en": "Landing net"},
     {"id": "keepnet", "category": "tackle", "title_ru": "Садок или кукан", "title_kk": "Садок немесе кукан", "title_en": "Keepnet or stringer"},
     {"id": "pliers", "category": "tackle", "title_ru": "Кусачки и экстрактор", "title_kk": "Тістеуік және ілмек суырғыш", "title_en": "Pliers and hook remover"},
     {"id": "tape_measure", "category": "tackle", "title_ru": "Рулетка — проверить промысловую меру", "title_kk": "Рулетка — кәсіптік өлшемді тексеру үшін", "title_en": "Tape measure for minimum sizes"},
     {"id": "clothes", "category": "clothing", "title_ru": "Одежда по погоде и дождевик", "title_kk": "Ауа райына сай киім және жаңбырлық", "title_en": "Weather-appropriate clothes and a rain jacket"},
     {"id": "hat_glasses", "category": "clothing", "title_ru": "Головной убор и солнцезащитные очки", "title_kk": "Бас киім және күннен қорғайтын көзілдірік", "title_en": "Hat and sunglasses"},
     {"id": "boots", "category": "clothing", "title_ru": "Сапоги", "title_kk": "Етік", "title_en": "Boots"},
     {"id": "chair", "category": "camp", "title_ru": "Стул или кресло", "title_kk": "Орындық", "title_en": "Folding chair"},
     {"id": "water", "category": "kitchen", "title_ru": "Питьевая вода", "title_kk": "Ауыз су", "title_en": "Drinking water"},
     {"id": "food", "category": "kitchen", "title_ru": "Еда и перекус", "title_kk": "Тамақ және жеңіл тағам", "title_en": "Food and snacks"},
     {"id": "thermos", "category": "kitchen", "title_ru": "Термос с горячим чаем", "title_kk": "Ыстық шай құйылған термос", "title_en": "Thermos with hot tea"},
     {"id": "sunscreen", "category": "first_aid", "title_ru": "Солнцезащитный крем и репеллент", "title_kk": "Күннен қорғайтын крем және репеллент", "title_en": "Sunscreen and insect repellent"},
     {"id": "first_aid_kit", "category": "first_aid", "title_ru": "Аптечка", "title_kk": "Дәрі қобдишасы", "title_en": "First aid kit"},
     {"id": "power_bank", "category": "power", "title_ru": "Заряженный телефон и пауэрбанк", "title_kk": "Зарядталған телефон және пауэрбанк", "title_en": "Charged phone and a power bank"},
     {"id": "trash_bags", "category": "other", "title_ru": "Мешки для мусора — увозим с собой", "title_kk": "Қоқыс қаптары — қоқысты өзімізбен алып кетеміз", "title_en": "Trash bags: take your trash home"},
     {"id": "id_card", "category": "documents", "title_ru": "Удостоверение личности", "title_kk": "Жеке куәлік", "title_en": "ID card"}
   ]'::jsonb),
  ('fishing_overnight', 20,
   'Рыбалка с ночёвкой', 'Түнеп балық аулау', 'Overnight fishing',
   'Всё для рыбалки плюс лагерь на ночь.',
   'Балық аулауға керектің бәрі және түнеуге лагерь.',
   'Everything for fishing plus a camp for the night.',
   '[
     {"id": "rods", "category": "rods", "title_ru": "Удилища", "title_kk": "Қармақсаптар", "title_en": "Fishing rods"},
     {"id": "reels", "category": "reels", "title_ru": "Катушки", "title_kk": "Катушкалар", "title_en": "Reels"},
     {"id": "line", "category": "tackle", "title_ru": "Леска и запасная шпуля", "title_kk": "Қармақ жібі және қосалқы шпуля", "title_en": "Line and a spare spool"},
     {"id": "terminal_tackle", "category": "tackle", "title_ru": "Крючки, грузила, поплавки", "title_kk": "Ілмектер, батырғыштар, қалтқылар", "title_en": "Hooks, sinkers, floats"},
     {"id": "lures", "category": "tackle", "title_ru": "Приманки", "title_kk": "Жасанды жемдер", "title_en": "Lures"},
     {"id": "bait", "category": "tackle", "title_ru": "Наживка и прикормка", "title_kk": "Жем және жемдеме", "title_en": "Bait and groundbait"},
     {"id": "feeders", "category": "tackle", "title_ru": "Кормушки", "title_kk": "Жем салғыштар (фидер)", "title_en": "Feeders"},
     {"id": "bite_alarms", "category": "tackle", "title_ru": "Сигнализаторы поклёвки", "title_kk": "Қабу дабылдары (сигнализатор)", "title_en": "Bite alarms"},
     {"id": "landing_net", "category": "tackle", "title_ru": "Подсачек", "title_kk": "Балық сүзгіш тор (подсачек)", "title_en": "Landing net"},
     {"id": "keepnet", "category": "tackle", "title_ru": "Садок или кукан", "title_kk": "Садок немесе кукан", "title_en": "Keepnet or stringer"},
     {"id": "pliers", "category": "tackle", "title_ru": "Кусачки и экстрактор", "title_kk": "Тістеуік және ілмек суырғыш", "title_en": "Pliers and hook remover"},
     {"id": "tape_measure", "category": "tackle", "title_ru": "Рулетка — проверить промысловую меру", "title_kk": "Рулетка — кәсіптік өлшемді тексеру үшін", "title_en": "Tape measure for minimum sizes"},
     {"id": "clothes", "category": "clothing", "title_ru": "Одежда по погоде и дождевик", "title_kk": "Ауа райына сай киім және жаңбырлық", "title_en": "Weather-appropriate clothes and a rain jacket"},
     {"id": "warm_clothes", "category": "clothing", "title_ru": "Тёплая одежда на ночь", "title_kk": "Түнге жылы киім", "title_en": "Warm clothes for the night"},
     {"id": "hat_glasses", "category": "clothing", "title_ru": "Головной убор и солнцезащитные очки", "title_kk": "Бас киім және күннен қорғайтын көзілдірік", "title_en": "Hat and sunglasses"},
     {"id": "boots", "category": "clothing", "title_ru": "Сапоги", "title_kk": "Етік", "title_en": "Boots"},
     {"id": "tent", "category": "camp", "title_ru": "Палатка", "title_kk": "Шатыр", "title_en": "Tent"},
     {"id": "sleeping_bag", "category": "camp", "title_ru": "Спальник", "title_kk": "Ұйықтау қабы", "title_en": "Sleeping bag"},
     {"id": "sleeping_pad", "category": "camp", "title_ru": "Коврик", "title_kk": "Төсеніш", "title_en": "Sleeping pad"},
     {"id": "chair", "category": "camp", "title_ru": "Стул или кресло", "title_kk": "Орындық", "title_en": "Folding chair"},
     {"id": "knife", "category": "camp", "title_ru": "Нож", "title_kk": "Пышақ", "title_en": "Knife"},
     {"id": "axe", "category": "camp", "title_ru": "Топор или пила", "title_kk": "Балта немесе ара", "title_en": "Axe or saw"},
     {"id": "toilet_paper", "category": "camp", "title_ru": "Туалетная бумага и влажные салфетки", "title_kk": "Дәретхана қағазы және дымқыл майлықтар", "title_en": "Toilet paper and wet wipes"},
     {"id": "water", "category": "kitchen", "title_ru": "Питьевая вода", "title_kk": "Ауыз су", "title_en": "Drinking water"},
     {"id": "food", "category": "kitchen", "title_ru": "Еда и перекус", "title_kk": "Тамақ және жеңіл тағам", "title_en": "Food and snacks"},
     {"id": "stove", "category": "kitchen", "title_ru": "Горелка и газ", "title_kk": "Газ жанарғысы және баллон", "title_en": "Stove and gas"},
     {"id": "cookware", "category": "kitchen", "title_ru": "Котелок и посуда", "title_kk": "Қазан және ыдыс-аяқ", "title_en": "Pot and dishes"},
     {"id": "lighter", "category": "kitchen", "title_ru": "Спички или зажигалка", "title_kk": "Сіріңке немесе шақпақ", "title_en": "Matches or a lighter"},
     {"id": "thermos", "category": "kitchen", "title_ru": "Термос с горячим чаем", "title_kk": "Ыстық шай құйылған термос", "title_en": "Thermos with hot tea"},
     {"id": "headlamp", "category": "power", "title_ru": "Налобный фонарь и фонарь для лагеря", "title_kk": "Маңдай шамы және лагерь шамы", "title_en": "Headlamp and camp lantern"},
     {"id": "batteries", "category": "power", "title_ru": "Запасные батарейки", "title_kk": "Қосалқы батареялар", "title_en": "Spare batteries"},
     {"id": "power_bank", "category": "power", "title_ru": "Заряженный телефон и пауэрбанк", "title_kk": "Зарядталған телефон және пауэрбанк", "title_en": "Charged phone and a power bank"},
     {"id": "tell_someone", "category": "navigation", "title_ru": "Сказать близким, куда едете и когда вернётесь", "title_kk": "Жақындарыңызға қайда баратыныңызды және қашан оралатыныңызды айту", "title_en": "Tell someone where you are going and when you will be back"},
     {"id": "sunscreen", "category": "first_aid", "title_ru": "Солнцезащитный крем и репеллент", "title_kk": "Күннен қорғайтын крем және репеллент", "title_en": "Sunscreen and insect repellent"},
     {"id": "first_aid_kit", "category": "first_aid", "title_ru": "Аптечка", "title_kk": "Дәрі қобдишасы", "title_en": "First aid kit"},
     {"id": "trash_bags", "category": "other", "title_ru": "Мешки для мусора — увозим с собой", "title_kk": "Қоқыс қаптары — қоқысты өзімізбен алып кетеміз", "title_en": "Trash bags: take your trash home"},
     {"id": "id_card", "category": "documents", "title_ru": "Удостоверение личности", "title_kk": "Жеке куәлік", "title_en": "ID card"}
   ]'::jsonb),
  ('winter_fishing', 30,
   'Зимняя рыбалка', 'Қысқы балық аулау', 'Ice fishing',
   'Лёд толщиной меньше 7 см опасен — проверяйте пешнёй каждые несколько шагов.',
   'Қалыңдығы 7 см-ден жұқа мұз қауіпті — әр бірнеше қадам сайын сүйменмен тексеріңіз.',
   'Ice thinner than 7 cm is dangerous: test it with an ice chisel every few steps.',
   '[
     {"id": "winter_rods", "category": "rods", "title_ru": "Зимние удочки", "title_kk": "Қысқы қармақтар", "title_en": "Ice fishing rods"},
     {"id": "jigs", "category": "tackle", "title_ru": "Мормышки и блёсны", "title_kk": "Мормышкалар мен блесналар", "title_en": "Jigs and spoons"},
     {"id": "terminal_tackle", "category": "tackle", "title_ru": "Крючки, грузила, поплавки", "title_kk": "Ілмектер, батырғыштар, қалтқылар", "title_en": "Hooks, sinkers, floats"},
     {"id": "bait", "category": "tackle", "title_ru": "Наживка и прикормка", "title_kk": "Жем және жемдеме", "title_en": "Bait and groundbait"},
     {"id": "ice_auger", "category": "tackle", "title_ru": "Ледобур", "title_kk": "Мұз бұрғысы", "title_en": "Ice auger"},
     {"id": "ice_chisel", "category": "tackle", "title_ru": "Пешня — проверять лёд", "title_kk": "Сүймен — мұзды тексеру үшін", "title_en": "Ice chisel to test the ice"},
     {"id": "ice_scoop", "category": "tackle", "title_ru": "Черпак для лунки", "title_kk": "Ойыққа арналған шөміш", "title_en": "Ice scoop"},
     {"id": "ice_box", "category": "tackle", "title_ru": "Ящик рыбака", "title_kk": "Балықшы жәшігі", "title_en": "Tackle box seat"},
     {"id": "ice_tent", "category": "camp", "title_ru": "Зимняя палатка", "title_kk": "Қысқы шатыр", "title_en": "Ice fishing shelter"},
     {"id": "thermal", "category": "clothing", "title_ru": "Термобельё и тёплая одежда", "title_kk": "Термоішкиім және жылы киім", "title_en": "Thermal underwear and warm clothes"},
     {"id": "winter_boots", "category": "clothing", "title_ru": "Зимние сапоги", "title_kk": "Қысқы етік", "title_en": "Winter boots"},
     {"id": "spare_socks", "category": "clothing", "title_ru": "Запасные носки и перчатки", "title_kk": "Қосалқы шұлық пен қолғап", "title_en": "Spare socks and gloves"},
     {"id": "ice_cleats", "category": "clothing", "title_ru": "Ледоходы", "title_kk": "Мұз шегелері", "title_en": "Ice cleats"},
     {"id": "hat_glasses", "category": "clothing", "title_ru": "Головной убор и солнцезащитные очки", "title_kk": "Бас киім және күннен қорғайтын көзілдірік", "title_en": "Hat and sunglasses"},
     {"id": "ice_picks", "category": "navigation", "title_ru": "Спасалки", "title_kk": "Мұздан шығуға арналған құтқарғыштар", "title_en": "Ice picks"},
     {"id": "rope", "category": "navigation", "title_ru": "Верёвка 15–20 м", "title_kk": "Арқан 15–20 м", "title_en": "Rope, 15–20 m"},
     {"id": "thermos", "category": "kitchen", "title_ru": "Термос с горячим чаем", "title_kk": "Ыстық шай құйылған термос", "title_en": "Thermos with hot tea"},
     {"id": "food", "category": "kitchen", "title_ru": "Еда и перекус", "title_kk": "Тамақ және жеңіл тағам", "title_en": "Food and snacks"},
     {"id": "hand_warmers", "category": "power", "title_ru": "Грелки для рук", "title_kk": "Қол жылытқыштар", "title_en": "Hand warmers"},
     {"id": "power_bank", "category": "power", "title_ru": "Заряженный телефон и пауэрбанк", "title_kk": "Зарядталған телефон және пауэрбанк", "title_en": "Charged phone and a power bank"},
     {"id": "tell_someone", "category": "navigation", "title_ru": "Сказать близким, куда едете и когда вернётесь", "title_kk": "Жақындарыңызға қайда баратыныңызды және қашан оралатыныңызды айту", "title_en": "Tell someone where you are going and when you will be back"},
     {"id": "first_aid_kit", "category": "first_aid", "title_ru": "Аптечка", "title_kk": "Дәрі қобдишасы", "title_en": "First aid kit"},
     {"id": "trash_bags", "category": "other", "title_ru": "Мешки для мусора — увозим с собой", "title_kk": "Қоқыс қаптары — қоқысты өзімізбен алып кетеміз", "title_en": "Trash bags: take your trash home"},
     {"id": "id_card", "category": "documents", "title_ru": "Удостоверение личности", "title_kk": "Жеке куәлік", "title_en": "ID card"}
   ]'::jsonb),
  ('paid_pond', 40,
   'Поездка на платник', 'Ақылы тоғанға сапар', 'Paid pond trip',
   'Заранее узнайте правила водоёма: снасти, сколько рыбы можно забрать.',
   'Су айдынының ережесін алдын ала біліңіз: қандай құрал болады, қанша балық алып кетуге болады.',
   'Check the pond rules in advance: allowed tackle and how many fish you may keep.',
   '[
     {"id": "rods", "category": "rods", "title_ru": "Удилища", "title_kk": "Қармақсаптар", "title_en": "Fishing rods"},
     {"id": "reels", "category": "reels", "title_ru": "Катушки", "title_kk": "Катушкалар", "title_en": "Reels"},
     {"id": "line", "category": "tackle", "title_ru": "Леска и запасная шпуля", "title_kk": "Қармақ жібі және қосалқы шпуля", "title_en": "Line and a spare spool"},
     {"id": "terminal_tackle", "category": "tackle", "title_ru": "Крючки, грузила, поплавки", "title_kk": "Ілмектер, батырғыштар, қалтқылар", "title_en": "Hooks, sinkers, floats"},
     {"id": "bait", "category": "tackle", "title_ru": "Наживка и прикормка", "title_kk": "Жем және жемдеме", "title_en": "Bait and groundbait"},
     {"id": "feeders", "category": "tackle", "title_ru": "Кормушки", "title_kk": "Жем салғыштар (фидер)", "title_en": "Feeders"},
     {"id": "landing_net", "category": "tackle", "title_ru": "Подсачек", "title_kk": "Балық сүзгіш тор (подсачек)", "title_en": "Landing net"},
     {"id": "keepnet", "category": "tackle", "title_ru": "Садок или кукан", "title_kk": "Садок немесе кукан", "title_en": "Keepnet or stringer"},
     {"id": "pliers", "category": "tackle", "title_ru": "Кусачки и экстрактор", "title_kk": "Тістеуік және ілмек суырғыш", "title_en": "Pliers and hook remover"},
     {"id": "tape_measure", "category": "tackle", "title_ru": "Рулетка — проверить промысловую меру", "title_kk": "Рулетка — кәсіптік өлшемді тексеру үшін", "title_en": "Tape measure for minimum sizes"},
     {"id": "chair", "category": "camp", "title_ru": "Стул или кресло", "title_kk": "Орындық", "title_en": "Folding chair"},
     {"id": "clothes", "category": "clothing", "title_ru": "Одежда по погоде и дождевик", "title_kk": "Ауа райына сай киім және жаңбырлық", "title_en": "Weather-appropriate clothes and a rain jacket"},
     {"id": "hat_glasses", "category": "clothing", "title_ru": "Головной убор и солнцезащитные очки", "title_kk": "Бас киім және күннен қорғайтын көзілдірік", "title_en": "Hat and sunglasses"},
     {"id": "water", "category": "kitchen", "title_ru": "Питьевая вода", "title_kk": "Ауыз су", "title_en": "Drinking water"},
     {"id": "food", "category": "kitchen", "title_ru": "Еда и перекус", "title_kk": "Тамақ және жеңіл тағам", "title_en": "Food and snacks"},
     {"id": "thermos", "category": "kitchen", "title_ru": "Термос с горячим чаем", "title_kk": "Ыстық шай құйылған термос", "title_en": "Thermos with hot tea"},
     {"id": "sunscreen", "category": "first_aid", "title_ru": "Солнцезащитный крем и репеллент", "title_kk": "Күннен қорғайтын крем және репеллент", "title_en": "Sunscreen and insect repellent"},
     {"id": "power_bank", "category": "power", "title_ru": "Заряженный телефон и пауэрбанк", "title_kk": "Зарядталған телефон және пауэрбанк", "title_en": "Charged phone and a power bank"},
     {"id": "cash", "category": "documents", "title_ru": "Наличные: нацпарк, платник, рынок", "title_kk": "Қолма-қол ақша: ұлттық парк, ақылы тоған, базар", "title_en": "Cash for the national park, paid pond, market"},
     {"id": "id_card", "category": "documents", "title_ru": "Удостоверение личности", "title_kk": "Жеке куәлік", "title_en": "ID card"}
   ]'::jsonb),
  ('first_aid', 50,
   'Аптечка', 'Дәрі қобдишасы', 'First aid kit',
   'Список-напоминание. Лекарства подбирайте с врачом и проверяйте сроки годности.',
   'Бұл еске салу тізімі. Дәрілерді дәрігермен ақылдасып таңдаңыз, жарамдылық мерзімін тексеріңіз.',
   'A reminder list. Choose medicines with your doctor and check expiry dates.',
   '[
     {"id": "bandages", "category": "first_aid", "title_ru": "Бинт и стерильные салфетки", "title_kk": "Бинт және стерильді майлықтар", "title_en": "Bandages and sterile gauze"},
     {"id": "plasters", "category": "first_aid", "title_ru": "Пластыри", "title_kk": "Пластырьлер", "title_en": "Adhesive plasters"},
     {"id": "antiseptic", "category": "first_aid", "title_ru": "Антисептик (хлоргексидин)", "title_kk": "Антисептик (хлоргексидин)", "title_en": "Antiseptic (chlorhexidine)"},
     {"id": "painkillers", "category": "first_aid", "title_ru": "Обезболивающее и жаропонижающее", "title_kk": "Ауырсынуды басатын және қызуды түсіретін дәрі", "title_en": "Pain and fever relief"},
     {"id": "antihistamine", "category": "first_aid", "title_ru": "От аллергии и укусов насекомых", "title_kk": "Аллергияға және жәндік шаққанға қарсы дәрі", "title_en": "Antihistamine for allergies and insect bites"},
     {"id": "stomach", "category": "first_aid", "title_ru": "От расстройства желудка", "title_kk": "Асқазан бұзылғанда ішетін дәрі", "title_en": "Upset stomach remedy"},
     {"id": "rehydration", "category": "first_aid", "title_ru": "Соли для регидратации", "title_kk": "Регидратацияға арналған тұздар", "title_en": "Oral rehydration salts"},
     {"id": "elastic_bandage", "category": "first_aid", "title_ru": "Эластичный бинт", "title_kk": "Серпімді бинт", "title_en": "Elastic bandage"},
     {"id": "tourniquet", "category": "first_aid", "title_ru": "Кровоостанавливающий жгут", "title_kk": "Қан тоқтатқыш бұрау (жгут)", "title_en": "Tourniquet"},
     {"id": "tweezers", "category": "first_aid", "title_ru": "Ножницы и пинцет (для клещей)", "title_kk": "Қайшы және пинцет (кене үшін)", "title_en": "Scissors and tweezers (for ticks)"},
     {"id": "burn_cream", "category": "first_aid", "title_ru": "Средство от ожогов", "title_kk": "Күйікке қарсы құрал", "title_en": "Burn cream"},
     {"id": "sunscreen", "category": "first_aid", "title_ru": "Солнцезащитный крем и репеллент", "title_kk": "Күннен қорғайтын крем және репеллент", "title_en": "Sunscreen and insect repellent"},
     {"id": "emergency_blanket", "category": "first_aid", "title_ru": "Спасательное термоодеяло", "title_kk": "Құтқару термокөрпесі", "title_en": "Emergency blanket"},
     {"id": "personal_meds", "category": "first_aid", "title_ru": "Личные лекарства", "title_kk": "Жеке дәрілер", "title_en": "Personal medications"}
   ]'::jsonb),
  ('documents_money', 60,
   'Документы и деньги', 'Құжаттар мен ақша', 'Documents and money',
   'В горах и у воды связь бывает не везде.',
   'Тауда және су жағасында байланыс бәр жерде бола бермейді.',
   'In the mountains and by the water there may be no signal.',
   '[
     {"id": "id_card", "category": "documents", "title_ru": "Удостоверение личности", "title_kk": "Жеке куәлік", "title_en": "ID card"},
     {"id": "driver_license", "category": "documents", "title_ru": "Водительское удостоверение и техпаспорт", "title_kk": "Жүргізуші куәлігі және техпаспорт", "title_en": "Driver''s license and vehicle registration"},
     {"id": "car_insurance", "category": "documents", "title_ru": "Страховка на машину", "title_kk": "Көлік сақтандыру полисі", "title_en": "Car insurance"},
     {"id": "cash", "category": "documents", "title_ru": "Наличные: нацпарк, платник, рынок", "title_kk": "Қолма-қол ақша: ұлттық парк, ақылы тоған, базар", "title_en": "Cash for the national park, paid pond, market"},
     {"id": "bank_card", "category": "documents", "title_ru": "Банковская карта", "title_kk": "Банк картасы", "title_en": "Bank card"},
     {"id": "park_ticket", "category": "documents", "title_ru": "Билет или квитанция нацпарка", "title_kk": "Ұлттық парк билеті немесе түбіртегі", "title_en": "National park ticket or receipt"},
     {"id": "border_permit", "category": "documents", "title_ru": "Пропуск в пограничную зону, если нужен", "title_kk": "Шекара аймағына рұқсат қағазы (қажет болса)", "title_en": "Border zone permit, if needed"},
     {"id": "power_bank", "category": "power", "title_ru": "Заряженный телефон и пауэрбанк", "title_kk": "Зарядталған телефон және пауэрбанк", "title_en": "Charged phone and a power bank"},
     {"id": "offline_map", "category": "navigation", "title_ru": "Скачанная офлайн-карта", "title_kk": "Жүктелген офлайн карта", "title_en": "Downloaded offline map"},
     {"id": "emergency_numbers", "category": "documents", "title_ru": "Номер экстренных служб — 112", "title_kk": "Төтенше қызметтер нөмірі — 112", "title_en": "Emergency number: 112"},
     {"id": "tell_someone", "category": "navigation", "title_ru": "Сказать близким, куда едете и когда вернётесь", "title_kk": "Жақындарыңызға қайда баратыныңызды және қашан оралатыныңызды айту", "title_en": "Tell someone where you are going and when you will be back"}
   ]'::jsonb);
