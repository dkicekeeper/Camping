#!/usr/bin/env python3
"""Стили карты Dalada из Liberty (map/style/liberty.json) — по одному на язык подписей.

    python3 map/build_style.py OUT_DIR

Пишет OUT_DIR/styles/liberty.<язык>.json и OUT_DIR/sprites/v1/ofm*: тайлы, шрифты и значки — из
нашего бакета (map/config.json → public_base), подписи — на языке стиля (для казахского и русского
— name:kk / name:ru из OpenStreetMap, если есть, иначе местное название). Слой рельефа Natural
Earth с сервера OpenFreeMap заменён своим: отмывка по тайлам высот и горизонтали из Copernicus DEM
(map/relief.py).
"""

import json
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONFIG = json.loads((HERE / "config.json").read_text())
RELIEF = CONFIG["relief"]
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
RELIEF_ATTRIBUTION = (
    '<a href="https://dataspace.copernicus.eu/explore-data/data-collections/copernicus-contributing-missions/'
    'collections-description/COP-DEM" target="_blank">Copernicus DEM GLO-30</a>: '
    "&copy; DLR e.V. 2010-2014 and &copy; Airbus Defence and Space GmbH 2014-2018 "
    "provided under COPERNICUS by the European Union and ESA"
)
# Подпись высоты у горизонталей.
METERS = {"ru": " м", "kk": " м", "en": " m"}
RELIEF_COLOR = "#7d6a55"


def relief_layers(language: str) -> list[dict]:
    """Отмывка рельефа и горизонтали: 100 м — с 11-го масштаба, 20 м — с 13-го, подписи — на 100 м."""
    return [
        {
            "id": "hillshade",
            "type": "hillshade",
            "source": "relief",
            "paint": {
                "hillshade-exaggeration": ["interpolate", ["linear"], ["zoom"], 8, 0.45, 12, 0.35, 15, 0.25],
                "hillshade-shadow-color": "#473b2e",
                "hillshade-highlight-color": "#ffffff",
                "hillshade-accent-color": "#473b2e",
            },
        },
        {
            "id": "contour_minor",
            "type": "line",
            "source": "contours",
            "source-layer": "contour",
            "minzoom": 13,
            "filter": ["==", ["get", "idx"], 0],
            "paint": {
                "line-color": RELIEF_COLOR,
                "line-opacity": 0.35,
                "line-width": ["interpolate", ["linear"], ["zoom"], 13, 0.5, 16, 0.9],
            },
        },
        {
            "id": "contour_major",
            "type": "line",
            "source": "contours",
            "source-layer": "contour",
            "minzoom": 11,
            "filter": ["==", ["get", "idx"], 1],
            "paint": {
                "line-color": RELIEF_COLOR,
                "line-opacity": ["interpolate", ["linear"], ["zoom"], 11, 0.3, 13, 0.5],
                "line-width": ["interpolate", ["linear"], ["zoom"], 11, 0.6, 13, 1, 16, 1.5],
            },
        },
        {
            "id": "contour_label",
            "type": "symbol",
            "source": "contours",
            "source-layer": "contour",
            "minzoom": 13,
            "filter": ["==", ["get", "idx"], 1],
            "layout": {
                "symbol-placement": "line",
                "text-field": ["concat", ["to-string", ["get", "ele"]], METERS[language]],
                "text-font": ["Noto Sans Regular"],
                "text-size": 10,
                "symbol-spacing": 350,
                "text-max-angle": 30,
                "text-padding": 10,
            },
            "paint": {
                "text-color": RELIEF_COLOR,
                "text-halo-color": "rgba(255,255,255,0.8)",
                "text-halo-width": 1,
            },
        },
    ]


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
        },
        "relief": {
            "type": "raster-dem",
            "tiles": [f"{base}/relief/{{z}}/{{x}}/{{y}}.png"],
            "encoding": "terrarium",
            "tileSize": 256,
            "minzoom": RELIEF["terrain_zooms"][0],
            "maxzoom": RELIEF["terrain_zooms"][1],
            "bounds": CONFIG["bounds"],
            "attribution": RELIEF_ATTRIBUTION,
        },
        "contours": {
            "type": "vector",
            "tiles": [f"{base}/contours/{{z}}/{{x}}/{{y}}.pbf"],
            "minzoom": RELIEF["contour_zooms"][0],
            "maxzoom": RELIEF["contour_zooms"][1],
            "bounds": CONFIG["bounds"],
            "attribution": RELIEF_ATTRIBUTION,
        },
    }
    style["sprite"] = f"{base}/sprites/{SPRITES_VERSION}/ofm"
    style["glyphs"] = f"{base}/fonts/{{fontstack}}/{{range}}.pbf"
    layers = []
    for layer in style["layers"]:
        source = layer.get("source")
        if source is not None and source not in style["sources"]:
            continue  # рельеф Natural Earth
        if layer.get("source-layer") in ("waterway", "water") and not any(l["id"] == "hillshade" for l in layers):
            layers += relief_layers(language)  # над растительностью, под водой и дорогами
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
