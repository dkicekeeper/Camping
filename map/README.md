# Своя карта (M5d)

Подложка карты — векторные тайлы региона из OpenStreetMap в своём бакете Cloudflare R2. С ними в
приложении можно скачать район заранее и пользоваться картой без связи (условия OpenFreeMap
массовую загрузку с их сервера не разрешают).

| Что | Где в бакете | Откуда |
|-----|--------------|--------|
| Тайлы `{z}/{x}/{y}.pbf`, масштабы 0–14 | `tiles/` | Planetiler (схема OpenMapTiles) из выгрузок Geofabrik: Казахстан + Кыргызстан, обрезка по `bounds` из `config.json` (Алматинская область, Жетісу, Алматы с запасом) |
| Стили `liberty.ru.json`, `liberty.kk.json`, `liberty.en.json` | `styles/` | `build_style.py` из `style/liberty.json`: подписи на языке приложения |
| Значки | `sprites/v1/` | `style/sprites/` |
| Шрифты Noto Sans | `fonts/` | [maplibre/demotiles](https://github.com/maplibre/demotiles) |

Публичный адрес бакета — `public_base` в `config.json` (Public Development URL, `*.r2.dev`); когда
появится домен, будет `tiles.dalada.app`, а приложение возьмёт стиль с нового адреса.

## Как обновить

Всё делает workflow **Map tiles** (`.github/workflows/tiles.yml`):

- стили, шрифты и значки — сами при изменениях в `map/` в `main`;
- тайлы — раз в месяц (3-го числа) и вручную: Actions → Map tiles → Run workflow (галочка
  «Пересобрать тайлы»). Сборка и загрузка — 15–40 минут, ~185 тыс. тайлов.

Секреты репозитория: `R2_ACCESS_KEY_ID` и `R2_SECRET_ACCESS_KEY` (токен R2 с правом Object Read &
Write на бакет); Account ID — не секрет, он в `config.json`. Имя бакета — переменная `R2_BUCKET`, по
умолчанию `dalada-tiles`. Шаг «R2 access» проверяет формат ключей и адрес аккаунта, не показывая их.

Проверить стиль локально: `python3 map/build_style.py /tmp/map` — файлы появятся в `/tmp/map`.

## Лицензии

- Данные: © участники OpenStreetMap, [ODbL](https://www.openstreetmap.org/copyright); схема тайлов
  © OpenMapTiles (BSD-3 / CC BY 4.0). Подпись об авторах — в стиле, приложение показывает её в «ⓘ».
- Стиль Liberty и значки — из [openfreemap-styles](https://github.com/hyperknot/openfreemap-styles)
  (MIT; основа — OSM Liberty и OSM Bright, дизайн CC BY 4.0), версия от 15.05.2026. Изменения —
  источники, подписи по языку, без слоя рельефа Natural Earth.
- Шрифты Noto Sans — SIL Open Font License.
