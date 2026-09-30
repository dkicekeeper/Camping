#!/usr/bin/env python3
"""Стили карты Dalada из Liberty (map/style/liberty.json) — по одному на язык подписей.

    python3 map/build_style.py OUT_DIR

Пишет OUT_DIR/styles/liberty.<язык>.json и OUT_DIR/sprites/v1/ofm*: тайлы, шрифты и значки — из
нашего бакета (map/config.json → public_base), подписи — на языке стиля (для казахского и русского
— name:kk / name:ru из OpenStreetMap, если есть, иначе местное название). Слой рельефа Natural
Earth с сервера OpenFreeMap убран.
"""

import json
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONFIG = json.loads((HERE / "config.json").read_text())
SPRITES_VERSION = "v1"

LABELS = {
    "ru": ["coalesce", ["get", "name:ru"], ["get", "name"]],
    "kk": ["coalesce", ["get", "name:kk"], ["get", "name"]],
    "en": ["coalesce", ["get", "name:en"], ["get", "name_en"], ["get", "name:latin"], ["get", "name"]],
}
ATTRIBUTION = (
    '<a href="https://openmaptiles.org/" target="_blank">&copy; OpenMapTiles</a> '
    '<a href="https://www.openstreetmap.org/copyright" target="_blank">&copy; OpenStreetMap contributors</a>'
)


def uses_name(expression) -> bool:
    """Подпись из названия объекта (а не номер дороги или дома)."""
    return "name" in json.dumps(expression)


def build(language: str) -> dict:
    style = json.loads((HERE / "style" / "liberty.json").read_text())
    base = CONFIG["public_base"].rstrip("/")
    style["name"] = f"Dalada Liberty ({language})"
    style["sources"] = {
        "openmaptiles": {
            "type": "vector",
            "tiles": [f"{base}/tiles/{{z}}/{{x}}/{{y}}.pbf"],
            "minzoom": 0,
            "maxzoom": CONFIG["maxzoom"],
            "bounds": CONFIG["bounds"],
            "attribution": ATTRIBUTION,
        }
    }
    style["sprite"] = f"{base}/sprites/{SPRITES_VERSION}/ofm"
    style["glyphs"] = f"{base}/fonts/{{fontstack}}/{{range}}.pbf"
    layers = []
    for layer in style["layers"]:
        source = layer.get("source")
        if source is not None and source not in style["sources"]:
            continue  # рельеф Natural Earth
        layout = layer.get("layout", {})
        if "text-field" in layout and uses_name(layout["text-field"]):
            layout["text-field"] = LABELS[language]
        layers.append(layer)
    style["layers"] = layers
    return style


def main(out: Path) -> None:
    (out / "styles").mkdir(parents=True, exist_ok=True)
    for language in CONFIG["languages"]:
        path = out / "styles" / f"liberty.{language}.json"
        path.write_text(json.dumps(build(language), ensure_ascii=False, separators=(",", ":")))
        print(f"{path}: {path.stat().st_size // 1024} КБ")
    sprites = out / "sprites" / SPRITES_VERSION
    sprites.mkdir(parents=True, exist_ok=True)
    for file in (HERE / "style" / "sprites").iterdir():
        shutil.copy(file, sprites / file.name)
    print(f"{sprites}: {len(list(sprites.iterdir()))} файла")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(Path(sys.argv[1]))
