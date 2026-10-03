-- M13: достижения (значки) за свои поездки, уловы, места и вклад в общую базу.
--
-- Условия считаются по своим данным владельца (`private.achievement_progress`). Полученный значок
-- сохраняется в `public.achievements` и не пропадает, если потом удалить поездку или улов. Значки
-- видны только владельцу: часть условий считается по приватным данным (ночёвки, секретные места).

create table public.achievements (
  owner_id    uuid not null references public.profiles (id) on delete cascade,
  achievement text not null check (achievement ~ '^[a-z0-9_]{1,40}$'),
  earned_at   timestamptz not null default now(),
  -- Когда человек увидел поздравление; пока `null` — значок «новый».
  seen_at     timestamptz,
  primary key (owner_id, achievement)
);

alter table public.achievements enable row level security;
revoke all on public.achievements from anon, authenticated;
grant select on public.achievements to authenticated;

create policy achievements_select_own on public.achievements
  for select to authenticated
  using (owner_id = (select auth.uid()));

-- Прогресс по каждому значку. Порядок `sort` — порядок показа.
-- Поездки — завершённые; ночёвки — смены дат по Алматы (не больше 14 за поездку, чтобы забытая
-- запись не давала значок); трофей — одна рыба от 3 кг; виды — без «другой рыбы»; места — разные
-- места с отчётами; первооткрыватель — своё публичное место, прошедшее проверку.
create function private.achievement_progress(p_user uuid)
returns table (achievement text, sort integer, progress integer, target integer)
language sql
stable
security definer
set search_path = ''
as $$
  with trips as (
    select t.started_at, t.ended_at, t.distance_m
      from public.trips t
     where t.owner_id = p_user and t.deleted_at is null and t.ended_at is not null
  ),
  catches as (
    select k.species_id, k.weight_g, k.count
      from public.catches k
     where k.owner_id = p_user and k.deleted_at is null
  ),
  checkins as (
    select c.place_id
      from public.checkins c
     where c.owner_id = p_user and c.deleted_at is null
  )
  select v.achievement, v.sort, v.progress, v.target
    from (values
      ('first_trip', 1,
       (select count(*) from trips)::integer, 1),
      ('distance_100', 2,
       (select coalesce(sum(distance_m), 0) / 1000 from trips)::integer, 100),
      ('nights_5', 3,
       (select coalesce(sum(least(
                 (t.ended_at at time zone 'Asia/Almaty')::date
                 - (t.started_at at time zone 'Asia/Almaty')::date, 14)), 0)
          from trips t)::integer, 5),
      ('first_catch', 4,
       (select count(*) from catches)::integer, 1),
      ('species_5', 5,
       (select count(distinct species_id) from catches
         where species_id is not null and species_id <> 'other')::integer, 5),
      ('trophy_3kg', 6,
       (select coalesce(max(weight_g), 0) from catches where count = 1)::integer, 3000),
      ('places_5', 7,
       (select count(distinct place_id) from checkins where place_id is not null)::integer, 5),
      ('first_public_place', 8,
       (select count(*) from public.places p
         where p.owner_id = p_user and p.deleted_at is null
           and p.visibility = 'public' and p.status = 'published')::integer, 1),
      ('reviews_5', 9,
       (select count(*) from public.reviews r
         where r.owner_id = p_user and r.deleted_at is null)::integer, 5),
      ('accepted_edit', 10,
       (select count(*) from public.place_suggestions s
         where s.author_id = p_user and s.status = 'accepted')::integer, 1)
    ) as v(achievement, sort, progress, target);
$$;

revoke execute on function private.achievement_progress(uuid) from public;

-- Мои значки: выдаёт заработанные с прошлого раза и возвращает все с прогрессом.
create function public.my_achievements()
returns table (achievement text, progress integer, target integer, earned_at timestamptz, is_new boolean)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  insert into public.achievements (owner_id, achievement)
  select me, p.achievement
    from private.achievement_progress(me) p
   where p.progress >= p.target
  on conflict do nothing;

  return query
  select p.achievement, p.progress, p.target, a.earned_at, (a.earned_at is not null and a.seen_at is null)
    from private.achievement_progress(me) p
    left join public.achievements a on a.owner_id = me and a.achievement = p.achievement
   order by p.sort;
end;
$$;

revoke execute on function public.my_achievements() from public;
grant execute on function public.my_achievements() to authenticated;

-- Поздравление показано: новые значки больше не «новые».
create function public.mark_achievements_seen()
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  update public.achievements
     set seen_at = now()
   where owner_id = auth.uid() and seen_at is null;
$$;

revoke execute on function public.mark_achievements_seen() from public;
grant execute on function public.mark_achievements_seen() to authenticated;
