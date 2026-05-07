# План сборки Allegra Desktop

## Стек
- **Frontend:** Electron (HTML/CSS/JS), нативный встроенный рендерер
- **Backend:** Встроенный Express.js сервер (Node.js), работает внутри главного процесса Electron
- **Хранение данных:** JSON-файл (metadata.json) + папка orders/ в userData

## Что изменилось
- Python-сервер (FastAPI + Uvicorn) **полностью заменён** на встроенный Node.js сервер.
- Больше не нужен Python, venv, pip или какие-либо внешние зависимости — только Node.js + npm.
- Данные хранятся в `app.getPath('userData')/data/` — папка создаётся автоматически при первом запуске.
- Приложение полностью переносимо: после сборки `electron-builder` работает на любом Windows ПК без установки Python.

## Запуск разработки
```bash
cd desktop
npm install
npm start
```

## Сборка инсталлятора
```bash
cd desktop
npm run build:win
```

## Структура desktop/
- `main.js` — главный процесс Electron + встроенный Express сервер
- `renderer.js` — логика интерфейса (заказы, табы, логи)
- `index.html` — разметка с sidebar и 2 вкладками
- `styles.css` — стили
- `package.json` — зависимости (express, multer, cors, electron, electron-builder)

## API endpoints (встроенный сервер)
- `POST /api/upload` — загрузка файлов заказа
- `GET /api/orders` — список заказов
- `PUT /api/orders/:id` — обновление статистики заказа
- `DELETE /api/orders/:id` — удаление заказа
- `GET /api/health` — проверка здоровья
