from fastapi import APIRouter, Depends, HTTPException, Request, Response, Form
from fastapi.responses import RedirectResponse
from sqlalchemy.orm import Session
from passlib.context import CryptContext
from authlib.integrations.starlette_client import OAuth
from starlette.config import Config
import os
import json
from .. import models, schemas, database

router = APIRouter()
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# Config for OAuth
config_data = {
    'YANDEX_CLIENT_ID': os.environ.get('YANDEX_CLIENT_ID', ''),
    'YANDEX_CLIENT_SECRET': os.environ.get('YANDEX_CLIENT_SECRET', '')
}
starlette_config = Config(environ=config_data)
oauth = OAuth(starlette_config)

oauth.register(
    name='yandex',
    client_id=config_data['YANDEX_CLIENT_ID'],
    client_secret=config_data['YANDEX_CLIENT_SECRET'],
    access_token_url='https://oauth.yandex.ru/token',
    authorize_url='https://oauth.yandex.ru/authorize',
    api_base_url='https://login.yandex.ru/',
    client_kwargs={'scope': 'login:email login:info'}
)

def verify_password(plain_password, hashed_password):
    return pwd_context.verify(plain_password, hashed_password)

def get_password_hash(password):
    return pwd_context.hash(password)

@router.post("/register")
async def register(request: Request, email: str = Form(...), password: str = Form(...), db: Session = Depends(database.get_db)):
    db_user = db.query(models.User).filter(models.User.email == email).first()
    if db_user:
        raise HTTPException(status_code=400, detail="Email already registered")
    
    hashed_password = get_password_hash(password)
    new_user = models.User(email=email, hashed_password=hashed_password, is_admin=False)
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    
    request.session["user"] = {"id": new_user.id, "email": new_user.email}
    return RedirectResponse(url="/", status_code=303)

@router.post("/login")
async def login(request: Request, email: str = Form(...), password: str = Form(...), db: Session = Depends(database.get_db)):
    db_user = db.query(models.User).filter(models.User.email == email).first()
    if not db_user or not verify_password(password, db_user.hashed_password):
        raise HTTPException(status_code=400, detail="Incorrect email or password")
    
    request.session["user"] = {"id": db_user.id, "email": db_user.email}
    return RedirectResponse(url="/", status_code=303)

@router.get("/logout")
async def logout(request: Request):
    request.session.clear()
    return RedirectResponse(url="/", status_code=303)

@router.get("/yandex")
async def auth_yandex(request: Request):
    if not config_data['YANDEX_CLIENT_ID']:
        return Response("Ключи Yandex не настроены на сервере.", media_type="text/plain")
    redirect_uri = request.url_for('auth_yandex_callback')
    redirect_uri = str(redirect_uri).replace('http://', 'https://')
    return await oauth.yandex.authorize_redirect(request, redirect_uri)

@router.get("/yandex/callback")
async def auth_yandex_callback(request: Request, db: Session = Depends(database.get_db)):
    try:
        token = await oauth.yandex.authorize_access_token(request)
    except Exception as e:
        return RedirectResponse(url="/?error=Ошибка%20авторизации%20Yandex", status_code=303)
        
    resp = await oauth.yandex.get('info', token=token)
    user_info = resp.json()
    
    yandex_id = user_info.get('id')
    email = user_info.get('default_email')
    
    if not email:
        return RedirectResponse(url="/?error=Не%20удалось%20получить%20email%20от%20Yandex", status_code=303)
        
    db_user = db.query(models.User).filter((models.User.yandex_id == yandex_id) | (models.User.email == email)).first()
    
    if not db_user:
        db_user = models.User(email=email, yandex_id=yandex_id, yandex_disk_token=json.dumps(token), is_admin=False)
        db.add(db_user)
        db.commit()
        db.refresh(db_user)
    else:
        db_user.yandex_id = yandex_id
        db_user.yandex_disk_token = json.dumps(token)
        db.commit()
        
    request.session["user"] = {"id": db_user.id, "email": db_user.email}
    return RedirectResponse(url="/", status_code=303)

@router.get("/yandex/disk_connect")
async def yandex_disk_connect(request: Request):
    if not config_data['YANDEX_CLIENT_ID']:
        return Response("Ключи Yandex не настроены.", media_type="text/plain")
    redirect_uri = request.url_for('auth_yandex_disk_callback')
    redirect_uri = str(redirect_uri).replace('http://', 'https://')
    return await oauth.yandex.authorize_redirect(request, redirect_uri)

@router.get("/yandex/disk_callback")
async def auth_yandex_disk_callback(request: Request, db: Session = Depends(database.get_db)):
    user_data = request.session.get("user")
    if not user_data:
        return RedirectResponse(url="/?error=Session%20expired", status_code=303)

    try:
        token = await oauth.yandex.authorize_access_token(request)
    except Exception as e:
        return RedirectResponse(url="/settings?error=Ошибка%20подключения%20Диска", status_code=303)

    user = db.query(models.User).filter(models.User.id == user_data["id"]).first()
    if user:
        user.yandex_manual_token = token.get("access_token")
        user.storage_mode = "yandex_disk"
        db.commit()

    return RedirectResponse(url="/settings?msg=Яндекс.Диск%20успешно%20подключен", status_code=303)
