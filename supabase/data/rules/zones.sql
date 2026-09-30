set search_path = extensions, public;
drop table if exists osm_src.zones;
create table osm_src.zones (id text primary key, geom geometry);

create temp table ile as
  select g from (select (st_dump(st_linemerge(geom))).geom g from osm_src.raw where key = 'ile') d
   order by st_length(g) desc limit 1;
create temp table ile_parts as select (st_dump(st_linemerge(geom))).geom g from osm_src.raw where key = 'ile';
create temp table res as select st_union(geom) g from osm_src.raw where key = 'kapshagay';
create temp table kz as select geom g from osm_src.raw where key = 'kz';
create temp table marks as
select
  st_linelocatepoint(ile.g, st_setsrid(st_makepoint(75.4514, 45.0415), 4326)) as f_aral,
  (select min(st_linelocatepoint(ile.g, p.geom)) from st_dumppoints(st_intersection(ile.g, res.g)) p) as f_dam,
  (select max(st_linelocatepoint(ile.g, p.geom)) from st_dumppoints(st_intersection(ile.g, res.g)) p) as f_res_up,
  st_linelocatepoint(ile.g, st_setsrid(st_makepoint(79.427, 43.931), 4326)) as f_sharyn,
  (select min(st_linelocatepoint(ile.g, p.geom)) from st_dumppoints(st_intersection(ile.g, st_boundary(kz.g))) p
    where st_linelocatepoint(ile.g, p.geom) > st_linelocatepoint(ile.g, st_setsrid(st_makepoint(79.427, 43.931), 4326))) as f_border
from ile, res, kz;

-- Буфер линии в метрах (через географию).
create function pg_temp.corridor(line geometry, meters double precision) returns geometry language sql as $$
  select st_buffer(line::geography, meters, 'quad_segs=4')::geometry
$$;

-- 1. Капшагайское водохранилище.
insert into osm_src.zones select 'kapshagay', g from res;

-- 2. Иле от плотины Капшагайской ГЭС до Аралтобе (6-й рыбпункт): коридор 1 км.
insert into osm_src.zones
select 'ile_dam_araltobe', pg_temp.corridor(st_linesubstring(ile.g, m.f_aral, m.f_dam), 1000) from ile, marks m;

-- 3. Дельта Иле: русло ниже Аралтобе и рукава дельты (части ниже 45.0° с. ш. и западнее 75.5° в. д.), коридор 2 км.
insert into osm_src.zones
select 'ile_delta', st_union(pg_temp.corridor(g, 2000))
  from (
    select st_linesubstring(ile.g, 0, m.f_aral) g from ile, marks m
    union all
    select p.g from ile_parts p where st_xmax(p.g) < 75.6 and st_ymin(p.g) > 44.95 and st_length(p.g::geography) > 1000
  ) s;

-- 4. Зона покоя: Иле от водохранилища до устья Шарына (участок в самом водохранилище — только в тексте).
insert into osm_src.zones
select 'ile_backwater', st_difference(pg_temp.corridor(st_linesubstring(ile.g, m.f_res_up, m.f_sharyn), 1000), res.g)
  from ile, marks m, res;

-- 5. Иле от устья Шарына до границы с КНР.
insert into osm_src.zones
select 'ile_sharyn_china', pg_temp.corridor(st_linesubstring(ile.g, m.f_sharyn, m.f_border), 1000) from ile, marks m;

-- 6–7. Балхаш: западная и восточная части (раздел у пролива Узынарал, ≈75.46° в. д.).
insert into osm_src.zones
select 'balkhash_west', st_intersection(g, st_makeenvelope(70, 40, 75.46, 50, 4326)) from (select st_union(geom) g from osm_src.raw where key = 'balkhash') b;
insert into osm_src.zones
select 'balkhash_east', st_difference(g, st_makeenvelope(70, 40, 75.46, 50, 4326)) from (select st_union(geom) g from osm_src.raw where key = 'balkhash') b;

-- 8. Реки Каратал, Аксу, Лепсы, Аягоз: коридор 1 км + круг 5 км у устья (конец реки ближе к Балхашу).
insert into osm_src.zones
select 'balkhash_rivers', st_union(g)
  from (
    select pg_temp.corridor(r.geom, 1000) g from osm_src.raw r where r.key in ('karatal', 'aksu', 'lepsy', 'ayaguz')
    union all
    select st_buffer(mouth::geography, 5000, 'quad_segs=8')::geometry
      from (
        select distinct on (r.key) r.key, p.geom as mouth
          from osm_src.raw r
          cross join lateral st_dumppoints(r.geom) p
          cross join (select st_union(geom) g from osm_src.raw where key = 'balkhash') b
         where r.key in ('karatal', 'aksu', 'lepsy', 'ayaguz')
         order by r.key, st_distance(p.geom, b.g)
      ) m
  ) s;

-- 9. Алаколь, Сасыкколь, Кошкарколь.
insert into osm_src.zones
select 'alakol_lakes', st_union(geom) from osm_src.raw where key in ('alakol', 'sasykkol', 'koshkarkol');

-- 10. Жаланашколь.
insert into osm_src.zones select 'zhalanashkol', geom from osm_src.raw where key = 'zhalanashkol';

-- Острова внутри озёр для правил не важны: оставляем только внешние контуры.
update osm_src.zones z
   set geom = (select st_collect(st_makepolygon(st_exteriorring(d.geom))) from st_dump(z.geom) d)
 where id in ('balkhash_west', 'balkhash_east', 'alakol_lakes', 'kapshagay');

-- Упрощение и сетка ~1 м; только полигоны.
update osm_src.zones
   set geom = st_multi(st_collectionextract(st_makevalid(
                st_snaptogrid(st_simplifypreservetopology(geom, case when id in ('balkhash_west','balkhash_east') then 0.005 when id in ('alakol_lakes','balkhash_rivers') then 0.0015 when id = 'zhalanashkol' then 0.0005 else 0.001 end), 0.00001)), 3));

select id, st_npoints(geom) pts, st_numgeometries(geom) parts, round(st_area(geom::geography)/1e6) km2, st_isvalid(geom) valid,
       length(st_astext(geom)) wkt_chars
  from osm_src.zones order by id;
