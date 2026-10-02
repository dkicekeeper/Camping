# Сборка на iPhone без Mac — TestFlight из GitHub Actions

Приложение собирает Mac в GitHub Actions (для публичного репозитория — бесплатно), подписывает
его и загружает в App Store Connect. Вы ставите сборку на iPhone через приложение **TestFlight**.
Mac не нужен ни для сборки, ни для установки.

Нужен платный Apple Developer Program. Судя по тому, что вход через Apple на телефоне работает,
он у вас есть.

## Один раз: настройка (15 минут, в браузере)

Удобнее с любого компьютера, не обязательно Mac. С iPhone тоже можно, но `.p8`-файл с ключом там
придётся открывать через «Файлы».

### 1. Приложение в App Store Connect

[appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **Apps** → «+» → **New App**:
- Platform: iOS; Name: «Dalada» (если занято — «Dalada: рыбалка и природа»);
- Primary Language: Russian; Bundle ID: `app.dalada.ios` (появился, когда Xcode запускал
  приложение на вашем телефоне); SKU: `dalada-ios`; User Access: Full Access.

### 2. Ключ App Store Connect API

**Users and Access** → **Integrations** → **App Store Connect API** → **Team Keys**
(в первый раз — «Request Access» и согласиться с условиями) → «+»:
- Name: `GitHub Actions`; Access: **Admin** (нужен, чтобы Xcode сам создавал сертификат
  и профиль подписи) → **Generate**.
- Запишите **Issuer ID** (над таблицей ключей) и **Key ID** (в строке ключа).
- **Download** — файл `AuthKey_XXXXXXXXXX.p8`. Скачать можно **только один раз**.

Ключ — это секрет: только в GitHub Secrets (шаг 3), не в чат и не в репозиторий. Отозвать
можно в любой момент там же, в Team Keys.

### 3. Секреты в GitHub

Репозиторий → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**,
пять штук:

| Имя | Значение |
|-----|----------|
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_KEY_ID` | Key ID |
| `ASC_KEY_P8` | Всё содержимое `.p8`-файла (открыть как текст), вместе со строками `-----BEGIN PRIVATE KEY-----` и `-----END PRIVATE KEY-----` |
| `SUPABASE_HOST` | Как в `ios/Config/Secrets.xcconfig` (без `https://`) |
| `SUPABASE_KEY` | Publishable key, как в `Secrets.xcconfig` |

### 4. Тестировщики

App Store Connect → Dalada → **TestFlight** → **Internal Testing** → «+» → группа «Команда» →
добавить себя (и других участников вашей команды App Store Connect, до 100 человек). Включите
**Automatic Distribution** — новые сборки будут приходить сами.

На iPhone — приложение **TestFlight** из App Store, вход тем же Apple ID.

### 5. Внешние тестировщики (по публичной ссылке)

TestFlight → **External Testing** → группа → «Public Link». Для внешних тестировщиков каждая
**версия** (`MARKETING_VERSION`, сейчас 0.1.0) проходит **бета-проверку Apple** (Beta App Review,
обычно до суток-двух). Пока одна сборка версии ждёт проверки, другую сборку той же версии
отправить нельзя. После одобрения следующие сборки той же версии добавляются в группу без
полной проверки.

Проверяющие Apple смотрят требования к пользовательскому контенту: жалобы, блокировка, фильтр,
контакт для связи (Guideline 1.2), удаление аккаунта из приложения (5.1.1(v)). Жалобы, блокировка,
фильтр и удаление аккаунта есть со сборки 107, ссылки на политику и поддержку и согласие при
входе — со 108, пуши — со 109, места редакции — со 110.

Если сборка 107 уже ждёт проверки — её можно не трогать: после одобрения версии 0.1.0 сборку 110
можно сразу добавить во внешнюю группу. Если 107 отклонили или вы хотите проверку сразу на свежей
сборке — Expire для 107 и отправьте 110 с текстами ниже.

**Test Information** (TestFlight → Test Information): Feedback Email — dakacom@gmail.com; Privacy
Policy URL — https://dkicekeeper.github.io/Dalada/privacy-policy.html (страница публикуется через
GitHub Pages, см. [M6c](M6-beta-readiness.md#m6c-документы-поддержка-согласие)); в Beta App Review
Information — контакт и демо-аккаунт (ниже).

### Демо-аккаунт для проверки Apple

Без демо-аккаунта Apple бету не проверяет (Guideline 2.1(a): «provide a user name and password») —
так отклонили сборку 107. Вход через Apple/Google проверяющим не подходит, поэтому в приложении есть
**вход по почте и паролю** («Главная» или «Профиль» → «Войти по почте и паролю»). Такой аккаунт заводит только
редакция: регистрация по почте на сервере закрыта (триггер на `auth.users`), в том числе и через
«Add user» в панели Supabase.

1. Supabase → **SQL Editor**:
   `select private.create_review_account('почта', 'пароль');` — пароль от 8 символов, почта любая
   (лучше своя, например с `+review`: на неё могут прийти письма о сбросе пароля). Функция создаёт
   аккаунт `@appreview` с согласием и содержимым «только для себя» (другим не видно): два своих
   места с «Информацией», отчёты с уловами (один — на водоёме редакции, после него можно оставить
   отзыв), поездка с треком, три сохранённых места. Повторный вызов меняет пароль, содержимое не
   дублирует. Если проверяющие удалят аккаунт — просто вызовите ещё раз.
2. GitHub → репозиторий **Dalada** → Settings → Secrets and variables → Actions → вкладка
   **Secrets** → «New repository secret» (не Variables и не Environment): **`ASC_DEMO_USER`**
   (почта) и **`ASC_DEMO_PASSWORD`** (пароль). Пароль — только туда, не в чат и не в репозиторий.
   Можно и вручную в App Store Connect → TestFlight → Test Information → Beta App Review
   Information («Sign-in required», User Name, Password) — без секретов workflow эти поля не
   трогает. Без демо-аккаунта workflow на бета-проверку не отправит.
3. Actions → **TestFlight info** → Run workflow: номер сборки и галочка «отправить на
   бета-проверку». Workflow отметит «Sign-in required» и передаст почту и пароль в Beta App Review
   Information (в лог они не попадают); без секретов он предупредит и поля входа не тронет.

Вход по почте в Supabase (Authentication → Sign In / Providers → Email) должен быть включён — он
включён по умолчанию.

### Тексты для TestFlight и Beta App Review

Тексты лежат в `appstore/testflight/` и попадают в App Store Connect сами — workflow **TestFlight
info** (`appstore/testflight_info.py`, тот же ключ API из секретов `ASC_*`):

| Файл | Куда в App Store Connect |
|------|--------------------------|
| `beta_description.<язык>.txt` | Test Information → Beta App Description (+ почта для отзывов и политика конфиденциальности) |
| `review_notes.txt` | Beta App Review Information → Notes; демо-аккаунт — из секретов `ASC_DEMO_*` |
| `what_to_test.<язык>.txt` | What to Test у сборки (без эмодзи: App Store Connect их не принимает) |

Когда запускается: после каждой сборки TestFlight (ждёт обработки сборки до 45 минут и ставит What
to Test), при изменении текстов в `main` и вручную — Actions → **TestFlight info** → Run workflow;
там же можно указать номер сборки и галочку «отправить на бета-проверку» (добавит сборку во
внешние группы и отправит, если версия ещё не одобрена). В итогах запуска — таблица последних сборок
с состоянием внутреннего и внешнего тестирования.

Имя, фамилию и телефон для связи с проверяющими workflow не заполняет (и не выводит в лог) — если
их нет, он предупредит; заполните один раз в Test Information → Beta App Review Information.

## Каждая сборка

**Actions** → **TestFlight** → **Run workflow** → **Run workflow**. С телефона — в приложении
GitHub или на github.com в Safari. Сборку после каждой вехи могу запускать и я.

Сборка и загрузка — 15–25 минут, ещё 10–30 минут App Store Connect обрабатывает сборку.
Потом в TestFlight на iPhone появится «Обновить» (или письмо-приглашение в первый раз).

Номер сборки ставится сам (101, 102, …), версия — из `ios/project.yml` (`MARKETING_VERSION`).
Сборки TestFlight работают 90 дней.

## Если что-то пошло не так

- **«Не заданы секреты»** — проверьте имена в шаге 3 (регистр важен).
- **«No suitable application records were found»** — нет приложения в App Store Connect (шаг 1)
  или другой Bundle ID.
- **Ошибка подписи / «Cloud signing permission error»** — у ключа роль ниже Admin; создайте
  новый ключ с Admin и обновите три секрета `ASC_*`.
- **«cannot register bundle identifier "app.dalada.ios.widgets"»** — идентификаторы приложения и
  виджета Live Activity регистрирует шаг «Register bundle identifiers» через API. Если он пишет
  «нужна роль Admin», либо создайте ключ с Admin, либо зарегистрируйте вручную:
  [developer.apple.com](https://developer.apple.com/account/resources/identifiers/list) →
  Identifiers → «+» → App IDs → App → Description «Dalada Widgets», Bundle ID (Explicit)
  `app.dalada.ios.widgets` → Continue → Register.
- **«Invalid bundle… UISupportedInterfaceOrientations… iPad multitasking» (90474)** — приложение
  только в портрете, поэтому в `ios/project.yml` стоит `UIRequiresFullScreen: YES`; если ключ
  пропал — верните.
- **«Для бета-проверки можно отправить только одну сборку версии…»** — сборка этой версии уже
  ждёт проверки. Либо дождитесь одобрения и добавьте новую сборку в группу, либо уберите ждущую:
  TestFlight → iOS → эта сборка → **Expire Build** (Прекратить тестирование) — после этого можно
  отправить на проверку другую сборку той же версии.
- Остальное — пришлите ссылку на запуск в Actions или текст ошибки.
