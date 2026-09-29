# M1. Вход и места

> Статус: **M1a (вход и профиль) — код готов, ждёт настройки провайдеров и проверки на Mac.**
> M1b (места) — следующим шагом.

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

## M1b. Места (следующий шаг)

- Места на карте: загрузка `places_in_bbox` при движении карты, свои места и публичные;
  приблизительные — кругом.
- Создание места: долгий тап по карте или «+» → «Новое место»: тип, название, описание,
  видимость (все / друзья / только я), «показывать приблизительно».
- Карточка места снизу по тапу на точку (`place_card`).
- Вкладка «Места»: «Мои места».
- Первая сборка в TestFlight (внутреннее тестирование).
