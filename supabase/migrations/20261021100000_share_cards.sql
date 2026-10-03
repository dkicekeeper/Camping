-- Картинки для Stories и Telegram (M11): данные для карточки своей поездки и своего улова.
--
-- Картинка уходит куда угодно, поэтому в ней только то, что можно показать всем:
-- - трек поездки — как его видит гость (private.visible_track без зрителя): без начала и конца,
--   зон приватности и участков у мест, которые гостю не видны;
-- - у улова — название места, только если место публичное и опубликовано.
-- Делиться можно только своим.

create function public.trip_share_card(p_trip uuid)
returns table (
  activity public.trip_activity,
  title text,
  started_at timestamptz,
  ended_at timestamptz,
  moving_seconds integer,
  distance_m integer,
  elevation_gain_m integer,
  track jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select t.activity, t.title, t.started_at, t.ended_at, t.moving_seconds, t.distance_m, t.elevation_gain_m,
         extensions.st_asgeojson(
           extensions.st_simplify(extensions.st_force2d(private.visible_track(t, null)), 0.00005), 5
         )::jsonb
    from public.trips t
   where t.id = p_trip
     and t.owner_id = auth.uid()
     and t.deleted_at is null;
$$;

create function public.catch_share_card(p_catch uuid)
returns table (
  species_id text,
  weight_g integer,
  length_mm integer,
  count integer,
  released boolean,
  at timestamptz,
  photo_path text,
  place_name text
)
language sql
stable
security definer
set search_path = ''
as $$
  select k.species_id, k.weight_g, k.length_mm, k.count, k.released, k.at,
         (select m.storage_path
            from public.media m
           where m.catch_id = k.id and m.owner_id = k.owner_id and m.deleted_at is null
           order by m.created_at desc
           limit 1),
         case when p.deleted_at is null and p.visibility = 'public' and p.status = 'published'
              then p.name end
    from public.catches k
    left join public.places p on p.id = k.place_id
   where k.id = p_catch
     and k.owner_id = auth.uid()
     and k.deleted_at is null;
$$;

revoke execute on function public.trip_share_card(uuid), public.catch_share_card(uuid) from public;
grant execute on function public.trip_share_card(uuid), public.catch_share_card(uuid) to authenticated;
