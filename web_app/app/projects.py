from fastapi import APIRouter, Depends, HTTPException, Request, UploadFile, File, Form, Response
from fastapi.responses import HTMLResponse, RedirectResponse, FileResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session
import os
import shutil
import json
import httpx
import paramiko
from pathlib import Path
from datetime import datetime, timezone, timedelta
from .. import database, models
from ..core_logic import (
    parse_grandma2_presets, load_passport_rows, PassportRow, 
    create_passport_xlsx, create_passport_pdf, safe_filename, 
    parse_partitura, PartituraField, create_partitura_xlsx, 
    create_partitura_pdf, PARTITURA_DEFAULT_FIELDS, PartituraRow
)
from ..cloud_sync import sync_to_cloud, list_cloud_projects, get_cloud_files, download_from_cloud, delete_cloud_project, rename_cloud_project

router = APIRouter()
templates = Jinja2Templates(directory="app/templates")
SERVER_RETENTION_HOURS = 12
PROJECT_META_FILE = "server_project_meta.json"

def get_current_user(request: Request):
    user = request.session.get("user")
    if not user: raise HTTPException(status_code=401)
    return user

def get_db_user(request: Request, db: Session):
    ud = get_current_user(request)
    return db.query(models.User).filter(models.User.id == ud["id"]).first()

def user_temp_dir(user_id: int):
    path = Path(f"/tmp/passport_creator/users/{user_id}/projects")
    path.mkdir(parents=True, exist_ok=True)
    return path

def project_server_created_at(project_dir: Path) -> datetime:
    meta_path = project_dir / PROJECT_META_FILE
    if meta_path.exists():
        try:
            with open(meta_path, "r", encoding="utf-8") as f:
                created_at = json.load(f).get("created_at")
            if created_at:
                parsed = datetime.fromisoformat(created_at)
                return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
        except (OSError, json.JSONDecodeError, ValueError):
            pass
    write_project_server_meta(project_dir)
    return datetime.now(timezone.utc)

def write_project_server_meta(project_dir: Path) -> None:
    meta_path = project_dir / PROJECT_META_FILE
    if meta_path.exists():
        return
    with open(meta_path, "w", encoding="utf-8") as f:
        json.dump({"created_at": datetime.now(timezone.utc).isoformat()}, f, ensure_ascii=False, indent=2)

def project_expires_at(project_dir: Path) -> datetime:
    return project_server_created_at(project_dir) + timedelta(hours=SERVER_RETENTION_HOURS)

def project_remaining_text(project_dir: Path) -> str:
    remaining = project_expires_at(project_dir) - datetime.now(timezone.utc)
    seconds = max(0, int(remaining.total_seconds()))
    hours, rest = divmod(seconds, 3600)
    minutes = rest // 60
    if hours:
        return f"{hours} ч {minutes:02d} мин"
    return f"{minutes} мин"

def cleanup_expired_projects(user_id: int) -> None:
    root = user_temp_dir(user_id)
    now = datetime.now(timezone.utc)
    for project_dir in root.iterdir():
        if not project_dir.is_dir():
            continue
        try:
            if project_expires_at(project_dir) <= now:
                shutil.rmtree(project_dir)
        except OSError:
            pass

def project_base_name(project_name: str) -> str:
    return project_name[:-9] if project_name.endswith("_passport") else project_name

def project_dir_name(title: str) -> str:
    safe = safe_filename(title)
    return safe if safe.endswith("_passport") else f"{safe}_passport"

def project_dir_for(user_id: int, project_name: str) -> Path:
    root = user_temp_dir(user_id)
    direct = root / project_name
    if direct.exists():
        return direct
    if project_name.endswith("_passport"):
        legacy = root / project_base_name(project_name)
        if legacy.exists():
            return legacy
    else:
        modern = root / project_dir_name(project_name)
        if modern.exists():
            return modern
    return direct

def find_project_xml(project_dir: Path, base_name: str = "") -> Path | None:
    if base_name:
        preferred = project_dir / f"{safe_filename(base_name)}.xml"
        if preferred.exists():
            return preferred
    xmls = sorted(p for p in project_dir.iterdir() if p.is_file() and p.suffix.lower() == ".xml")
    return xmls[0] if xmls else None

def normalize_photo_path(project_dir: Path, value: str | None) -> str:
    if not value:
        return ""
    path = Path(value)
    if path.exists():
        return str(path)
    candidate = project_dir / "photos" / path.name
    return str(candidate) if candidate.exists() else ""

def row_photo_name(row: dict) -> str | None:
    value = row.get("photo_path") or row.get("photoName") or ""
    name = Path(str(value)).name if value else ""
    return name or None

def write_passport_state(project_dir: Path, data: dict) -> None:
    state_rows = []
    for row in data.get("rows", []):
        state_rows.append({
            "presetLabel": row.get("preset_label", row.get("presetLabel", "")),
            "fixtureId": row.get("fixture_id", row.get("fixtureId", "")),
            "presetNo": row.get("preset_no", row.get("presetNo", "")),
            "photoName": row_photo_name(row),
            "description": row.get("description", "")
        })
    with open(project_dir / "passport_state.json", "w", encoding="utf-8") as f:
        json.dump({"rows": state_rows}, f, ensure_ascii=False, indent=2)

def read_passport_state(project_dir: Path) -> list[PassportRow]:
    state_path = project_dir / "passport_state.json"
    if not state_path.exists():
        return []
    try:
        with open(state_path, "r", encoding="utf-8") as f:
            raw = json.load(f)
    except (OSError, json.JSONDecodeError):
        return []
    rows = []
    for item in raw.get("rows", []):
        photo_name = item.get("photoName")
        photo_path = project_dir / "photos" / photo_name if photo_name else None
        rows.append(PassportRow(
            item.get("presetLabel", ""),
            item.get("fixtureId", ""),
            item.get("presetNo", ""),
            photo_path if photo_path and photo_path.exists() else None,
            item.get("description", "")
        ))
    return rows

def write_project_json(project_dir: Path, data: dict) -> None:
    with open(project_dir / "project.json", "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    write_passport_state(project_dir, data)

def build_project_data(project_dir: Path, project_name: str) -> dict:
    base_name = project_base_name(project_name)
    xml_path = find_project_xml(project_dir, base_name)
    if xml_path is None:
        raise HTTPException(status_code=404, detail="XML not found")

    items = parse_grandma2_presets(xml_path)
    state_rows = read_passport_state(project_dir)
    if state_rows:
        has_table = any(project_dir.glob("*_пресеты.xlsx"))
        table_rows, _ = load_passport_rows(items, project_dir, base_name) if has_table else ([], None)
        table_by_occurrence = {}
        table_counts = {}
        for table_row in table_rows:
            key = (table_row.preset_label, table_row.fixture_id)
            occurrence = table_counts.get(key, 0)
            table_counts[key] = occurrence + 1
            table_by_occurrence[(key, occurrence)] = table_row

        item_by_group = {(item.preset_label, item.fixture_id): item for item in items}
        rows = []
        used_table_rows = set()
        state_counts = {}
        for row in state_rows:
            item = item_by_group.get((row.preset_label, row.fixture_id))
            if item and not row.preset_no:
                row.preset_no = item.preset_no
            key = (row.preset_label, row.fixture_id)
            occurrence = state_counts.get(key, 0)
            state_counts[key] = occurrence + 1
            table_row = table_by_occurrence.get((key, occurrence))
            if table_row:
                row.description = table_row.description
                used_table_rows.add((key, occurrence))
            rows.append(row)
        table_counts.clear()
        for table_row in table_rows:
            key = (table_row.preset_label, table_row.fixture_id)
            occurrence = table_counts.get(key, 0)
            table_counts[key] = occurrence + 1
            if (key, occurrence) not in used_table_rows and (table_row.photo_path or table_row.description):
                rows.append(table_row)
        existing = {(row.preset_label, row.fixture_id) for row in rows}
        for item in items:
            if (item.preset_label, item.fixture_id) not in existing:
                rows.append(PassportRow(item.preset_label, item.fixture_id, item.preset_no))
    else:
        rows, _ = load_passport_rows(items, project_dir, base_name)

    part_rows = parse_partitura(xml_path)
    return {
        "title": base_name,
        "xml_file": xml_path.name,
        "rows": [
            {
                "preset_label": r.preset_label,
                "fixture_id": r.fixture_id,
                "preset_no": r.preset_no,
                "photo_path": str(r.photo_path) if r.photo_path else "",
                "description": r.description
            }
            for r in rows
        ],
        "partitura": [
            {
                "number": r.number,
                "name": r.name,
                "fade": r.fade,
                "downfade": r.downfade,
                "delay": r.delay,
                "trigger": r.trigger,
                "trigger_time": r.trigger_time,
                "info": r.info,
                "command": r.command
            }
            for r in part_rows
        ]
    }

def load_project_data(project_dir: Path, project_name: str) -> dict:
    json_path = project_dir / "project.json"
    if json_path.exists() and json_path.stat().st_size > 0:
        with open(json_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        base_name = project_base_name(project_name)
        data["title"] = project_base_name(data.get("title") or base_name)
        xml_path = find_project_xml(project_dir, data["title"])
        if xml_path:
            data["xml_file"] = xml_path.name
            items = parse_grandma2_presets(xml_path)
            item_by_group = {(item.preset_label, item.fixture_id): item for item in items}
            has_table = any(project_dir.glob("*_пресеты.xlsx"))
            table_rows, _ = load_passport_rows(items, project_dir, data["title"]) if has_table else ([], None)
            table_counts = {}
            table_by_occurrence = {}
            for table_row in table_rows:
                key = (table_row.preset_label, table_row.fixture_id)
                occurrence = table_counts.get(key, 0)
                table_counts[key] = occurrence + 1
                table_by_occurrence[(key, occurrence)] = table_row

            json_counts = {}
            used_table_rows = set()
            for row in data.get("rows", []):
                key = (row.get("preset_label", ""), row.get("fixture_id", ""))
                item = item_by_group.get(key)
                if item and not row.get("preset_no"):
                    row["preset_no"] = item.preset_no
                occurrence = json_counts.get(key, 0)
                json_counts[key] = occurrence + 1
                table_row = table_by_occurrence.get((key, occurrence))
                if table_row:
                    row["description"] = table_row.description
                    if table_row.photo_path:
                        row["photo_path"] = str(table_row.photo_path)
                    used_table_rows.add((key, occurrence))

            table_counts.clear()
            for table_row in table_rows:
                key = (table_row.preset_label, table_row.fixture_id)
                occurrence = table_counts.get(key, 0)
                table_counts[key] = occurrence + 1
                if (key, occurrence) not in used_table_rows and (table_row.photo_path or table_row.description):
                    data.setdefault("rows", []).append({
                        "preset_label": table_row.preset_label,
                        "fixture_id": table_row.fixture_id,
                        "preset_no": table_row.preset_no,
                        "photo_path": str(table_row.photo_path) if table_row.photo_path else "",
                        "description": table_row.description
                    })

            existing = {(row.get("preset_label", ""), row.get("fixture_id", "")) for row in data.get("rows", [])}
            for item in items:
                if (item.preset_label, item.fixture_id) not in existing:
                    data.setdefault("rows", []).append({
                        "preset_label": item.preset_label,
                        "fixture_id": item.fixture_id,
                        "preset_no": item.preset_no,
                        "photo_path": "",
                        "description": ""
                    })
        for row in data.get("rows", []):
            row["photo_path"] = normalize_photo_path(project_dir, row.get("photo_path"))
        write_project_json(project_dir, data)
        return data
    data = build_project_data(project_dir, project_name)
    write_project_json(project_dir, data)
    return data

def unique_photo_path(project_dir: Path, rows: list[dict], index: int) -> Path:
    row = rows[index]
    stem = safe_filename(f"{row.get('preset_no') or row.get('preset_label', '')}_{row.get('fixture_id', '')}")
    duplicate = 1
    key = (row.get("preset_label", ""), row.get("fixture_id", ""))
    for i in range(index):
        other = rows[i]
        if (other.get("preset_label", ""), other.get("fixture_id", "")) == key:
            duplicate += 1
    photo_dir = project_dir / "photos"
    photo_dir.mkdir(exist_ok=True)
    base = photo_dir / (f"{stem}.jpg" if duplicate == 1 else f"{stem}_{duplicate}.jpg")
    if not base.exists():
        return base
    counter = max(duplicate + 1, 2)
    while True:
        candidate = photo_dir / f"{stem}_{counter}.jpg"
        if not candidate.exists():
            return candidate
        counter += 1

@router.post("/create")
async def create_project(request: Request, title: str = Form(...), xml_file: UploadFile = File(...), db: Session = Depends(database.get_db)):
    user = get_db_user(request, db)
    safe_title = safe_filename(title)
    project_name = project_dir_name(safe_title)
    project_dir = user_temp_dir(user.id) / project_name
    
    legacy_project_dir = user_temp_dir(user.id) / safe_title
    if (project_dir.exists() and (project_dir / "project.json").exists()) or (legacy_project_dir.exists() and (legacy_project_dir / "project.json").exists()):
        return RedirectResponse(url=f"/?msg=Проект%20с%20таким%20именем%20уже%20редактируется", status_code=303)

    project_dir.mkdir(parents=True, exist_ok=True)
    write_project_server_meta(project_dir)
    
    if not xml_file.filename.endswith('.xml'):
        raise HTTPException(status_code=400, detail="Only XML files allowed")
    
    xml_path = project_dir / f"{safe_title}.xml"
    with open(xml_path, "wb") as buffer: shutil.copyfileobj(xml_file.file, buffer)
    
    items = parse_grandma2_presets(xml_path)
    rows, _ = load_passport_rows(items, project_dir, safe_title)
    part_rows = parse_partitura(xml_path)
    
    project_data = {
        "title": safe_title,
        "xml_file": xml_path.name,
        "rows": [{"preset_label": r.preset_label, "fixture_id": r.fixture_id, "preset_no": r.preset_no, "photo_path": str(r.photo_path) if r.photo_path else "", "description": r.description} for r in rows],
        "partitura": [{"number": r.number, "name": r.name, "fade": r.fade, "downfade": r.downfade, "delay": r.delay, "trigger": r.trigger, "trigger_time": r.trigger_time, "info": r.info, "command": r.command} for r in part_rows]
    }
    
    write_project_json(project_dir, project_data)
    
    return RedirectResponse(url=f"/projects/{project_name}/presets", status_code=303)

@router.get("/cloud/list")
async def cloud_list(request: Request, db: Session = Depends(database.get_db)):
    user = get_db_user(request, db)
    return await list_cloud_projects(user)

@router.get("/cloud/{project_name}/files")
async def cloud_files(project_name: str, request: Request, db: Session = Depends(database.get_db)):
    user = get_db_user(request, db)
    return await get_cloud_files(user, project_name)

@router.post("/{project_name}/save_to_cloud")
async def save_to_cloud_manual(project_name: str, request: Request, db: Session = Depends(database.get_db)):
    user = get_db_user(request, db)
    project_dir = project_dir_for(user.id, project_name)
    data = load_project_data(project_dir, project_name)
    cloud_project_name = project_dir.name
    
    # 1. Load sync metadata for INCREMENTAL sync (mostly for photos)
    sync_meta_path = project_dir / ".sync_metadata.json"
    sync_meta = {}
    if sync_meta_path.exists():
        try:
            with open(sync_meta_path, "r") as f: sync_meta = json.load(f)
        except: pass
    
    def needs_sync(file_p: Path):
        mtime = os.path.getmtime(file_p)
        return sync_meta.get(file_p.name) != mtime

    # 2. ALWAYS sync core files (JSON, XML) to ensure state is fresh
    json_path = project_dir / "project.json"
    if json_path.exists():
        await sync_to_cloud(user, json_path, cloud_project_name)
        sync_meta[json_path.name] = os.path.getmtime(json_path)
    state_path = project_dir / "passport_state.json"
    if state_path.exists():
        await sync_to_cloud(user, state_path, cloud_project_name)
        sync_meta[state_path.name] = os.path.getmtime(state_path)
    
    xml_p = project_dir / data["xml_file"]
    if xml_p.exists():
        await sync_to_cloud(user, xml_p, cloud_project_name)
        sync_meta[xml_p.name] = os.path.getmtime(xml_p)
    
    # 3. Incremental sync for photos (only if changed)
    # Sync photos
    p_dir = project_dir / "photos"
    if p_dir.exists():
        photo_list = list(p_dir.iterdir())
        print(f"DEBUG: Syncing {len(photo_list)} photos for project {project_name}")
        for p in photo_list:
            if p.is_file():
                await sync_to_cloud(user, p, cloud_project_name)
                sync_meta[p.name] = os.path.getmtime(p)

    # 4. ALWAYS sync documents (PDF/XLSX) to cloud
    for f in project_dir.iterdir():
        if f.suffix in [".pdf", ".xlsx"]:
            await sync_to_cloud(user, f, cloud_project_name)
            sync_meta[f.name] = os.path.getmtime(f)
            
    # Save updated metadata
    with open(sync_meta_path, "w") as f: json.dump(sync_meta, f)
        
    return {"status": "ok"}

@router.post("/{project_name}/restore_from_cloud")
async def restore_cloud(project_name: str, request: Request, db: Session = Depends(database.get_db)):
    user = get_db_user(request, db)
    local_project_name = project_name if project_name.endswith("_passport") else project_dir_name(project_name)
    project_dir = user_temp_dir(user.id) / local_project_name
    await download_from_cloud(user, project_name, project_dir)
    write_project_server_meta(project_dir)
    data = load_project_data(project_dir, local_project_name)
    write_project_json(project_dir, data)
    # After download, mark everything as synced
    sync_meta = {}
    for f in project_dir.rglob("*"):
        if f.is_file(): sync_meta[f.name] = os.path.getmtime(f)
    with open(project_dir / ".sync_metadata.json", "w") as f: json.dump(sync_meta, f)
    return {"status": "ok"}

@router.post("/cloud/{project_name}/delete")
async def delete_cloud(project_name: str, request: Request, db: Session = Depends(database.get_db)):
    user = get_db_user(request, db)
    await delete_cloud_project(user, project_name)
    return {"status": "ok"}

@router.post("/cloud/{project_name}/rename")
async def rename_cloud(project_name: str, request: Request, new_name: str = Form(...), db: Session = Depends(database.get_db)):
    user = get_db_user(request, db)
    await rename_cloud_project(user, project_name, project_dir_name(new_name))
    return {"status": "ok"}

@router.get("/{project_name}/files")
async def local_files(project_name: str, request: Request):
    ud = get_current_user(request)
    p_dir = project_dir_for(ud["id"], project_name)
    if not p_dir.exists(): return []
    files = [f.name for f in p_dir.iterdir() if f.is_file() and f.suffix in [".pdf", ".xlsx"]]
    return sorted(files)

from urllib.parse import quote

@router.get("/cloud/{project_name}/download/{file_name}")
async def download_cloud_file(project_name: str, file_name: str, request: Request, db: Session = Depends(database.get_db)):
    user = get_db_user(request, db)
    if user.storage_mode == "yandex_disk":
        token = user.yandex_manual_token or (json.loads(user.yandex_disk_token).get("access_token") if user.yandex_disk_token else None)
        if not token: raise HTTPException(status_code=401)
        headers = {"Authorization": f"OAuth {token}"}
        async with httpx.AsyncClient(timeout=60.0, follow_redirects=True) as client:
            remote_path = f"app:/MA2_passports/{project_name}/{file_name}"
            resp = await client.get(f"https://cloud-api.yandex.net/v1/disk/resources/download?path={remote_path}", headers=headers)
            if resp.status_code == 200:
                href = resp.json()["href"]
                async with httpx.AsyncClient(timeout=60.0, follow_redirects=True) as dl_client:
                    file_resp = await dl_client.get(href)
                if file_resp.status_code != 200:
                    raise HTTPException(status_code=502, detail="Failed to fetch file bytes from cloud")
                encoded_filename = quote(file_name)
                return Response(content=file_resp.content, media_type="application/octet-stream", headers={"Content-Disposition": f"attachment; filename*=UTF-8''{encoded_filename}"})
    
    elif user.storage_mode == "sftp" and user.sftp_config:
        try:
            import io
            config = json.loads(user.sftp_config)
            ssh = paramiko.SSHClient()
            ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            ssh.connect(config["host"], port=int(config.get("port", 22)), username=config["username"], password=config.get("password"), timeout=15)
            sftp = ssh.open_sftp()
            
            remote_path = f"MA2_passports/{project_name}/{file_name}"
            file_obj = io.BytesIO()
            sftp.getfo(remote_path, file_obj)
            sftp.close()
            ssh.close()
            
            file_obj.seek(0)
            encoded_filename = quote(file_name)
            return Response(
                content=file_obj.getvalue(),
                media_type="application/octet-stream",
                headers={"Content-Disposition": f"attachment; filename*=UTF-8''{encoded_filename}"}
            )
        except Exception as e:
            print(f"DEBUG: SFTP Cloud Download Error: {e}")
            raise HTTPException(status_code=404, detail="File not found on SFTP")

    raise HTTPException(status_code=404)

@router.post("/{project_name}/rename")
async def rename_local(request: Request, project_name: str, new_name: str = Form(...)):
    ud = get_current_user(request)
    old_safe = project_name
    new_base = safe_filename(new_name)
    new_safe = project_dir_name(new_base)
    
    user_dir = user_temp_dir(ud["id"])
    old_dir = project_dir_for(ud["id"], old_safe)
    new_dir = user_dir / new_safe
    old_base = project_base_name(old_dir.name)
    
    if old_dir.exists():
        # 1. Rename all files INSIDE the directory first
        for f in old_dir.iterdir():
            if f.is_file():
                if f.name.startswith(old_base):
                    new_fname = f.name.replace(old_base, new_base, 1)
                    f.rename(old_dir / new_fname)
        
        # 2. Rename the directory itself
        old_dir.rename(new_dir)
        
        # 3. Update project.json content
        json_path = new_dir / "project.json"
        if json_path.exists():
            with open(json_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            
            data["title"] = new_base
            # Update xml_file name if it was following the old name
            if data.get("xml_file"):
                old_xml = new_dir / data["xml_file"]
                new_xml = new_dir / f"{new_base}.xml"
                if old_xml.exists() and old_xml.name != new_xml.name:
                    old_xml.rename(new_xml)
                data["xml_file"] = new_xml.name if new_xml.exists() else data["xml_file"]
            
            # Update photo paths
            old_str, new_str = str(old_dir), str(new_dir)
            for row in data.get("rows", []):
                if row.get("photo_path"):
                    row["photo_path"] = row["photo_path"].replace(old_str, new_str)
            
            write_project_json(new_dir, data)
                
    return {"status": "ok"}

@router.post("/{project_name}/delete")
async def delete_local(request: Request, project_name: str):
    ud = get_current_user(request)
    p_dir = project_dir_for(ud["id"], project_name)
    if p_dir.exists(): shutil.rmtree(p_dir)
    return {"status": "ok"}

@router.get("/{project_name}/partitura_builder")
async def view_partitura_builder(request: Request, project_name: str, db: Session = Depends(database.get_db)):
    user = get_db_user(request, db)
    # Load custom fields or use defaults
    if user.partitura_fields:
        fields = json.loads(user.partitura_fields)
    else:
        fields = [{"field_id": f.field_id, "title": f.title, "enabled": f.enabled} for f in PARTITURA_DEFAULT_FIELDS]
        
    return templates.TemplateResponse(request, "partitura_builder.html", {
        "project_name": project_name,
        "fields": fields
    })

@router.post("/{project_name}/partitura_fields_save")
async def save_partitura_fields(request: Request, project_name: str, fields_json: str = Form(...), db: Session = Depends(database.get_db)):
    user = get_db_user(request, db)
    try:
        parsed = json.loads(fields_json)
        user.partitura_fields = json.dumps(parsed)
        db.commit()
    except:
        raise HTTPException(status_code=400, detail="Invalid fields configuration")
    return RedirectResponse(url=f"/projects/{project_name}/partitura", status_code=303)

@router.get("/{project_name}/presets")
async def view_presets(request: Request, project_name: str):
    ud = get_current_user(request)
    p_dir = project_dir_for(ud["id"], project_name)
    if not p_dir.exists():
        raise HTTPException(status_code=404, detail="Project missing")
    data = load_project_data(p_dir, project_name)
    return templates.TemplateResponse(request, "preset.html", {"project": data, "project_name": project_name})

@router.get("/{project_name}/partitura")
async def view_partitura(request: Request, project_name: str, db: Session = Depends(database.get_db)):
    user = get_db_user(request, db)
    p_dir = project_dir_for(user.id, project_name)
    if not p_dir.exists():
        raise HTTPException(status_code=404, detail="Project missing")
    data = load_project_data(p_dir, project_name)
    fields = [f for f in json.loads(user.partitura_fields) if f["enabled"]] if user.partitura_fields else [{"field_id": f.field_id, "title": f.title, "enabled": f.enabled} for f in PARTITURA_DEFAULT_FIELDS if f.enabled]
    return templates.TemplateResponse(request, "partitura.html", {"project": data, "project_name": project_name, "fields": fields})

@router.post("/{project_name}/update_partitura")
async def update_partitura_row(request: Request, project_name: str):
    ud = get_current_user(request)
    form = await request.form()
    idx = int(form.get("index"))
    p_dir = project_dir_for(ud["id"], project_name)
    data = load_project_data(p_dir, project_name)
    row = data["partitura"][idx]
    for k, v in form.items():
        if k != "index": row[k] = v
    write_project_json(p_dir, data)
    return {"status": "ok"}

@router.post("/{project_name}/add_partitura_row")
async def add_partitura_row(request: Request, project_name: str, index: int = Form(0)):
    ud = get_current_user(request)
    p_dir = project_dir_for(ud["id"], project_name)
    data = load_project_data(p_dir, project_name)
    new_row = {"number": "Новое", "name": "Реплика"}
    for field in PARTITURA_DEFAULT_FIELDS:
        if field.field_id not in new_row: new_row[field.field_id] = ""
    data["partitura"].insert(index + 1, new_row)
    write_project_json(p_dir, data)
    return {"status": "ok"}

@router.post("/{project_name}/delete_partitura_row")
async def delete_partitura_row(request: Request, project_name: str, index: int = Form(...)):
    ud = get_current_user(request)
    p_dir = project_dir_for(ud["id"], project_name)
    data = load_project_data(p_dir, project_name)
    if 0 <= index < len(data["partitura"]): data["partitura"].pop(index)
    write_project_json(p_dir, data)
    return {"status": "ok"}

@router.post("/{project_name}/upload_photo")
async def upload_photo(request: Request, project_name: str, index: int = Form(...), photo: UploadFile = File(...)):
    ud = get_current_user(request)
    p_dir = project_dir_for(ud["id"], project_name)
    data = load_project_data(p_dir, project_name)
    row = data["rows"][index]
    photo_dir = p_dir / "photos"
    photo_dir.mkdir(exist_ok=True)
    old = data["rows"][index].get("photo_path")
    if old and os.path.exists(old):
        os.remove(old)
    p_path = unique_photo_path(p_dir, data["rows"], index)
    with open(p_path, "wb") as b: shutil.copyfileobj(photo.file, b)
    data["rows"][index]["photo_path"] = str(p_path)
    write_project_json(p_dir, data)
    return {"status": "ok", "photo_path": f"/projects/{project_name}/photos/{p_path.name}"}

@router.get("/{project_name}/photos/{photo_name}")
async def get_photo(request: Request, project_name: str, photo_name: str):
    ud = get_current_user(request)
    return FileResponse(project_dir_for(ud["id"], project_name) / "photos" / photo_name)

@router.post("/{project_name}/update_description")
async def update_desc(request: Request, project_name: str, index: int = Form(...), description: str = Form("")):
    ud = get_current_user(request)
    p_dir = project_dir_for(ud["id"], project_name)
    data = load_project_data(p_dir, project_name)
    data["rows"][index]["description"] = description
    write_project_json(p_dir, data)
    return {"status": "ok"}

@router.post("/{project_name}/add_row")
async def add_row(request: Request, project_name: str, index: int = Form(...)):
    ud = get_current_user(request)
    p_dir = project_dir_for(ud["id"], project_name)
    data = load_project_data(p_dir, project_name)
    base = data["rows"][index]
    new_row = {"preset_label": base["preset_label"], "fixture_id": base["fixture_id"], "preset_no": base["preset_no"], "photo_path": "", "description": ""}
    data["rows"].insert(index + 1, new_row)
    write_project_json(p_dir, data)
    return {"status": "ok"}

@router.post("/{project_name}/delete_row")
async def delete_row(request: Request, project_name: str, index: int = Form(...)):
    ud = get_current_user(request)
    p_dir = project_dir_for(ud["id"], project_name)
    data = load_project_data(p_dir, project_name)
    if len(data["rows"]) > 1:
        old = data["rows"][index].get("photo_path")
        if old and os.path.exists(old): os.remove(old)
        data["rows"].pop(index)
        write_project_json(p_dir, data)
    return {"status": "ok"}

@router.post("/{project_name}/delete_photo")
async def delete_photo(request: Request, project_name: str, index: int = Form(...)):
    ud = get_current_user(request)
    p_dir = project_dir_for(ud["id"], project_name)
    data = load_project_data(p_dir, project_name)
    old = data["rows"][index].get("photo_path")
    if old and os.path.exists(old): os.remove(old)
    data["rows"][index]["photo_path"] = ""
    write_project_json(p_dir, data)
    return {"status": "ok"}

@router.get("/{project_name}/generate")
async def generate_docs(request: Request, project_name: str, db: Session = Depends(database.get_db)):
    user = get_db_user(request, db)
    p_dir = project_dir_for(user.id, project_name)
    data = load_project_data(p_dir, project_name)
    base_name = data.get("title") or project_base_name(project_name)
    
    # 1. Regenerate Presets
    rows = [PassportRow(r["preset_label"], r["fixture_id"], r["preset_no"], Path(r["photo_path"]) if r["photo_path"] else None, r["description"]) for r in data["rows"]]
    create_passport_xlsx(rows, p_dir / f"{base_name}_пресеты.xlsx", base_name)
    create_passport_pdf(rows, p_dir / f"{base_name}_пресеты.pdf", base_name)
    
    # 2. Regenerate Partitura (using user's custom fields if they exist)
    xml_p = p_dir / data["xml_file"]
    part_rows = [PartituraRow(**r) for r in data.get("partitura", [])] or (parse_partitura(xml_p) if xml_p.exists() else [])
    if part_rows:
        if user.partitura_fields:
            fields = [PartituraField(f["field_id"], f["title"], f["enabled"]) for f in json.loads(user.partitura_fields) if f["enabled"]]
        else:
            fields = [f for f in PARTITURA_DEFAULT_FIELDS if f.enabled]
            
        create_partitura_xlsx(part_rows, fields, p_dir / f"{base_name}_партитура.xlsx", base_name)
        create_partitura_pdf(part_rows, fields, p_dir / f"{base_name}_партитура.pdf", base_name)
    write_project_json(p_dir, data)
    if request.query_params.get("ajax") == "1":
        return {"status": "ok"}

    return RedirectResponse(url="/?msg=generated", status_code=303)

@router.get("/{project_name}/download/{file_name}")
async def dl_file(request: Request, project_name: str, file_name: str):
    ud = get_current_user(request)
    return FileResponse(project_dir_for(ud["id"], project_name) / file_name)
