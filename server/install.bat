@echo off
chcp 65001 >nul
echo ========================================
echo  Установка зависимостей сервера
echo ========================================
echo.

REM Проверяем наличие Python
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python не найден!
    echo Скачайте с https://www.python.org/downloads/
    pause
    exit /b 1
)

echo [OK] Python найден
python --version
echo.

REM Создаем виртуальное окружение если его нет
if not exist "venv" (
    echo [INFO] Создание виртуального окружения...
    python -m venv venv
    echo [OK] Виртуальное окружение создано
) else (
    echo [OK] Виртуальное окружение уже существует
)
echo.

REM Активируем и устанавливаем зависимости
echo [INFO] Установка библиотек...
call venv\Scripts\activate.bat
python -m pip install --upgrade pip wheel setuptools
pip install -r requirements.txt

if errorlevel 1 (
    echo.
    echo [ERROR] Ошибка установки!
    pause
    exit /b 1
)

echo.
echo ========================================
echo  [SUCCESS] Установка завершена успешно!
echo ========================================
echo.
echo Теперь запустите start_server.bat
pause
