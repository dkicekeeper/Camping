#!/usr/bin/env python3
"""Сколько весят тайлы каждого района «Карт без сети» — по готовым папкам тайлов.

    python3 map/region_sizes.py DIR [DIR…]

DIR — папка {z}/{x}/{y}.* (например, public/relief и public/contours). Районы и масштабы берутся
из приложения (MapRegions.swift), чтобы не держать второй список. Печатает байты по районам —
их переносим в MapRegions.swift (`reliefBytes`).
"""

import math
import re
import sys
from pathlib import Path

REGIONS = Path(__file__).resolve().parent.parent / "ios/Packages/DaladaKit/Sources/DaladaCore/MapRegions.swift"
PATTERN = re.compile(
    r'MapRegion\(id: "(?P<id>\w+)", bounds: GeoBounds\(south: (?P<south>[\d.]+), west: (?P<west>[\d.]+), '
    r'north: (?P<north>[\d.]+), east: (?P<east>[\d.]+)\), maxZoom: (?P<max>\d+)'
)
MIN_ZOOM = int(re.search(r"static let minZoom = (\d+)", REGIONS.read_text()).group(1))


def tile(lon: float, lat: float, zoom: int) -> tuple[int, int]:
    n = 1 << zoom
    x = int((lon + 180) / 360 * n)
    y = int((1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n)
    return min(x, n - 1), min(y, n - 1)


def region_bytes(folder: Path, region: dict) -> tuple[int, int]:
    count, size = 0, 0
    for zoom in range(MIN_ZOOM, int(region["max"]) + 1):
        x0, y0 = tile(float(region["west"]), float(region["north"]), zoom)
        x1, y1 = tile(float(region["east"]), float(region["south"]), zoom)
        for x in range(x0, x1 + 1):
            column = folder / str(zoom) / str(x)
            if not column.is_dir():
                continue
            for path in column.iterdir():
                if y0 <= int(path.stem) <= y1:
                    count += 1
                    size += path.stat().st_size
    return count, size


def main(folders: list[Path]) -> None:
    regions = [match.groupdict() for match in PATTERN.finditer(REGIONS.read_text())]
    if not regions:
        sys.exit(f"Не нашёл районы в {REGIONS}")
    print("| Район | " + " | ".join(folder.name for folder in folders) + " | Всего, байт |")
    print("|---" * (len(folders) + 2) + "|")
    for region in regions:
        cells, total = [], 0
        for folder in folders:
            count, size = region_bytes(folder, region)
            cells.append(f"{count} тайлов, {size / 1024 / 1024:.1f} МБ")
            total += size
        print(f"| {region['id']} | " + " | ".join(cells) + f" | {total} |")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main([Path(arg) for arg in sys.argv[1:]])
