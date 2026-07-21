# Kabanchiki — архітектура

Сімейна система завдань і винагород. Дорослий («власник») створює завдання та погодинні роботи, діти («виконавці») виконують їх і отримують жолуді. Один бекенд, три клієнти.

```
┌─────────────────┐     ┌──────────────────┐     ┌───────────────────┐
│  Windows (адмін) │     │ Android (викон.) │     │ Telegram Mini App │
│  PySide6 + QML   │     │ Kotlin + Compose │     │ vanilla JS (адмін)│
└────────┬────────┘     └────────┬─────────┘     └─────────┬─────────┘
         │  parent JWT (RLS)      │  child JWT (RLS+RPC)    │  parent JWT
         └────────────┬──────────┴──────────┬──────────────┘
                      ▼                     ▼
              ┌──────────────────────────────────┐
              │  Supabase (your project)         │
              │  Postgres + RLS + RPC + Realtime │
              │  Storage · Auth · Edge Functions │
              └──────────────────────────────────┘
```

## Компоненти та точки входу

| Платформа | Тека | Точка входу | Стек |
|---|---|---|---|
| Windows-адмінка | `desktop/` | `src/kabanchiki_admin/__main__.py` → `Main.qml`/`Shell.qml` | Python 3.13, PySide6 (QML), qasync, supabase-py; збірка PyInstaller (`Kabanchiki.spec`) |
| Android (виконавці) | `android/` | `MainActivity.kt` → `AppRoot.kt` | Kotlin, Jetpack Compose, supabase-kt, FCM; пакет `com.kabanchiki.app`, minSdk 26 |
| Telegram Mini App (адмінка) | `telegram/` | `index.html` → `js/app.js` | vanilla JS + supabase-js@2 (CDN) + Telegram WebApp SDK |
| Бекенд | `supabase/` | міграції + `functions/{admin,send-push,tg-auth}` | Postgres, Deno Edge Functions |

**Деплой Mini App:** каталог `telegram/` публикуется GitHub Actions workflow
`miniapp-pages.yml` из единого репозитория. Второй репозиторий для Mini App не
требуется; домен Pages задаётся настройками репозитория и не зашит в клиент.

## Desktop (`desktop/src/kabanchiki_admin/`)

- `backend.py` — єдиний QObject-міст у QML: моделі (`DictListModel` для дітей/завдань/робіт/виводів/журналу), слоти-мутації через `@asyncSlot`, оптимістичні оновлення + `_schedule_refresh`.
- `services/supabase_service.py` — усі запити до Supabase (parent JWT, RLS/RPC); привілейовані auth-операції — через Edge Function `admin` (`call_admin`).
- `services/realtime_service.py` — підписка на `public`-таблиці; УВАГА: realtime-py віддає тип події str-Enum'ом, нормалізація у `_on_change`.
- `services/notification_service.py` + `app_identity.py` — Windows-тости (AUMID `Kabanchiki.Desktop`).
- `config.py` — `%APPDATA%\Kabanchiki\config.json`, `DEFAULT_SUPABASE_URL`/`DEFAULT_ANON_KEY` (публічні), frozen-aware шляхи ресурсів (`assets_dir()`); сесія (refresh token) у Windows Credential Manager через `keyring`.
- `qml/` — iOS-стиль (Theme.qml: фон #F7F3F1, акцент #766D78), базові компоненти `AppDialog/AppButton/Card/...`, сторінки `TasksPage/JobsPage/JournalPage/SettingsPage`, діалоги.
- i18n: `i18n/uk_UA.ts` → `.qm` (українська за замовчуванням, перемикач uk/en).

## Android (`android/app/src/main/kotlin/com/kabanchiki/app/`)

- `core/data/*Repository.kt` — запити (tasks/jobs/bonuses/devices/update), `RealtimeSync` (realtime + heartbeat presence 20 с + signOutIfBlocked), `TimeSync` (`server_now()` — час і жолуді рахуються ТІЛЬКИ від серверних міток).
- `core/tracking/` — `TaskTrackingService`/`JobTrackingService` (FGS-таймери з ongoing-нотифікацією), `OfflineGuard` (гап >10 хв → пауза, RPC `task_apply_offline_gap`).
- `core/push/` — FCM data-повідомлення, рендер локально (канали з кастомним звуком, версія в id `tasks_v1`).
- `feature/` — екрани: Login, Home (кастомний нижній док), Tasks/TaskDetail, Jobs, Profile, UpdateBanner.
- Самооновлення: `UpdateRepository` порівнює `latest_release()` з BuildConfig → DownloadManager → FileProvider → інсталяція. Публікація з desktop (Settings → «Опублікувати оновлення», Storage bucket `app-releases`).
- Підпис: `android/signing/kabanchiki.keystore` (НЕ пересоздавати). `versionCode` +1 на кожну збірку.

## Авторизація — три шляхи

1. **Виконавці (Android):** email `<username>@kabanchiki.local` + пароль → child JWT. Читання — вузькі RLS-політики «своє», усі мутації — SECURITY DEFINER RPC (`task_start/pause/complete/decline`, `request_withdrawal`, `register_device`, …) з гардом `is_blocked()`.
2. **Власники (Windows):** email + пароль → parent JWT. `parents` (id = auth.uid) + `is_parent()`; permissive RLS-політики parent-all на всіх data-таблицях; привілейовані RPC мають гард (`auth.uid() is null` = service_role OK; parent OK; інакше NOT_PARENT). Auth-операції (створення/видалення користувачів, паролі) — тільки Edge Function `admin` (сама перевіряє parent JWT, service_role лишається на сервері).
3. **Mini App (Telegram):** `tg-auth` перевіряє HMAC `initData` токеном бота (ключ `WebAppData`); знаходить parent за `telegram_id` або прив'язує за одноразовим `link_code` (deep link `t.me/<bot>?startapp=<code>`, 15 хв, генерує desktop через RPC `parent_start_link`); мінтить magiclink `token_hash` → Mini App міняє його на сесію `supabase.auth.verifyOtp()`. Далі — той самий parent JWT, що й у desktop.

Токен бота зберігається в `app_secrets` (RLS без політик — лише service_role), задається власником з desktop (`set_telegram_bot_token`), клієнтам доступний тільки булевий `telegram_bot_configured()`.

## Схема БД (після 19 міграцій)

**Основні таблиці:** `profiles` (виконавці; + `last_seen_at`, `blocked`), `devices` (FCM-токени; + `app_version/app_version_code`), `tasks` (статуси `new/in_progress/paused/submitted/done/declined`; `completion_mode timer|simple`; `payment_status unpaid/awaiting/paid` + `paid_at`; proof text/photo; `created_by`+`created_by_name` — авторство), `task_intervals`, `jobs` (`idle/running/archived`; + авторство) + `job_members` (баланс від `earnings_reset_at`) + `job_sessions`, `withdrawals` (+ `payment_status`), `bonuses`, `notifications_outbox`, `app_releases`, `parents` (+ `telegram_id`, `link_code`, `phone`, `note`, `disabled`), `app_config` (singleton: bot username, miniapp URL), `app_secrets` (токен бота), `events` (аудит: пишуть ТІЛЬКИ тригери, читають власники; ретенція ~5000), `locations` (остання 50-точкова історія геолокації виконавця через RPC `location_report`; читають власники).

**Ключові принципи:**
- Час/жолуді рахуються тільки на сервері (`server_now()`, `job_earned_seconds()`, view `job_member_stats` security_invoker).
- Життєвий цикл завдання: `new → in_progress/paused → submitted → (власник: task_review) done / declined / назад у new (rework, нотатка в decline_reason)`. `simple`-завдання: `new → done` одразу (`task_complete`).
- Вивід: `request_withdrawal` (сума рахується сервером) → `admin_decide_withdrawal` (approve → `payment_status='awaiting'`, баланс скидається `earnings_reset_at = period_to`; decline — баланс зберігається).

## Пуші виконавцям (FCM)

Тригери БД пишуть у `notifications_outbox` → Database Webhook (insert) → Edge Function `send-push` → FCM **data**-повідомлення → Android сам рендерить нотифікацію (локалізація + кастомні звуки). Події: `task_created`, `job_assigned/started/stopped`, `withdrawal_decided`, `bonus_granted`, `task_reviewed/paid`, `withdrawal_paid`, `app_update`, `deadline_soon`.

## Сповіщення власникам (Telegram-бот)

Дії виконавців у журналі (`events`) → тригер додає у `tg_outbox` → pg_net webhook → Edge Function `tg-notify` (`sendMessage` кожному прив'язаному активному власнику, inline-кнопки). Кнопки обробляє Edge Function `tg-bot` (вебхук бота, `secret_token` у `app_secrets`, реєструється авто при збереженні токена в desktop через admin-екшен `register_tg_webhook`) → RPC `bot_act()` виконує дію від імені власника (`set_config('app.actor_id')` + `event_actor()` це поважає → у журналі власник, а не «Система»). Повтори — pg_cron sweep (`tg-outbox-retry`, 5 разів). Прострочені дедлайни й нагадування — pg_cron `deadline-reminders` (кожні 10 хв, `run_deadline_reminders()`).

## Realtime

Публікація `supabase_realtime` включає всі робочі таблиці (+`profiles` окремою міграцією — інакше підписка падає). Desktop і Mini App підписані на `public.*` → debounce-перезавантаження моделей; Android — `RealtimeSync`.

## Presence (три рівні)

`active` — `profiles.last_seen_at` < 50 с (heartbeat 20 с з Android); `reachable` — є рядок у `devices` (пуш дійде); `offline` — інакше.

## Інструменти розробки

- Міграції: Supabase Management API (скрипт-обгортка; потрібен `User-Agent`) або CLI; функції — `supabase functions deploy` (обидва в `%LOCALAPPDATA%\KabanchikiTools\`).
- Desktop-збірка: PyInstaller (`desktop/README.md`); перед пересборкою закрити запущений `Kabanchiki.exe`.
- Android-збірка: Gradle 8.14.2, JDK 17 (шлях прошито в `android/gradle.properties`); `development.md`.
- E2E: pytest-скрипти проти реального проєкту Supabase (service_role з Credential Manager).
