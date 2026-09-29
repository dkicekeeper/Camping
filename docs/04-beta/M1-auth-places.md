# M1. Вход и места

> Статус: **M1a (вход и профиль) — ✅ проверено на iPhone (Sign in with Apple, 2026-09-29).**
> **M1b (места) — код готов, ждёт проверки на Mac.** Дальше — первая сборка в TestFlight.

## M1a. Вход и профиль

### Что делает приложение

| Состояние | Что видит пользователь |
|-----------|------------------------|
| Гость | На «Профиле» — карточка входа: «Sign in with Apple» и «Войти через Google». Остальные вкладки работают без входа |
| Первый вход | Экран «Имя пользователя» на весь экран: проверка формата сразу, занятости — на сервере через 0,4 с после ввода; «Продолжить» активна только для свободного имени. Можно выйти |
| Вошёл | Шапка профиля: инициалы, имя (от Apple — при первом входе, от Google — из аккаунта), @username. Меню «•••» → «Выйти» |
| Профиль не загрузился | Сообщение об ошибке и «Повторить» |

Сессия хранится в Keychain (supabase-swift) и переживает перезапуск приложения.

### Код

- `Backend/BackendClient.swift` — `authChanges()`, `signInWithApple`, `signInWithGoogle`,
  `signOut`, `myProfile`, `updateProfile`, `isUsernameAvailable`; ошибки «имя занято» и
  «неверный формат» различаются по кодам базы (`23505`, `22023`).
- `DaladaCore/UserProfile.swift` — профиль, правила username (как в базе), случайный nonce.
- `AppFeature/SessionStore.swift` — состояние входа; `SignInCard`, `UsernameOnboardingView`,
  обновлённый `ProfileHomeView`.
- `Dalada/Dalada.entitlements` — capability «Sign in with Apple».
- База: `username_available` и правила username — уже в облаке (миграция `…_usernames.sql`).

### Что нужно настроить вам

**A. Sign in with Apple**

1. Supabase → **Authentication → Sign In / Providers → Apple** → включить.
2. В поле **Client IDs** впишите `app.dalada.ios`. **Secret Key** оставьте пустым — он нужен только
   для входа через браузер, а у нас нативный вход.
3. Save.
4. В Xcode ничего делать не нужно: capability уже в проекте, автоматическая подпись сама включит
   Sign in with Apple для `app.dalada.ios` в вашем аккаунте разработчика.
5. На симуляторе: Настройки → войдите в Apple Account (иначе кнопка Apple выдаст ошибку).

**B. Вход через Google**

1. [console.cloud.google.com](https://console.cloud.google.com) → создайте проект «Dalada».
2. **Google Auth Platform → Branding**: название «Dalada», email поддержки.
   **Audience**: External. Пока приложение в режиме Testing, войти могут только добавленные
   **Test users** (до 100) — добавьте свои аккаунты и аккаунты тестеров.
3. **Clients → Create client** → тип **Web application**. В **Authorized redirect URIs** вставьте
   Callback URL из Supabase (Authentication → Providers → Google, вида
   `https://<ваш-проект>.supabase.co/auth/v1/callback`).
4. Скопируйте **Client ID** и **Client secret** → Supabase → Authentication → Providers →
   **Google** → включить → вставить → Save.

**C. Адрес возврата в приложение**

Supabase → **Authentication → URL Configuration → Redirect URLs** → Add URL → `dalada://auth-callback`.

### Как проверить

1. `git pull` → в папке `ios`: `xcodegen generate` (добавились файлы) → Run.
2. «Профиль» без входа: карточка входа и «Сервер: Подключено».
3. Sign in with Apple → экран «Имя пользователя»: `admin` — «Уже занято», `.arman` — ошибка
   формата, своё имя — «Свободно» → «Продолжить» → шапка профиля с @username.
4. Перезапустите приложение — вы всё ещё вошли.
5. «•••» → «Выйти» → снова карточка входа.
6. То же через Google.

Ошибки сборки или входа — присылайте текст или скриншот.

## M1b. Места

### Что делает приложение

| Где | Что |
|-----|-----|
| Карта | Места в видимой области загружаются через 0,3 с после остановки карты (`places_in_bbox`). Свои — оранжевые точки, чужие — фиолетовые. Приблизительные чужие места — полупрозрачный круг ~1 км |
| Карта | **Новое место:** долгое нажатие на карту или кнопка «+ Место» (ставит точку в центр экрана). Гостю — подсказка войти |
| Форма | Название, тип (9 типов), описание, «Кто видит»: все / друзья / только я, «Показывать приблизительно» (для «только я» выключено), координаты. Подсказка под переключателем объясняет, что увидят другие |
| Карточка | По тапу на точку или круг: тип, название, видимость, «На проверке» для мест на модерации, пояснение про приблизительность, описание, автор, кнопка «Маршрут» в Apple Maps (для огрублённых мест без точки подъезда маршрута нет — чтобы не раскрыть точку) |
| «Места» | «Мои места» — все свои места с видимостью и статусом, обновление жестом вниз, карточка по тапу |

Первые 3 публичных места нового автора уходят на модерацию: автор их видит, другие — нет.
Опубликовать: Supabase → Table Editor → `places` → `status` = `published`.

### Код

- База: `migrations/…_my_places.sql` — RPC `my_places`; тесты `tests/database/03_my_places.test.sql`
  (в том числе вставка места в том виде, в каком её делает приложение).
- `DaladaCore/Place.swift` — типы места, видимость, статус, `PlaceSummary`, `PlaceDetails`,
  `PlaceDraft`; `GeoPoint.circle`, `GeoBoundingBox` — с тестами.
- `Backend/PlacesAPI.swift` — места в области, мои места, карточка, создание (координаты — EWKT).
- `MapEngine/DaladaMapView.swift` — слои стиля (круги, точки, метка нового места), тап,
  долгое нажатие, видимая область.
- `AppFeature` — `MapScreenModel`, `MapHomeView`, `PlaceFormView`, `PlaceCardView`,
  `PlacesHomeView` (Мои места).

### Как проверить

1. `git pull` → Run (новые файлы — в пакете, `xcodegen` не нужен).
2. «Карта» → долгое нажатие у Капшагая → форма → «Только я» → Сохранить → оранжевая точка.
3. Ещё одно место «Друзья» + «Показывать приблизительно», и одно «Все».
4. Тап по точке → карточка; у публичного — «На проверке».
5. «Места» → три места со значками видимости.
6. Выйти → на карте свои места пропали (гость видит только опубликованные публичные).

## Первая сборка в TestFlight

1. App Store Connect → Apps → «+» → New App: платформа iOS, имя «Dalada» (если занято —
   «Dalada: рыбалка и природа»), язык — русский, bundle ID `app.dalada.ios`, SKU `dalada-ios`.
2. Xcode: вверху выбрать **Any iOS Device (arm64)** → Product → **Archive**.
3. В окне Organizer → **Distribute App** → **App Store Connect** → Upload (подпись автоматическая).
4. Через 10–30 минут сборка появится в App Store Connect → TestFlight. На вопрос про шифрование
   ответ уже задан в проекте (`ITSAppUsesNonExemptEncryption = NO`).
5. TestFlight → **Internal Testing** → «+» группа → добавить себя и других участников команды
   App Store Connect → они получат приглашение в приложение TestFlight. Проверка Apple не нужна.
6. Каждую следующую сборку: увеличить **Build** (`CURRENT_PROJECT_VERSION` в `ios/project.yml`,
   я буду делать это сам перед релизными сборками) → Archive → Upload.
