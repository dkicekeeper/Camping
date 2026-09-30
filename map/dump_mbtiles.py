#!/usr/bin/env python3
"""MBTiles → папка тайлов {z}/{x}/{y}.pbf для раздачи из бакета.

    python3 map/dump_mbtiles.py region.mbtiles OUT_DIR

Тайлы остаются сжатыми gzip, как их пишет Planetiler: при загрузке им ставится
Content-Encoding: gzip, и телефон распаковывает их сам. Номер строки в MBTiles — по схеме TMS
(снизу вверх), в адресе — XYZ (сверху вниз).
"""

import sqlite3
import sys
from pathlib import Path


def main(source: Path, out: Path) -> None:
    db = sqlite3.connect(source)
    count, size, plain = 0, 0, 0
    for z, x, tms_y, data in db.execute("select zoom_level, tile_column, tile_row, tile_data from tiles"):
        y = (1 << z) - 1 - tms_y
        path = out / str(z) / str(x) / f"{y}.pbf"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        count += 1
        size += len(data)
        plain += not data.startswith(b"\x1f\x8b")
    if plain:
        sys.exit(f"{plain} тайлов без gzip — запустите Planetiler с --tile_compression=gzip")
    print(f"{count} тайлов, {size / 1024 / 1024:.0f} МБ")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(Path(sys.argv[1]), Path(sys.argv[2]))
