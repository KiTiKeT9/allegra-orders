from fastapi import FastAPI, UploadFile, File, Form, HTTPException, Request, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from starlette.middleware.base import BaseHTTPMiddleware
from typing import List, Optional
from pydantic import BaseModel, Field
import os
import shutil
import logging
import tempfile
from datetime import datetime
import json
from pathlib import Path
from filelock import FileLock

logger = logging.getLogger("allegra-server")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

MAX_UPLOAD_SIZE = 500 * 1024 * 1024
LOCK_PATH = Path(__file__).parent / "metadata.lock"
meta_lock = FileLock(str(LOCK_PATH), timeout=30)

class MaxBodySizeMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        if request.method == "POST" and "/api/upload" in str(request.url):
            request._body = await request.body()
        response = await call_next(request)
        return response

class UploadForm(BaseModel):
    order_number: str = Field(..., min_length=1, max_length=50)
    count: int = Field(default=0, ge=0, le=9999)
    window_number: int = Field(default=1, ge=1, le=9999)
    append_mode: bool = False

class UpdateStatsForm(BaseModel):
    total_count: int = Field(default=0, ge=0, le=999999)
    delivered: int = Field(default=0, ge=0, le=999999)
    in_transit: int = Field(default=0, ge=0, le=999999)
    damaged: int = Field(default=0, ge=0, le=999999)
    issues: int = Field(default=0, ge=0, le=999999)
    notes: str = Field(default="", max_length=1000)

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
    try:
        if not METADATA_FILE.exists():
            return {}
        with open(METADATA_FILE, 'r', encoding='utf-8') as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        logger.error(f"Ошибка чтения metadata.json (повреждён): {e}")
        return {}
    except FileNotFoundError:
        return {}
    except Exception as e:
        logger.error(f"Неожиданная ошибка при чтении metadata.json: {e}")
        return {}

def save_metadata(metadata):
    try:
        tmp = tempfile.NamedTemporaryFile(
            mode='w',
            encoding='utf-8',
            dir=METADATA_FILE.parent,
            delete=False,
            suffix='.tmp'
        )
        try:
            json.dump(metadata, tmp, ensure_ascii=False, indent=2)
            tmp.flush()
            os.fsync(tmp.fileno())
        finally:
            tmp.close()
        os.replace(tmp.name, METADATA_FILE)
    except Exception as e:
        logger.error(f"Ошибка записи metadata.json: {e}")
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)
        raise

def _count_window_folders(order_dir: Path) -> int:
    if not order_dir.exists():
        return 0
    return len([d for d in order_dir.iterdir() if d.is_dir() and d.name.startswith("Окно ")])

# --- API ЭНДПОИНТЫ ---

@app.get("/api/check-order/{order_number}")
async def check_order(order_number: str):
    with meta_lock:
        metadata = load_metadata()
        exists = order_number in metadata
        windows_count = 0
        if exists:
            order_dir = UPLOAD_DIR / order_number
            actual = _count_window_folders(order_dir)
            windows_count = metadata[order_number].get("window_count", 0)
            if windows_count == 0:
                windows_count = metadata[order_number].get("total_count", 0)
            windows_count = max(windows_count, actual)
    return {"exists": exists, "windows_count": windows_count}

async def validate_upload_form(
    order_number: str = Form(...),
    count: int = Form(0),
    window_number: int = Form(1),
    append_mode: bool = Form(False),
) -> UploadForm:
    try:
        return UploadForm(
            order_number=order_number,
            count=count,
            window_number=window_number,
            append_mode=append_mode,
        )
    except Exception as e:
        raise HTTPException(status_code=422, detail=f"Валидация не пройдена: {e}")

@app.post("/api/upload")
async def upload_files(
    form: UploadForm = Depends(validate_upload_form),
    files: List[UploadFile] = File(...),
):
    try:
        order_dir = UPLOAD_DIR / form.order_number
        order_dir.mkdir(parents=True, exist_ok=True)

        window_dir = order_dir / f"Окно {form.window_number}"
        window_dir.mkdir(exist_ok=True)

        uploaded_files = []
        for file in files:
            file_path = window_dir / file.filename
            try:
                with open(file_path, "wb") as buffer:
                    shutil.copyfileobj(file.file, buffer)
            finally:
                await file.close()
            uploaded_files.append(file.filename)

        with meta_lock:
            metadata = load_metadata()
            timestamp = datetime.now().isoformat()

            if form.order_number in metadata:
                if not form.append_mode:
                    metadata[form.order_number]['total_count'] += form.count
                    metadata[form.order_number]['in_transit'] += form.count
                actual = _count_window_folders(order_dir)
                current_window_count = metadata[form.order_number].get('window_count', actual)
                metadata[form.order_number]['window_count'] = max(current_window_count, actual, form.window_number)
                metadata[form.order_number]['files'].extend(uploaded_files)
                metadata[form.order_number]['updated_at'] = timestamp
                metadata[form.order_number]['files_count'] = len(metadata[form.order_number]['files'])
            else:
                for i in range(1, form.count + 1):
                    (order_dir / f"Окно {i}").mkdir(exist_ok=True)

                actual = _count_window_folders(order_dir)
                metadata[form.order_number] = {
                    "order_number": form.order_number,
                    "created_at": timestamp,
                    "updated_at": timestamp,
                    "total_count": form.count,
                    "delivered": 0,
                    "in_transit": form.count,
                    "damaged": 0,
                    "issues": 0,
                    "notes": "",
                    "files": uploaded_files,
                    "files_count": len(uploaded_files),
                    "window_count": max(form.count, actual, form.window_number)
                }
            save_metadata(metadata)
        return {"success": True}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Upload error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/orders")
async def get_orders():
    with meta_lock:
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
    try:
        form = UpdateStatsForm(
            total_count=total_count,
            delivered=delivered,
            in_transit=in_transit,
            damaged=damaged,
            issues=issues,
            notes=notes,
        )
    except Exception as e:
        raise HTTPException(status_code=422, detail=f"Ошибка валидации: {e}")

    with meta_lock:
        metadata = load_metadata()
        if order_number not in metadata:
            raise HTTPException(status_code=404, detail="Заказ не найден")
        order = metadata[order_number]
        order['total_count'] = form.total_count
        order['delivered'] = form.delivered
        order['in_transit'] = form.in_transit
        order['damaged'] = form.damaged
        order['issues'] = form.issues
        order['notes'] = form.notes
        order['updated_at'] = datetime.now().isoformat()
        save_metadata(metadata)
    return {"success": True}

@app.delete("/api/orders/{order_number}")
async def delete_order(order_number: str):
    with meta_lock:
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
    with meta_lock:
        count = len(load_metadata())
    return {"status": "ok", "orders_count": count}

@app.get("/api/version")
async def get_version():
    return {"version": "1.0.0", "download_url": "https://github.com/KiTiKeT9/allegra-orders/releases/latest/download/Allegra-Scanner.apk"}

@app.get("/api/disk-info")
async def get_disk_info():
    total, used, free = shutil.disk_usage(UPLOAD_DIR.anchor)
    folder_size = 0
    if UPLOAD_DIR.exists():
        for dirpath, dirnames, filenames in os.walk(UPLOAD_DIR):
            for f in filenames:
                fp = os.path.join(dirpath, f)
                folder_size += os.path.getsize(fp)
    return {
        "total": round(total / (1024**3), 2),
        "used": round(used / (1024**3), 2),
        "free": round(free / (1024**3), 2),
        "folderSize": round(folder_size / (1024**3), 2),
        "percentUsed": round((used / total) * 100) if total > 0 else 0
    }

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
