@echo off
chcp 65001 >nul
title Allegra Desktop App

REM Переходим в папку, где лежит этот bat-файл (desktop/)
cd /d "%~dp0"

REM Проверяем наличие node_modules
if not exist "node_modules" (
    echo [INFO] Установка зависимостей Electron-приложения...
    call npm install
    if errorlevel 1 (
        echo [ERROR] Не удалось установить зависимости!
        pause
        exit /b 1
    )
)

REM Запускаем Electron-приложение
echo [INFO] Запуск Allegra Desktop...
npm start

exit
