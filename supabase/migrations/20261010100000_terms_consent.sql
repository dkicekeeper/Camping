-- Согласие с условиями и политикой конфиденциальности (M6c).
--
-- При первом входе (и после существенных изменений документов) приложение просит принять условия
-- использования, правила сообщества и политику конфиденциальности, в том числе хранение данных за
-- пределами Казахстана. Какую версию документов человек принял и когда — в профиле; записывает
-- только accept_terms (время ставит сервер).

alter table public.profiles
  add column terms_version integer check (terms_version > 0),
  add column terms_accepted_at timestamptz;

create function public.accept_terms(p_version integer) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'auth required' using errcode = '28000';
  end if;
  if p_version is null or p_version < 1 then
    raise exception 'invalid terms version' using errcode = '22023';
  end if;
  update public.profiles
     set terms_version = greatest(coalesce(terms_version, 0), p_version),
         terms_accepted_at = now()
   where id = me;
end;
$$;

revoke execute on function public.accept_terms(integer) from public;
grant execute on function public.accept_terms(integer) to authenticated;
