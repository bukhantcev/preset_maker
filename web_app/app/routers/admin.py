from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session
from pathlib import Path
import shutil
from .. import database, models

router = APIRouter()
templates = Jinja2Templates(directory="app/templates")

def storage_label(mode: str) -> str:
    labels = {
        "temp": "Сервер",
        "sftp": "SFTP",
        "yandex_disk": "Яндекс.Диск",
    }
    return labels.get(mode or "", mode or "Не выбрано")

def get_admin_user(request: Request, db: Session = Depends(database.get_db)):
    user_data = request.session.get("user")
    if not user_data:
        raise HTTPException(status_code=401, detail="Not authenticated")
    user = db.query(models.User).filter(models.User.id == user_data["id"]).first()
    if not user or not user.is_admin:
        raise HTTPException(status_code=403, detail="Not authorized. Admin access required.")
    return user

def get_dir_size(path: Path) -> int:
    total = 0
    try:
        for p in path.rglob('*'):
            if p.is_file():
                total += p.stat().st_size
    except:
        pass
    return total

@router.get("/")
async def admin_dashboard(request: Request, msg: str = None, admin_user: models.User = Depends(get_admin_user), db: Session = Depends(database.get_db)):
    users = db.query(models.User).all()
    
    base_dir = Path("/tmp/passport_creator/users")
    stats = []
    
    for u in users:
        user_dir = base_dir / str(u.id) / "projects"
        project_count = 0
        size_mb = 0
        if user_dir.exists():
            project_count = len([d for d in user_dir.iterdir() if d.is_dir() and (d / "project.json").exists()])
            size_mb = get_dir_size(user_dir) / (1024 * 1024)
            
        stats.append({
            "id": u.id,
            "email": u.email,
            "storage_mode": u.storage_mode,
            "storage_label": storage_label(u.storage_mode),
            "created_at": u.created_at,
            "is_admin": u.is_admin,
            "project_count": project_count,
            "size_mb": round(size_mb, 2)
        })
        
    return templates.TemplateResponse(request, "admin.html", {
        "admin_user": admin_user,
        "users": stats,
        "msg": msg
    })

@router.post("/user/{user_id}/clear_projects")
async def clear_user_projects(user_id: int, request: Request, admin_user: models.User = Depends(get_admin_user)):
    user_dir = Path(f"/tmp/passport_creator/users/{user_id}/projects")
    if user_dir.exists():
        shutil.rmtree(user_dir)
    return RedirectResponse(url="/admin", status_code=303)

@router.post("/user/{user_id}/reset_password")
async def reset_user_password(user_id: int, request: Request, admin_user: models.User = Depends(get_admin_user), db: Session = Depends(database.get_db)):
    user_to_reset = db.query(models.User).filter(models.User.id == user_id).first()
    if not user_to_reset:
        raise HTTPException(status_code=404, detail="User not found")
        
    from .auth import get_password_hash
    temp_password = "password123"
    user_to_reset.hashed_password = get_password_hash(temp_password)
    db.commit()
    
    return RedirectResponse(url=f"/admin?msg=Пароль%20для%20{user_to_reset.email}%20сброшен%20на%20{temp_password}", status_code=303)

@router.post("/user/{user_id}/delete")
async def delete_user(user_id: int, request: Request, admin_user: models.User = Depends(get_admin_user), db: Session = Depends(database.get_db)):
    if admin_user.id == user_id:
        raise HTTPException(status_code=400, detail="Cannot delete yourself")
        
    user_to_delete = db.query(models.User).filter(models.User.id == user_id).first()
    if not user_to_delete:
        raise HTTPException(status_code=404, detail="User not found")
        
    user_dir = Path(f"/tmp/passport_creator/users/{user_id}")
    if user_dir.exists():
        shutil.rmtree(user_dir)
        
    db.delete(user_to_delete)
    db.commit()
    
    return RedirectResponse(url="/admin", status_code=303)
