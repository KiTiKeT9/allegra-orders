@echo off
chcp 65001 >nul
title Order Management Server

echo ========================================
echo  Запуск сервера заказов
echo ========================================
echo.

REM Проверяем наличие venv
if not exist "venv" (
    echo [ERROR] Виртуальное окружение не найдено!
    echo Запустите install.bat сначала
    pause
    exit /b 1
)

echo [INFO] Запуск сервера...
echo [INFO] Откройте http://127.0.0.1:8000/docs для API
echo.

call venv\Scripts\activate.bat
python main.py

pause
