# Kabanchiki Desktop (программа родителя)

Windows-программа управления: дети, задачи, почасовые работы, заявки на вывод. PySide6 (QML) + Supabase.

## Установка

```powershell
Set-Location $PSScriptRoot
py -3.13 -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

## Запуск

```powershell
.\.venv\Scripts\python.exe src\main.py
```

При первом запуске программа просит **email и пароль родителя-владельца**. Публичные параметры Supabase находятся в `config.example.json` рядом с приложением и могут быть переопределены переменными `KABANCHIKI_SUPABASE_URL` и `KABANCHIKI_SUPABASE_ANON_KEY`. Сессия хранится в Windows Credential Manager, настройки — в `%APPDATA%\Kabanchiki\config.json`. Мастер-ключ `service_role` на ПК не хранится — привилегированные операции идут через сервер (RLS + Edge Function `admin`).

## Тесты

```powershell
.\.venv\Scripts\python.exe -m pytest tests -q
```

## Сборка EXE

```powershell
.\.venv\Scripts\pyinstaller.exe --noconfirm --clean --windowed --name Kabanchiki --icon assets\app.ico --paths src --add-data "src\kabanchiki_admin\qml;kabanchiki_admin\qml" --add-data "src\kabanchiki_admin\i18n;kabanchiki_admin\i18n" --add-data "assets;assets" src\main.py
```

Результат: `dist\Kabanchiki\Kabanchiki.exe` (папку `dist\Kabanchiki` можно переносить целиком; настройки и ключ подключения хранятся отдельно — в `%APPDATA%\Kabanchiki` и Credential Manager, поэтому пересборка их не трогает).
