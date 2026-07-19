@echo off
REM Double-click to publish the Telegram Mini App to GitHub (live site).
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy-miniapp.ps1" %*
echo.
pause
