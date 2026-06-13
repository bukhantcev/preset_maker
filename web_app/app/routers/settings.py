from fastapi import APIRouter, Depends, HTTPException, Request, Form
from fastapi.responses import RedirectResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session
import json
import httpx
import paramiko
from .. import database, models, core_logic
from ..core_logic import PARTITURA_DEFAULT_FIELDS
from ..cloud_sync import ROOT_FOLDER

router = APIRouter()
templates = Jinja2Templates(directory="app/templates")

def get_current_user(request: Request, db: Session):
    user_data = request.session.get("user")
    if not user_data:
        raise HTTPException(status_code=401, detail="Not authenticated")
    return db.query(models.User).filter(models.User.id == user_data["id"]).first()

async def check_cloud_connection(user: models.User) -> tuple[bool, str]:
    if user.storage_mode == "temp":
        return False, "Облако не выбрано"

    if user.storage_mode == "sftp":
        if not user.sftp_config:
            return False, "Нужны настройки SFTP"
        try:
            config = json.loads(user.sftp_config)
            ssh = paramiko.SSHClient()
            ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            ssh.connect(
                config["host"],
                port=int(config.get("port", 22)),
                username=config["username"],
                password=config.get("password"),
                timeout=10
            )
            sftp = ssh.open_sftp()
            try:
                sftp.stat(ROOT_FOLDER)
            except FileNotFoundError:
                sftp.mkdir(ROOT_FOLDER)
            sftp.close()
            ssh.close()
            return True, "Облако подключено"
        except Exception as exc:
            return False, f"SFTP не подключен: {exc}"

    if user.storage_mode == "yandex_disk":
        token = user.yandex_manual_token
        if not token and user.yandex_disk_token:
            try:
                token = json.loads(user.yandex_disk_token).get("access_token")
            except (json.JSONDecodeError, TypeError):
                token = user.yandex_disk_token
        if not token:
            return False, "Нужно подключить Яндекс.Диск"
        headers = {"Authorization": f"OAuth {token}"}
        try:
            async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
                await client.put(
                    "https://cloud-api.yandex.net/v1/disk/resources",
                    params={"path": f"app:/{ROOT_FOLDER}"},
                    headers=headers
                )
                resp = await client.get(
                    "https://cloud-api.yandex.net/v1/disk/resources",
                    params={"path": f"app:/{ROOT_FOLDER}"},
                    headers=headers
                )
            if resp.status_code == 200:
                return True, "Облако подключено"
            return False, f"Яндекс.Диск не подключен: {resp.status_code}"
        except Exception as exc:
            return False, f"Яндекс.Диск не подключен: {exc}"

    return False, "Неизвестный тип облака"

@router.get("/")
async def view_settings(request: Request, db: Session = Depends(database.get_db)):
    user = get_current_user(request, db)
    sftp_data = json.loads(user.sftp_config) if user.sftp_config else {}
    cloud_ok, cloud_message = await check_cloud_connection(user)
    
    # Load custom fields or use defaults
    if user.partitura_fields:
        fields = json.loads(user.partitura_fields)
    else:
        fields = [{"field_id": f.field_id, "title": f.title, "enabled": f.enabled} for f in PARTITURA_DEFAULT_FIELDS]
        
    return templates.TemplateResponse(request, "settings.html", {
        "user": user, 
        "sftp": sftp_data,
        "cloud_ok": cloud_ok,
        "cloud_message": cloud_message,
        "fields": fields,
        "all_field_ids": [f.field_id for f in PARTITURA_DEFAULT_FIELDS]
    })

@router.post("/partitura_fields")
async def update_partitura_fields(request: Request, fields_json: str = Form(...), db: Session = Depends(database.get_db)):
    user = get_current_user(request, db)
    # Validate JSON
    try:
        parsed = json.loads(fields_json)
        user.partitura_fields = json.dumps(parsed)
        db.commit()
    except:
        raise HTTPException(status_code=400, detail="Invalid fields configuration")
    return RedirectResponse(url="/settings", status_code=303)

@router.post("/storage")
async def update_storage_mode(request: Request, storage_mode: str = Form(...), db: Session = Depends(database.get_db)):
    user = get_current_user(request, db)
    user.storage_mode = storage_mode
    db.commit()
    return RedirectResponse(url="/settings", status_code=303)

@router.post("/yandex_token")
async def update_yandex_token(request: Request, token: str = Form(...), db: Session = Depends(database.get_db)):
    user = get_current_user(request, db)
    user.yandex_manual_token = token
    user.storage_mode = "yandex_disk"
    db.commit()
    return RedirectResponse(url="/settings", status_code=303)

@router.post("/yandex_disconnect")
async def disconnect_yandex_disk(request: Request, db: Session = Depends(database.get_db)):
    user = get_current_user(request, db)
    user.yandex_manual_token = None
    user.yandex_disk_token = None
    if user.storage_mode == "yandex_disk":
        user.storage_mode = "temp"
    db.commit()
    return RedirectResponse(url="/settings?msg=Яндекс.Диск%20отключен", status_code=303)

@router.post("/sftp")
async def update_sftp_config(
    request: Request, 
    host: str = Form(...), 
    port: int = Form(22), 
    username: str = Form(...), 
    password: str = Form(""), 
    remote_dir: str = Form("MA2_passports"),
    db: Session = Depends(database.get_db)
):
    user = get_current_user(request, db)
    sftp_config = {
        "host": host,
        "port": port,
        "username": username,
        "password": password,
        "remote_dir": remote_dir
    }
    user.sftp_config = json.dumps(sftp_config)
    user.storage_mode = "sftp"
    db.commit()
    return RedirectResponse(url="/settings", status_code=303)
