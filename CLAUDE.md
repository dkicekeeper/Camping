# Dalada — заметки для Claude

iOS-приложение для рыбалки и отдыха на природе в Алматинском регионе. Документы — в `docs/`
(начать с `README.md` и `docs/04-beta/README.md` — текущий план по вехам).

## Язык и стиль

- Документы, комментарии в коде и тексты интерфейса — на русском. Сообщения коммитов — на английском.
- Интерфейс на трёх языках: строки только через `Localizable.xcstrings` (RU / KK / EN), без
  захардкоженного текста. Казахский — кириллица.
- `.xcstrings` пишем в формате Xcode (ключи по алфавиту, разделитель `" : "`, отступ 2, без перевода
  строки в конце) — иначе Xcode переписывает файл при сборке и появляются лишние изменения.

## Структура

- `supabase/` — миграции (`migrations/`), тесты pgTAP (`tests/database/`), `config.toml`.
- `ios/` — `project.yml` (XcodeGen; `.xcodeproj` не хранится в git), таргеты `Dalada/` и
  `DaladaWidgets/` (Live Activity), модули в `Packages/DaladaKit` (DaladaCore → DaladaUI / MapEngine /
  Backend / Persistence → Sync / TripLiveActivity → AppFeature).
- `docs/` — бриф, анализ рынка, план продукта, архитектура, путь к бете.

## База данных: правила

- **Приватность — главное.** Таблицы с координатами (`places`, `checkins`, дальше — поездки,
  уловы, медиа) напрямую отдают только свои строки. Чужие данные — только через RPC
  `SECURITY DEFINER` с `set search_path = ''`, которые вызывают `private.can_view` и огрубляют
  координаты. Фильтр по области карты для чужих приблизительных мест — по `approx_center`.
- Каждая новая таблица: `enable row level security`, `revoke all … from anon, authenticated`,
  затем явные права (для записи — только разрешённые колонки). Служебные поля выставляют триггеры.
- Внутри функций с пустым `search_path` — полные имена: `extensions.st_*`, `public.*`, `private.*`.
- Файлы (фото) — в закрытом бакете `media`, путь `<owner_id>/<media_id>.jpg`. Своей видимости у фото
  нет: оно видно тем, кто видит чекин, место и улов. Политики `storage.objects` вызывают функции из
  схемы `rls` (схема `private` для клиента закрыта, а политики выполняются от его имени).
- Любая новая таблица или RPC с чужими данными → тесты в `supabase/tests/database/` (матрица
  «зритель × объект × видимость»).
- Миграции только добавляются; уже применённые не редактировать.

## Проверки

```bash
# В облачном контейнере Docker может быть не запущен: nohup dockerd >/tmp/dockerd.log 2>&1 &
supabase db start
supabase db reset                                   # миграции с нуля
supabase db lint --level warning --fail-on warning -s public,private,rls
supabase test db                                    # pgTAP
```

iOS собирается только на Mac (Xcode 26, iOS 26): `cd ios && xcodegen generate`. Хуки в `.githooks/`
(включаются `git config core.hooksPath .githooks`) пересоздают проект после `git pull`, если изменился
`ios/project.yml` или состав файлов `ios/Dalada/` и `ios/DaladaWidgets/`. Новые файлы кладём в пакет `DaladaKit`, где
генерация не нужна. На Linux можно
проверить синтаксис (`swiftc -parse`) и модули без UI (`DaladaCore`, `Persistence`, `Sync`, `Backend`) отдельным
пакетом: у `DaladaKit` платформа только iOS, поэтому для Linux — свой `Package.swift` со ссылками на
папки исходников.

Настоящую сборку приложения и тесты пакета делает GitHub Actions на macOS (`.github/workflows/ios.yml`,
в том числе на ветках `claude/**`). Код iOS попадает в `main` только после зелёной сборки на рабочей
ветке. Сборка в TestFlight — `.github/workflows/testflight.yml` (вручную, см. `docs/04-beta/testflight.md`).

## Компоненты интерфейса: DesignKit или Dalada

Дизайн-система — пакет [DesignKit](https://github.com/dkicekeeper/DesignKit) (общий с Tenra). Перед
тем как писать новый компонент, ищи готовый в DesignKit (Gallery в TestFlight, `docs/design-system.md`
в DesignKit): кнопки, карточки (`cardStyle`), строки (`UniversalRow`, `InfoRow`), бейджи
(`BadgeView`, `TrendBadge`), `StatTile`, `AvatarView`, `RatingView`/`RatingPicker`, `ChipPicker`,
`SelectionIndicator`, `LinearProgressBar(value:)`, `EmptyStateView`, `RecommendationBox`,
`DisclosureChevron`, скелетоны загрузки (`SkeletonRow`, `.skeletonLoadingLabel()`),
`LoadingButtonLabel`, `ExpandableText`, `ActivityTimeline`, `MonthCalendar`,
`PermissionPrimerView` (перед системным запросом разрешения), `OnboardingPager` /
`OnboardingPage`. Своё — только если в DesignKit нет подходящего.

Компонент идёт в DesignKit, если выполнены все три условия:
1. **Не знает данных приложения**: принимает текст, числа, даты, цвета, иконки, замыкания и
   `@ViewBuilder`-слоты — никаких `Place`, `Trip`, `Catch`, сторов и сервисов. Если зависимость от
   модели можно заменить параметром — тоже DesignKit, а переходник (`RuleStatus` → `BadgeView`)
   остаётся здесь маленькой обёрткой.
2. **Отвечает на «как выглядит», а не «что значит»**: карточка, строка, бейдж, выбор — да;
   «карточка улова», «форма чекина» — нет.
3. **Нужен в двух местах** (правило двух): нужен и Tenra, или это базовый паттерн, который должен
   выглядеть везде одинаково. Новый компонент можно начать здесь, а при втором применении —
   перенести PR в DesignKit (чеклист переноса — в CLAUDE.md DesignKit).

Признаки, что компонент остаётся в Dalada: в названии слово предметной области (Place, Trip,
Catch, Rule, Gear), или он сам загружает данные и управляет навигацией. Новая версия DesignKit
приходит сама (workflow **DesignKit update**), визуальные изменения перечислены в её release notes.

## Секреты

`ios/Config/Secrets.xcconfig` (хост и publishable key Supabase) — не в git, пример —
`Secrets.example.xcconfig`. Service role key — никогда в приложении и в репозитории.
