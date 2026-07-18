# Kabanchiki Design System

Единая «дорогая iOS-анатомия» трёх клиентов: тёплый фон, белые карточки,
мягкая глубина, сдержанная фирменная палитра от иконки-кабанчика. Этот файл —
контракт: новые экраны оформляются только этими токенами и паттернами.

## 1. Где живут токены

| Платформа | Файл | Что содержит |
|---|---|---|
| Windows | `desktop/src/kabanchiki_admin/qml/Theme.qml` | singleton: цвета, радиусы, отступы, шрифты, тайминги |
| Android | `android/.../core/designsystem/Theme.kt` | `LightPalette` / `DarkPalette` (KabColors — реактивный) |
| Mini App | `telegram/styles.css` | `:root` (light) + `body[data-scheme="dark"]` CSS-переменные |

Меняешь цвет — меняешь во всех трёх местах.

## 2. Палитра

| Токен | Light | Dark | Использование |
|---|---|---|---|
| bg | `#F7F3F1` | `#17161A` | фон окна/страницы |
| surface | `#FFFFFF` | `#232228` | карточки, диалоги, шторки |
| surfaceAlt | `#F1ECEA` | `#2C2A32` | поля ввода, вторичные подложки |
| surfacePressed | `#E7E0DE` | `#3A3742` | нажатое состояние плоских элементов |
| border | `#E4DCD9` | `#38343D` | все рамки (1px; web 0.5px) |
| textPrimary | `#38333B` | `#F3F0F2` | основной текст |
| textSecondary | `#A29AA5` | `#9C93A0` | подписи, вторичный текст |
| accent | `#766D78` | `#9C8FA0` | основные кнопки, активные состояния |
| accentSoft | `#CDB1B1` | `#7C6E74` | заглушки аватаров, мягкие акценты |
| accentDark | `#4A434E` | `#B8A9BC` | тосты, чипы наград |
| danger | `#C96A5F` | `#D98A80` | удаление, просрочка, ошибки |
| warning | `#D99A5B` | `#E0AE73` | «скоро дедлайн», ожидание, доработка |
| success | `#6FA287` | `#86B79E` | выполнено, оплачено, онлайн |
| info | `#8598B5` | `#9AAECB` | нейтральные статусы |

Шкала сложности (обе темы): `#6FA287 #8598B5 #D99A5B #CE8158 #C96A5F`.

## 3. Геометрия и типографика

- **Радиусы:** 10 (поля, мелкие кнопки) / 12 (кнопки, фото-ячейки) / 16 (карточки)
  / 22 (диалоги, шторки); пилюли/чипы — 999.
- **Отступы:** шкала 4-8-12-16-24-32. Внутри карточек 14–16, страницы 16–24.
- **Шрифты:** Segoe UI (Win) / system-ui,-apple-system (web) / платформенный (Android).
  Размеры: 11 (подписи-капсы), 12, 13–14 (вторичный), 14–15.5 (основной),
  17 (заголовок карточки), 22 (заголовок страницы), 28 (крупные значения).
  Деньги и таймеры — `tabular-nums` / Consolas.
- **Тени:** только на «поднятых» элементах: `#20000000`, blur ~12, y=4.
  Плоские списки — только border. Плавающие кнопки/доки — цветная тень акцента.

## 4. Движение

- 120 мс — микро-отклик (hover, цвет), 200–240 мс — переходы/шторки/диалоги,
  easing OutCubic / `cubic-bezier(0.2, 0.8, 0.2, 1)`.
- Нажатие: scale 0.97 (кнопки), 0.985 (карточки). Haptic на мобильных.
- QML-ловушка: НИКОГДА не анимировать цвет от `"transparent"` (это прозрачный
  чёрный — интерполяция идёт через серый). Использовать `Qt.alpha(tone, 0)`.

## 5. Компоненты (канонические реализации)

| Паттерн | Windows | Android | Mini App |
|---|---|---|---|
| Кнопка (primary/secondary/danger/ghost) | `AppButton.qml` | `KButton` | `.btn` (+`.ok/.warn/.danger/.ghost/.sm`) |
| Карточка | `Card.qml` | `KCard` | `.card` (`.tap` для кликабельных) |
| Чип статуса | `Chip.qml` | `KChip` | `.chip .st-*/.pay-*` |
| Аватар (фото→инициалы) | `Avatar.qml` (`source`) | `KAvatar(photoUrl)` | `avatar()` в app.js |
| Сложность (5 сегментов+подпись) | `DifficultyBadge.qml` | `KDifficultyBadge` | `.diffpick` / `deadlineChip` |
| Пикер дедлайна | `DeadlineField/DeadlinePicker.qml` | — (ребёнок не задаёт) | `ui.deadlineSheet` |
| Мультифото-инпут | `PhotoGridInput.qml` | `ProofDialog` grid | `ui.PhotoUploader` |
| Галерея + просмотр | `ImageThumb` + `Lightbox.showList` | `PhotoStrip` + `PhotoViewer` | `.gal` + `ui.lightbox` |
| Кроп аватара | `AvatarPicker/AvatarCropDialog.qml` | `AvatarCropDialog.kt` | `ui.cropSheet` |
| Кастомный select | `AppComboBox.qml` | — | `ui.optionSheet` + `ui.pickField` |
| Сегмент-контрол | `PaymentSegment.qml` | — | `ui.segmented` / `.fseg` |
| Диалог/шторка | `AppDialog.qml` | `AlertDialog` (containerColor=surface) | `.sheet-*` + drag-close |
| Тост | `Toast.qml` | — | `.toast` |
| Скелетоны | — | shimmer в списках | `.skel` |

## 6. Слой хранилища фото

- Каждое вложение/аватар несёт `storage` (`supabase`|`drive`) + `path`.
- Отображение: supabase → signed URL (private) или public URL (avatars);
  drive → `https://drive.google.com/thumbnail?id=…&sz=w480|w1920`.
- Запись — по `app_config.storage_backend`; Drive недоступен → фолбэк в Supabase.
- Оптимизация ДО загрузки на всех клиентах: ≤1920px, WebP q82 (JPEG q85 где
  нет кодека), миниатюра 480px, EXIF/GPS вычищены. Цель 150–450 КБ.
- Реализации: `desktop/services/image_service.py` + `storage_service.py`,
  `android/core/images/ImageOptimizer.kt` + `core/data/StorageBridge.kt`,
  `telegram/js/images.js` + storage-часть `api.js`.

## 7. Правила оформления нового экрана

1. Фон — `bg`; контент — карточки `surface` радиуса 16 с border.
2. Заголовок страницы 22–24 bold, подзаголовок 13 `textSecondary`.
3. Все интерактивные элементы — все состояния: normal/hover/pressed/focus/
   disabled/loading; списки — empty state с логотипом и подсказкой.
4. Формы: подпись 12–13 `textSecondary` над полем; поле `surfaceAlt` радиуса
   10–12; на фокусе рамка `accent`; ошибка — 12px `danger` под полем.
   В Mini App размер шрифта полей ≥16px (iOS-зум) и `appearance:none`.
5. Выборы из 2–5 вариантов — сегмент-контрол, не селект. Длинные списки —
   optionSheet (web) / AppComboBox (desktop).
6. Деньги/время — tabular-nums; статусы — чипы из общей палитры статусов.
7. Дедлайны: «скоро» = < 24 ч (warning), просрочен (danger), одинаковые
   формулировки (`fmt_deadline` / `formatDeadline` / `deadline()`).
8. Термины: «виконавець», «власник». Копирайт `© <год> Zakharoff · Oleksandr
   Zakharov` и фирменные иконки не трогать.
9. Строки: desktop — `qsTr` + uk_UA.ts (+lrelease), Android — обе strings.xml,
   Mini App — украинский прямо в JS.
10. Релиз Mini App: поднять `?v=NNN` в `index.html` **и во всех import-рёбрах**
    (`app.js`, `api.js`, `ui.js`, `images.js`, `config.js`, `format.js`),
    запушить изменения в `telegram/`; GitHub Actions сам опубликует Pages.
