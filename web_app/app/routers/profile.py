from fastapi import APIRouter, Depends, HTTPException, Request, Form
from fastapi.responses import RedirectResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session
from .. import database, models
from .auth import get_password_hash, verify_password

router = APIRouter()
templates = Jinja2Templates(directory="app/templates")

def get_current_user_db(request: Request, db: Session = Depends(database.get_db)):
    user_data = request.session.get("user")
    if not user_data:
        raise HTTPException(status_code=401, detail="Not authenticated")
    user = db.query(models.User).filter(models.User.id == user_data["id"]).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user

@router.get("/")
async def view_profile(request: Request, msg: str = None, error: str = None, db: Session = Depends(database.get_db)):
    user = get_current_user_db(request, db)
    return templates.TemplateResponse(request, "profile.html", {"user": user, "msg": msg, "error": error})

@router.post("/update_email")
async def update_email(request: Request, new_email: str = Form(...), db: Session = Depends(database.get_db)):
    user = get_current_user_db(request, db)
    
    if new_email == user.email:
        return RedirectResponse(url="/profile?msg=Email%20не%20изменился", status_code=303)
        
    existing = db.query(models.User).filter(models.User.email == new_email).first()
    if existing:
        return RedirectResponse(url="/profile?error=Этот%20Email%20уже%20занят", status_code=303)
        
    user.email = new_email
    db.commit()
    
    # Reassign the whole dict to trigger session save in Starlette
    request.session["user"] = {"id": user.id, "email": new_email}
    
    return RedirectResponse(url="/profile?msg=Email%20успешно%20обновлен", status_code=303)

@router.post("/update_password")
async def update_password(request: Request, current_password: str = Form(...), new_password: str = Form(...), confirm_password: str = Form(...), db: Session = Depends(database.get_db)):
    user = get_current_user_db(request, db)
    
    if not verify_password(current_password, user.hashed_password):
        return RedirectResponse(url="/profile?error=Неверный%20текущий%20пароль", status_code=303)
        
    if new_password != confirm_password:
        return RedirectResponse(url="/profile?error=Новые%20пароли%20не%20совпадают", status_code=303)
        
    user.hashed_password = get_password_hash(new_password)
    db.commit()
    
    return RedirectResponse(url="/profile?msg=Пароль%20успешно%20изменен", status_code=303)
