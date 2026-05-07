from fastapi import FastAPI, UploadFile, File, Form, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from starlette.middleware.base import BaseHTTPMiddleware
from typing import List, Optional
import os
import shutil
from datetime import datetime
import json
from pathlib import Path

MAX_UPLOAD_SIZE = 500 * 1024 * 1024

class MaxBodySizeMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        if request.method == "POST" and "/api/upload" in str(request.url):
            request._body = await request.body()
        response = await call_next(request)
        return response

app = FastAPI(title="Order Management Server", version="2.3")
app.add_middleware(MaxBodySizeMiddleware)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

BASE_DIR = Path(__file__).parent
UPLOAD_DIR = BASE_DIR / "orders"
METADATA_FILE = BASE_DIR / "metadata.json"
WEB_DIR = BASE_DIR.parent / "web"

def load_metadata():
    if METADATA_FILE.exists():
        try:
            with open(METADATA_FILE, 'r', encoding='utf-8') as f:
                return json.load(f)
        except:
            return {}
    return {}

def save_metadata(metadata):
    with open(METADATA_FILE, 'w', encoding='utf-8') as f:
        json.dump(metadata, f, ensure_ascii=False, indent=2)

def _count_window_folders(order_dir: Path) -> int:
    if not order_dir.exists():
        return 0
    return len([d for d in order_dir.iterdir() if d.is_dir() and d.name.startswith("Окно ")])

# --- API ЭНДПОИНТЫ ---

@app.get("/api/check-order/{order_number}")
async def check_order(order_number: str):
    metadata = load_metadata()
    exists = order_number in metadata
    windows_count = 0
    if exists:
        order_dir = UPLOAD_DIR / order_number
        actual = _count_window_folders(order_dir)
        windows_count = metadata[order_number].get("window_count", 0)
        # fallback для старых заказов, созданных до появления window_count
        if windows_count == 0:
            windows_count = metadata[order_number].get("total_count", 0)
        windows_count = max(windows_count, actual)
    return {"exists": exists, "windows_count": windows_count}

@app.post("/api/upload")
async def upload_files(
    order_number: str = Form(...),
    count: int = Form(0),
    window_number: int = Form(1),
    append_mode: bool = Form(False),
    files: List[UploadFile] = File(...)
):
    try:
        order_dir = UPLOAD_DIR / order_number
        order_dir.mkdir(parents=True, exist_ok=True)

        window_dir = order_dir / f"Окно {window_number}"
        window_dir.mkdir(exist_ok=True)

        uploaded_files = []
        for file in files:
            file_path = window_dir / file.filename
            with open(file_path, "wb") as buffer:
                shutil.copyfileobj(file.file, buffer)
            uploaded_files.append(file.filename)

        metadata = load_metadata()
        timestamp = datetime.now().isoformat()

        if order_number in metadata:
            if not append_mode:
                metadata[order_number]['total_count'] += count
                metadata[order_number]['in_transit'] += count
            actual = _count_window_folders(order_dir)
            current_window_count = metadata[order_number].get('window_count', actual)
            metadata[order_number]['window_count'] = max(current_window_count, actual, window_number)
            metadata[order_number]['files'].extend(uploaded_files)
            metadata[order_number]['updated_at'] = timestamp
            metadata[order_number]['files_count'] = len(metadata[order_number]['files'])
        else:
            for i in range(1, count + 1):
                (order_dir / f"Окно {i}").mkdir(exist_ok=True)

            actual = _count_window_folders(order_dir)
            metadata[order_number] = {
                "order_number": order_number,
                "created_at": timestamp,
                "updated_at": timestamp,
                "total_count": count,
                "delivered": 0,
                "in_transit": count,
                "damaged": 0,
                "issues": 0,
                "notes": "",
                "files": uploaded_files,
                "files_count": len(uploaded_files),
                "window_count": max(count, actual, window_number)
            }
        save_metadata(metadata)
        return {"success": True}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/orders")
async def get_orders():
    metadata = load_metadata()
    orders = list(metadata.values())
    orders.sort(key=lambda x: x['created_at'], reverse=True)
    return {"orders": orders, "total": len(orders)}

@app.put("/api/orders/{order_number}")
async def update_order_stats(
    order_number: str,
    total_count: int = Form(0),
    delivered: int = Form(0),
    in_transit: int = Form(0),
    damaged: int = Form(0),
    issues: int = Form(0),
    notes: str = Form("")
):
    metadata = load_metadata()
    if order_number not in metadata:
        raise HTTPException(status_code=404, detail="Заказ не найден")
    order = metadata[order_number]
    order['total_count'] = total_count
    order['delivered'] = delivered
    order['in_transit'] = in_transit
    order['damaged'] = damaged
    order['issues'] = issues
    order['notes'] = notes
    order['updated_at'] = datetime.now().isoformat()
    save_metadata(metadata)
    return {"success": True}

@app.delete("/api/orders/{order_number}")
async def delete_order(order_number: str):
    metadata = load_metadata()
    if order_number in metadata:
        order_dir = UPLOAD_DIR / order_number
        if order_dir.exists():
            shutil.rmtree(order_dir)
        del metadata[order_number]
        save_metadata(metadata)
    return {"success": True}

@app.get("/api/health")
async def health_check():
    return {"status": "ok", "orders_count": len(load_metadata())}

@app.get("/api/version")
async def get_version():
    return {"version": "1.0.0", "download_url": "https://github.com/KiTiKeT9/allegra-orders/releases/latest/download/Allegra-Scanner.apk"}

# --- МОНТИРОВАНИЕ ВЕБ-ИНТЕРФЕЙСА ---

if WEB_DIR.exists():
    app.mount("/", StaticFiles(directory=str(WEB_DIR), html=True), name="web")
    print(f"✅ Веб-интерфейс подключен из: {WEB_DIR}")
else:
    print(f"⚠️ Папка web не найдена по пути: {WEB_DIR}")

if __name__ == "__main__":
    import uvicorn
    UPLOAD_DIR.mkdir(exist_ok=True)
    uvicorn.run(app, host="0.0.0.0", port=8000, limit_max_requests=None, timeout_keep_alive=120)
