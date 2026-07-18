# Сборка и установка APK

## Сборка (на этом ПК)

```powershell
Set-Location (Join-Path $PSScriptRoot '..\android')
.\gradlew.bat assembleRelease
```

Готовый файл: `android\app\build\outputs\apk\release\app-release.apk`.

- Используйте JDK 17 через `JAVA_HOME` и Android SDK через локальный `local.properties` (создайте его из `android/local.properties.example`).
- Подпись: release-ключ лежит в `android\signing\kabanchiki.keystore` (создан при первой сборке; пароли — в `android\signing\keystore.properties`). ⚠️ Не удаляй ключ: обновления поверх установленного приложения должны быть подписаны им же. Папка в `.gitignore`.

## Установка на телефон

1. Скинь `app-release.apk` на телефон (кабель, Telegram «Избранное», Google Drive — как угодно).
2. Открой файл на телефоне → Android спросит разрешение «Устанавливать из этого источника» → разреши.
3. После установки при первом входе приложение попросит разрешение на уведомления — обязательно разрешить.
4. Рекомендую: Настройки → Приложения → Kabanchiki → Батарея → **Без ограничений** (чтобы OEM-оболочка не душила доставку пушей).

## Обновление версии

Собери новый APK тем же способом и просто установи поверх — данные сохранятся (подпись та же).
