#!/usr/bin/env bash
# Скачивает из OpenStreetMap геометрии водоёмов и рек для зон правил (Балхаш-Алакольский бассейн)
# и загружает их в схему osm_src локальной базы. Дальше — zones.sql и export_zones.py.
# Данные OSM © участники OpenStreetMap, лицензия ODbL.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .osm
UA="Dalada-dev/0.1 (+https://github.com/dkicekeeper/Dalada)"
DB=${DB:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}

# Nominatim: не чаще раза в секунду.
fetch() {
  curl -sS -m 120 -G -A "$UA" "https://nominatim.openstreetmap.org/lookup" \
    --data-urlencode "osm_ids=$1" --data-urlencode "format=json" \
    --data-urlencode "polygon_geojson=1" --data-urlencode "polygon_threshold=$2" -o ".osm/$3"
  sleep 1.2
}

fetch R146505 0.0003 kapshagay.json                               # Капшагайское водохранилище
fetch R19025268 0.0005 balkhash.json                              # озеро Балхаш
fetch R35889,R1660939,R7615782,R9374204 0.0003 alakol_lakes.json  # Алаколь, Сасыкколь, Кошкарколь, Жаланашколь
fetch R238679 0.0003 ile.json                                     # река Иле
fetch R238651 0.0003 charyn.json                                  # река Шарын
fetch R15779936,R19186384,R19430721 0.0003 rivers.json            # Лепсы, Аксу, Аягоз
fetch R214665 0.005 kz.json                                       # граница Казахстана
# Каратал в OSM — отдельными линиями (way).
KARATAL="W20278613,W20278701,W20278735,W22699430,W22699440,W22699443,W22699462,W22699531,W22699536,W189848110,W190466810,W190748418,W190748643,W192257783,W192259186,W371592230,W371592231,W1307811528,W1307811529"
fetch "$KARATAL" 0.0003 karatal.json

python3 - <<'PY'
import json
names = {
    "R146505": "kapshagay", "R19025268": "balkhash", "R35889": "alakol", "R1660939": "sasykkol",
    "R7615782": "koshkarkol", "R9374204": "zhalanashkol", "R238679": "ile", "R238651": "charyn",
    "R15779936": "lepsy", "R19186384": "aksu", "R19430721": "ayaguz", "R214665": "kz",
}
rows = []
for f in ["kapshagay", "balkhash", "alakol_lakes", "ile", "charyn", "rivers", "kz", "karatal"]:
    for r in json.load(open(f".osm/{f}.json")):
        osm_id = r["osm_type"][0].upper() + str(r["osm_id"])
        key = "karatal" if f == "karatal" else names[osm_id]
        rows.append((key, osm_id, json.dumps(r["geojson"]).replace("'", "''")))
with open(".osm/load.sql", "w") as out:
    out.write("drop schema if exists osm_src cascade; create schema osm_src;\n")
    out.write("create table osm_src.raw (key text, osm_id text, geom extensions.geometry);\n")
    for key, osm_id, geojson in rows:
        out.write(f"insert into osm_src.raw values ('{key}', '{osm_id}', "
                  f"extensions.st_setsrid(extensions.st_geomfromgeojson('{geojson}'), 4326));\n")
PY
psql "$DB" -q -f .osm/load.sql
psql "$DB" -q -f zones.sql
