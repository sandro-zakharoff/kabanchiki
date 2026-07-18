# Как вносить правки и собирать программы

## Desktop (Windows-программа)

**Где что лежит** (`desktop/src/kabanchiki_admin/`):

| Что менять | Файл |
|---|---|
| Внешний вид, цвета, отступы | `qml/Theme.qml` (палитра/радиусы/анимации — одно место) |
| Экраны | `qml/TasksPage.qml`, `JobsPage.qml`, `JournalPage.qml`, `SettingsPage.qml`, `Shell.qml` |
| Диалоги | `qml/TaskDialog.qml`, `JobDialog.qml`, `ChildDialog.qml`, … |
| Логика/данные | `backend.py` (мост Python↔QML), `services/supabase_service.py` (запросы к БД) |
| Переводы | `i18n/uk_UA.ts` → после правки перекомпилировать (см. ниже). Английский текст пишется прямо в коде в `qsTr("...")` |
| Версия | `__init__.py` → `__version__` |

**Запуск для проверки** (правки QML/Python видны сразу при перезапуске, ничего собирать не нужно):

```powershell
Set-Location (Join-Path $PSScriptRoot '..\desktop')
.\.venv\Scripts\python.exe src\main.py
```

**Перекомпилировать украинский перевод** (после правок `.ts`):

```powershell
.\.venv\Scripts\pyside6-lrelease.exe src\kabanchiki_admin\i18n\uk_UA.ts -qm src\kabanchiki_admin\i18n\uk_UA.qm
```

**Тесты:** `.\.venv\Scripts\python.exe -m pytest tests -q`

**Собрать exe** (через spec — в нём прописаны метаданные версии Windows из `version_info.txt`):

```powershell
Set-Location (Join-Path $PSScriptRoot '..\desktop')
.\.venv\Scripts\pyinstaller.exe Kabanchiki.spec --noconfirm --clean
```

Результат: `dist\Kabanchiki\Kabanchiki.exe`. После правок кода просто повтори команду — она пересоберёт папку `dist\Kabanchiki` заново. Перед сборкой закрой запущенный Kabanchiki.exe. При смене версии обнови `__init__.py` (`__version__`) и `version_info.txt` (filevers/prodvers/FileVersion/ProductVersion).

> ⚠️ НЕ собирай старой командой `pyinstaller --name Kabanchiki … src\main.py` — она **перегенерирует** `Kabanchiki.spec` и выбросит из него метаданные версии и плагин карт (`geoservices`) → в exe не будет карты OpenStreetMap. Только `pyinstaller Kabanchiki.spec …`. Если spec случайно перезаписан — `git checkout -- desktop/Kabanchiki.spec`.

## Android (приложение исполнителей)

**Где что лежит** (`android/app/src/main/`):

| Что менять | Файл |
|---|---|
| Цвета, типографика | `kotlin/com/kabanchiki/app/core/designsystem/Theme.kt` |
| Компоненты (кнопки, карточки, бейджи) | `core/designsystem/Components.kt` |
| Экраны | `feature/tasks/…`, `feature/jobs/…`, `feature/profile/…`, `feature/auth/…`, `feature/home/HomeScreen.kt` (нижний бар) |
| Данные/запросы | `core/data/*.kt` |
| Пуши и звук | `core/push/…`; звук — файл `res/raw/notification.ogg`. ⚠️ Если меняешь звук — подними `SOUND_VERSION` в `NotificationChannels.kt`, иначе Android оставит старый звук |
| Тексты | `res/values/strings.xml` (EN) и `res/values-uk/strings.xml` (UK) — всегда парой |
| Иконки | `res/mipmap-*`, `res/drawable*` (сгенерированы Android Studio из твоей иконки) |

**Версия — обязательно перед каждой новой сборкой для установки поверх:**
`android/app/build.gradle.kts` → `versionCode` (+1 каждый раз, целое) и `versionName` (человекочитаемая, например `"1.2.0"`).

> Приложение сообщает свою версию в Windows-программу (видно у каждого исполнителя). «Актуальный» versionCode берётся живьём из последнего опубликованного релиза (`app_releases`); константа `FALLBACK_ANDROID_VERSION_CODE` в `desktop/src/kabanchiki_admin/backend.py` — только запасная, но при релизе подними и её.

**Собрать APK:**

```powershell
Set-Location (Join-Path $PSScriptRoot '..\android')
.\gradlew.bat assembleRelease
# результат: app\build\outputs\apk\release\app-release.apk
```

Установка поверх старой версии — просто открой новый APK на телефоне, данные сохранятся (подпись та же). ⚠️ Папку `android/signing/` не удалять и не терять — без неё обновления не встанут.

## Бэкенд (Supabase)

- Схема БД меняется **только** новыми файлами в `supabase/migrations/` (имя `YYYYMMDDHHMMSS_название.sql`), применяются так:
  ```powershell
  $supa = "$env:LOCALAPPDATA\KabanchikiTools\supabase-cli\supabase.exe"
  Set-Location (Join-Path $PSScriptRoot '..')
  $env:SUPABASE_ACCESS_TOKEN = "<access token>"
  $env:SUPABASE_DB_PASSWORD = "<пароль БД>"
  & $supa db push
  ```
- Функция пушей: `supabase/functions/send-push/index.ts` → `& $supa functions deploy send-push`.

## Фоновая геолокация (Android)

Механизм — `android/.../core/location/LocationReporter.kt`:
- Основной драйвер — **AlarmManager `setAndAllowWhileIdle`** цепочкой (каждый будильник перевзводит следующий через 15 мин; в Doze система даёт окно как раз ~раз в 15 мин). WorkManager Periodic(15м) — страховка, `LocationBootReceiver` перевзводит после перезагрузки.
- Точки капаются в очередь (DataStore, cap 200) и шлются пачкой с реальным временем захвата (`location_report(..., p_at)`), поэтому мёртвая сеть не теряет данные.
- При включении тумблера просим убрать из оптимизации батареи (`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`) и показываем экран-инструкцию для агрессивных прошивок (Xiaomi/Huawei/…). Desktop подсвечивает точки старше 30 мин.
- **Если геолокация всё равно молчит часами:** телефон, скорее всего, убивает фон — на нём нужно вручную разрешить автозапуск и снять ограничения батареи для Kabanchiki (в приложении: Профиль → Геолокація → «Відкрити поради»). Полной гарантии «каждые 15 минут» Android не даёт ни одному приложению.

## Уведомления бота (Telegram) — див. `../setup/telegram.md`

Вебхук бота регистрируется автоматически при сохранении токена в Windows-программе. Функции: `supabase functions deploy tg-notify tg-bot` (обе `--no-verify-jwt`). Требуют секрет `WEBHOOK_SECRET` (уже задан). pg_cron задачи (`tg-outbox-retry`, `deadline-reminders`) создаются миграциями.

## Типовые сценарии

- **Поменять цвет во всех программах:** `desktop/.../qml/Theme.qml` + `android/.../designsystem/Theme.kt` (`LightPalette`/`DarkPalette`) + `telegram/styles.css` (:root / [data-scheme=dark]).
- **Добавить поле задаче:** миграция (колонка) → `desktop/backend.py` (+диалог QML) → `android/core/model/Models.kt` (+экран) → `telegram/js/api.js`+`app.js`.
- **Изменить текст:** desktop — в QML `qsTr` + перевод в `.ts` + lrelease; Android — обе `strings.xml`; Mini App — прямо в JS.
- **Тёмная тема Android:** всё через `KabColors.*` (реактивные) — ничего не хардкодить; палитра тёмной в `Theme.kt`.
