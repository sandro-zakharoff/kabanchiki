# Kabanchiki — Telegram Mini App

Статичний веб-застосунок (vanilla JS + supabase-js через CDN + Telegram WebApp SDK),
що дублює керування з Windows-програми: виконавці, завдання (аппрув/оплата), роботи
(старт/стоп/виводи), бонуси, журнал. Синхронізація з десктопом у реальному часі через
Supabase Realtime.

## Структура

- `index.html` — оболонка, підключає Telegram SDK і `js/app.js`.
- `styles.css` — брендовий iOS-стиль, підлаштовується під тему Telegram (світла/темна).
- `config.js` — публічний Supabase bootstrap config (плейсхолдер у git). Заповнюється
  вашими значеннями вручну або генерується workflow'ом Pages з репозиторних Variables
  `KABANCHIKI_SUPABASE_URL` / `KABANCHIKI_SUPABASE_ANON_KEY`. Секрети сюди не додаються.
- `js/config.js` — runtime-derived endpoints used by the client.
- `js/format.js` — гроші/час/статуси (дзеркалить desktop `models.py`).
- `js/api.js` — Supabase-клієнт, вхід через `tg-auth`, усі запити/мутації.
- `js/app.js` — контролер: авторизація, realtime, рендер, дії.

## Авторизація

`js/api.js → signInWithTelegram()` шле `initData` (+ одноразовий код прив'язки) у Edge
Function `tg-auth`, отримує magic-link `token_hash`, міняє його на сесію Supabase. Далі —
ті самі RLS/RPC, що й у десктопі. Токен бота застосунок ніколи не бачить.

## Хостинг і деплой

GitHub Pages публікує workflow `Deploy Telegram Mini App` з каталогу `telegram/`
єдиного репозиторію. Живий URL — HTTPS-адрес GitHub Pages, показаний після
публікації workflow.

**Кеш:** Pages віддає файли з `max-age=600`, тому при кожному релізі підніміть мітку
`?v=NNN` у `index.html` (script src) та в усіх import-рядках `js/app.js` і `js/api.js` —
інакше WebView до 10 хвилин може змішувати старі й нові модулі.

Повна інструкція з ботом — `../docs/setup/telegram.md`.

## Локальна перевірка

```bash
cd telegram && python -m http.server 8777
# відкрити http://localhost:8777 — поза Telegram покаже екран «Відкрийте у Telegram»
```
