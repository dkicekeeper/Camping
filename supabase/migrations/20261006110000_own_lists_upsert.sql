-- Отправка своих списков из приложения — upsert PostgREST (`on_conflict=id`). В `DO UPDATE SET`
-- он пишет все присланные колонки, в том числе первичный ключ, поэтому нужно право на `id`.
-- Сменить id строки при этом нельзя: триггер оставляет прежний.
--
-- Лимит на число записей проверяется при вставке, а upsert сначала пробует вставку и для уже
-- существующей строки: такая правка — изменение, лимит к ней не относится.

grant update (id) on table public.gear_items, public.checklists to authenticated;

create or replace function private.own_list_before_write() returns trigger
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
        if existing >= private.gear_items_limit()
           and not exists (select 1 from public.gear_items where id = new.id) then
          raise exception 'too many gear items' using errcode = 'DL004';
        end if;
      else
        select count(*) into existing from public.checklists
         where owner_id = new.owner_id and deleted_at is null;
        if existing >= private.checklists_limit()
           and not exists (select 1 from public.checklists where id = new.id) then
          raise exception 'too many checklists' using errcode = 'DL004';
        end if;
      end if;
    end if;
  else
    new.id := old.id;
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
