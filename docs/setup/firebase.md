# Настройка Firebase (пуш-уведомления)

Пуши при закрытом приложении на Android доставляются только через Firebase Cloud Messaging (FCM). Это бесплатно и не требует публикации в Play Market.

## 1. Создать проект (~10 минут)

1. Зайди на <https://console.firebase.google.com> под своим Google-аккаунтом.
2. **Create a project** (Добавить проект):
   - Название: `kabanchiki`
   - Google Analytics: **выключи** (не нужен).
3. Когда проект создан — на главной странице проекта нажми значок **Android** (добавить Android-приложение):
   - **Android package name**: `com.kabanchiki.app` — ⚠️ ровно так, это важно.
   - Nickname: `Kabanchiki` (любое).
   - SHA-1 — оставить пустым.
   - **Register app** → **Download google-services.json**.
4. Дальше в мастере просто жми Next/Continue до конца (ничего в код добавлять не нужно — уже сделано).

## 2. Ключ сервис-аккаунта (для отправки пушей с сервера)

1. В Firebase Console: ⚙️ (Project settings) → вкладка **Service accounts**.
2. Кнопка **Generate new private key** → подтверди → скачается файл `kabanchiki-xxxx-firebase-adminsdk-....json`.

## 3. Что мне передать

1. Файл **google-services.json** положите в `android/app/google-services.json`. Он игнорируется Git и не должен включаться в исходную историю.
2. Файл **ключа сервис-аккаунта** (`...firebase-adminsdk....json`) → скажи, где лежит. Я загружу его содержимое в секреты Supabase (`FCM_SERVICE_ACCOUNT`) — он нужен Edge Function, локально храниться не будет.

## 4. Кастомный звук

Пришли/положи куда-нибудь звуковые файлы (mp3/ogg/wav, до ~30 сек):

- один общий звук — или три разных:
  - «новая задача»
  - «работа запущена/остановлена»
  - «решение по выводу»

Я вшью их в APK (`res/raw/`) и привяжу к каналам уведомлений. Звук играет даже при закрытом приложении.
