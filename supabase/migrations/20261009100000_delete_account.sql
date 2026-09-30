-- Удаление аккаунта из приложения (M6b, требование App Store).
--
-- Приложение сначала удаляет свои фото из бакета `media` (через Storage API: удалять строки
-- storage.objects напрямую Supabase не даёт), затем вызывает delete_my_account. Удаляется
-- пользователь в Auth, а с ним каскадом — профиль и всё своё: места, чекины, уловы, поездки,
-- отзывы, обсуждения и ответы, реакции, друзья, блокировки, жалобы, экипировка, чеклисты.
-- Жалобы других людей на этого человека остаются (без ссылки на автора).
--
-- Сразу и без восстановления. Мягкое удаление на 30 дней и обезличивание публичного вклада —
-- после беты (docs/03-architecture/02-backend.md).

create function public.delete_my_account() returns void
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
  delete from auth.users where id = me;
end;
$$;

revoke execute on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;
