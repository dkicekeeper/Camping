# Dalada — заметки для Claude

iOS-приложение для рыбалки и отдыха на природе в Алматинском регионе. Документы — в `docs/`
(начать с `README.md` и `docs/04-beta/README.md` — текущий план по вехам).

## Язык и стиль

- Документы, комментарии в коде и тексты интерфейса — на русском. Сообщения коммитов — на английском.
- Интерфейс на трёх языках: строки только через `Localizable.xcstrings` (RU / KK / EN), без
  захардкоженного текста. Казахский — кириллица.

## Структура

- `supabase/` — миграции (`migrations/`), тесты pgTAP (`tests/database/`), `config.toml`.
- `ios/` — `project.yml` (XcodeGen; `.xcodeproj` не хранится в git), таргет `Dalada/`,
  модули в `Packages/DaladaKit` (DaladaCore → DaladaUI / MapEngine / Backend → AppFeature).
- `docs/` — бриф, анализ рынка, план продукта, архитектура, путь к бете.

## База данных: правила

- **Приватность — главное.** Таблицы с координатами (`places`, `checkins`, дальше — поездки,
  уловы, медиа) напрямую отдают только свои строки. Чужие данные — только через RPC
  `SECURITY DEFINER` с `set search_path = ''`, которые вызывают `private.can_view` и огрубляют
  координаты. Фильтр по области карты для чужих приблизительных мест — по `approx_center`.
- Каждая новая таблица: `enable row level security`, `revoke all … from anon, authenticated`,
  затем явные права (для записи — только разрешённые колонки). Служебные поля выставляют триггеры.
- Внутри функций с пустым `search_path` — полные имена: `extensions.st_*`, `public.*`, `private.*`.
- Любая новая таблица или RPC с чужими данными → тесты в `supabase/tests/database/` (матрица
  «зритель × объект × видимость»).
- Миграции только добавляются; уже применённые не редактировать.

## Проверки

```bash
# В облачном контейнере Docker может быть не запущен: nohup dockerd >/tmp/dockerd.log 2>&1 &
supabase db start
supabase db reset                                   # миграции с нуля
supabase db lint --level warning --fail-on warning -s public,private
supabase test db                                    # pgTAP
```

iOS собирается только на Mac (Xcode 26, iOS 26): `cd ios && xcodegen generate`. На Linux можно
проверить синтаксис (`swiftc -parse`) и модули без UI (`DaladaCore`, `Backend`) отдельным пакетом.

## Секреты

`ios/Config/Secrets.xcconfig` (хост и publishable key Supabase) — не в git, пример —
`Secrets.example.xcconfig`. Service role key — никогда в приложении и в репозитории.
