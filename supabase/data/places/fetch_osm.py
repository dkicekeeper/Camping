#!/usr/bin/env python3
"""Кандидаты в места редакции из OpenStreetMap: Алматинская область, область Жетісу и Алматы.

    python3 supabase/data/places/fetch_osm.py

Пишет osm_candidates.csv: водоёмы, родники и горячие источники, водопады, места рыбалки, магазины
снастей, стоянки, базы отдыха и приюты — с предварительным решением в колонке `include`
(yes — берём, no — нет, ? — посмотреть). Решения и заметки, уже записанные в файле, сохраняются.
Взятое переносит в places.csv команда `places.py import osm_candidates.csv`.

Данные © участники OpenStreetMap, лицензия ODbL (https://www.openstreetmap.org/copyright).
"""

import csv
import hashlib
import json
import math
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE / "osm_candidates.csv"
UA = "Dalada-dev/0.1 (+https://github.com/dkicekeeper/Dalada)"
MIRRORS = [
    "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
    "https://overpass-api.de/api/interpreter",
]
# Ответы Overpass кэшируются (удалите папку, чтобы скачать заново).
CACHE = HERE / ".osm"
# Алматы, область Жетісу, Алматинская область (id отношений + 3600000000).
AREAS = "(area(id:3602465058);area(id:3614312169);area(id:3600215718);)->.r;"

FIELDS = ["include", "type", "name", "lat", "lon", "description", "source", "kind", "osm_name", "link", "note"]

# (метка, выборка Overpass, геометрия нужна — для водоёмов точка ставится внутри контура).
QUERIES = [
    ("shop", 'nwr["shop"~"^(fishing|hunting)$"]', False),
    ("fishing", 'nwr["leisure"="fishing"]', False),
    ("spring", 'nwr["natural"="spring"]["name"]', False),
    ("hot_spring", 'nwr["natural"="hot_spring"]', False),
    ("waterfall", 'nwr["waterway"="waterfall"]["name"]', False),
    ("waterfall", 'nwr["natural"="waterfall"]["name"]', False),
    ("water", 'way["natural"="water"]["name"]["water"~"^(lake|reservoir|oxbow|pond)$"]', True),
    ("water", 'rel["natural"="water"]["name"]["water"~"^(lake|reservoir|oxbow|pond)$"]', True),
    ("camp", 'node["tourism"="camp_site"]', False),
    ("camp", 'way["tourism"="camp_site"]', False),
    ("resort", 'nwr["leisure"="resort"]', False),
    ("hut", 'nwr["tourism"~"^(alpine_hut|wilderness_hut)$"]', False),
]

TECHNICAL = re.compile(
    r"отстойник|очистк|технич|золоотвал|күл үйінді|бассейн|плотина|^поле$|шұңқыр|накопител|"
    r"карантин|suv|gsm|tax free",
    re.I,
)
NUMBERED = re.compile(r"^(№\s*\d+|\d+\w?|к-\d+|озеро \d+|\d+-бис|\d+б)$", re.I)
NOT_CAMP = re.compile(r"зимовк|чабан|стойбищ|пионер|лагерь|ранч|ranch|клуб|трейл", re.I)
NOT_BASE = re.compile(r"санатор|spa|аква|aqua|бан[ия]|арена|arena|pool|городище|аким|перекрыл|пионер", re.I)
GENERIC_SPRING = re.compile(r"^(water|water source|родник|источник.*|бастау|исток)$", re.I)


def overpass(query: str) -> dict:
    CACHE.mkdir(exist_ok=True)
    cached = CACHE / (hashlib.sha256(query.encode()).hexdigest()[:16] + ".json")
    if cached.exists():
        return json.loads(cached.read_bytes())
    data = urllib.parse.urlencode({"data": query}).encode()
    last = None
    for attempt in range(10):
        url = MIRRORS[attempt % len(MIRRORS)]
        try:
            req = urllib.request.Request(url, data=data, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=120) as resp:
                body = resp.read()
            if body.lstrip().startswith(b"{") and b'"remark"' not in body[:2000]:
                cached.write_bytes(body)
                return json.loads(body)
            last = body[:200]
        except Exception as error:  # сеть, 429, 504 — пробуем ещё раз, с другого зеркала
            last = error
        time.sleep(min(5 * (attempt + 1), 30))
    sys.exit(f"Overpass не ответил: {last}")


def point_inside(element: dict) -> tuple[float, float] | None:
    """Точка внутри контура водоёма: середина самого широкого отрезка горизонтали внутри."""
    segments = []
    rings = []
    if element["type"] == "way":
        rings.append(element.get("geometry") or [])
    else:
        rings += [m.get("geometry") or [] for m in element.get("members", []) if m.get("type") == "way"]
    for ring in rings:
        for a, b in zip(ring, ring[1:]):
            segments.append((a["lon"], a["lat"], b["lon"], b["lat"]))
    if not segments:
        return None
    b = element["bounds"]
    best = None
    for share in (0.5, 0.35, 0.65, 0.2, 0.8):
        y = b["minlat"] + (b["maxlat"] - b["minlat"]) * share
        xs = sorted(
            x1 + (y - y1) * (x2 - x1) / (y2 - y1)
            for x1, y1, x2, y2 in segments
            if (y1 <= y < y2) or (y2 <= y < y1)
        )
        for left, right in zip(xs[0::2], xs[1::2]):
            if best is None or right - left > best[0]:
                best = (right - left, (left + right) / 2, y)
    return (best[2], best[1]) if best else None


def describe(label: str, tags: dict) -> str:
    lines = []
    # Описание из OSM — только на русском или казахском.
    text = " ".join((tags.get("description:ru") or tags.get("description") or "").split())
    cyrillic = len(re.findall(r"[а-яёәғқңөұүһі]", text, re.I))
    if cyrillic and cyrillic >= len(re.findall(r"[a-z]", text, re.I)):
        lines.append(text.rstrip(".") + ".")
    if label == "hot_spring" and "источник" not in " ".join(lines).lower():
        lines.append("Горячий источник.")
    spring = label in ("spring", "hot_spring")
    if tags.get("drinking_water") == "yes":
        lines.append("Вода питьевая (по данным OpenStreetMap)." if spring else "Есть питьевая вода (по данным OpenStreetMap).")
    elif tags.get("drinking_water") == "no":
        lines.append("Вода не питьевая (по данным OpenStreetMap)." if spring else "Питьевой воды нет (по данным OpenStreetMap).")
    street = tags.get("addr:street")
    if street:
        house = tags.get("addr:housenumber")
        city = tags.get("addr:city")
        lines.append("Адрес: " + ", ".join(x for x in (city, street + (f", {house}" if house else "")) if x) + ".")
    if tags.get("opening_hours"):
        lines.append(f"Часы работы: {tags['opening_hours']}.")
    phone = tags.get("phone") or tags.get("contact:phone")
    if phone:
        lines.append(f"Телефон: {phone}.")
    site = tags.get("website") or tags.get("contact:website") or tags.get("contact:instagram")
    if site:
        lines.append(f"Сайт: {site}")
    if tags.get("fee") == "yes":
        lines.append("Платно.")
    return " ".join(lines)[:2000]


def decide(label: str, name: str, tags: dict) -> tuple[str, str, str]:
    """Тип места, предварительное решение и причина."""
    place_type = {
        "shop": "tackle_shop", "fishing": "fishing_spot", "spring": "spring", "hot_spring": "spring",
        "waterfall": "landmark", "water": "water_body", "camp": "campsite", "resort": "base",
        "hut": "campsite",
    }[label]
    if label == "fishing" and (tags.get("fee") == "yes" or re.search(r"платн|форел|хозяйств|усадьб", name, re.I)):
        place_type = "paid_pond"
    if label == "resort" and re.search(r"форел", name, re.I):
        place_type = "paid_pond"
    if not name:
        return place_type, "no", "без названия"
    if TECHNICAL.search(name):
        return place_type, "no", "технический объект"
    if NUMBERED.match(name):
        return place_type, "no", "номер вместо названия"
    if label == "shop":
        return (place_type, "yes", "") if tags.get("shop") == "fishing" else (place_type, "?", "охотничий магазин")
    if label == "spring" and GENERIC_SPRING.match(name):
        return place_type, "?", "общее название"
    if label == "hot_spring" and NOT_BASE.search(name):
        return place_type, "no", "платный комплекс"
    if label == "camp":
        return (place_type, "no", "не стоянка") if NOT_CAMP.search(name) else (place_type, "?", "")
    if label == "resort":
        return (place_type, "no", "не база отдыха") if NOT_BASE.search(name) else (place_type, "?", "")
    if label == "hut":
        return place_type, "?", "приют"
    if label == "water" and tags.get("water") == "pond":
        return place_type, "?", "пруд"
    return place_type, "yes", ""


def main() -> None:
    previous = {}
    if OUT.exists():
        with OUT.open(encoding="utf-8") as f:
            previous = {row["source"]: row for row in csv.DictReader(f)}

    rows, seen = [], set()
    for label, selector, with_geometry in QUERIES:
        out = "out geom;" if with_geometry else "out center tags;"
        data = overpass(f"[out:json][timeout:55];{AREAS}({selector}(area.r););{out}")
        print(f"{label}: {len(data['elements'])}", file=sys.stderr)
        for element in data["elements"]:
            key = f"{element['type'][0]}{element['id']}"
            if key in seen:
                continue
            seen.add(key)
            tags = element.get("tags", {})
            if with_geometry:
                point = point_inside(element)
            elif "lat" in element:
                point = (element["lat"], element["lon"])
            else:
                point = (element["center"]["lat"], element["center"]["lon"])
            if point is None:
                continue
            name = " ".join((tags.get("name:ru") or tags.get("name") or "").split())[:80]
            place_type, include, note = decide(label, name, tags)
            source = f"osm:{key}"
            old = previous.get(source)
            if old:
                include, note = old["include"], old["note"]
            kind = next((f"{k}={tags[k]}" for k in ("shop", "leisure", "natural", "waterway", "tourism") if k in tags), "")
            rows.append({
                "include": include,
                "type": place_type,
                "name": name,
                "lat": f"{point[0]:.6f}",
                "lon": f"{point[1]:.6f}",
                "description": describe(label, tags),
                "source": source,
                "kind": kind,
                "osm_name": tags.get("name", ""),
                "link": f"https://www.openstreetmap.org/{element['type']}/{element['id']}",
                "note": note,
            })
        time.sleep(2)

    rows.sort(key=lambda r: ({"yes": 0, "?": 1, "no": 2}.get(r["include"], 1), r["type"], r["name"], r["source"]))
    with OUT.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    counts = {k: sum(1 for r in rows if r["include"] == k) for k in ("yes", "?", "no")}
    print(f"{OUT.name}: {len(rows)} кандидатов, {counts}", file=sys.stderr)


if __name__ == "__main__":
    main()
