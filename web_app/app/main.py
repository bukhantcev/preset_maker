from fastapi import FastAPI, Request, Depends
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from starlette.middleware.sessions import SessionMiddleware
from sqlalchemy.orm import Session
from .database import engine, Base, get_db
from .config import settings as app_settings
from .routers import auth, projects, settings, admin, profile
from .routers.projects import cleanup_expired_projects, project_remaining_text, user_temp_dir
from .cloud_sync import list_cloud_projects
from . import models

# Create tables
Base.metadata.create_all(bind=engine)

app = FastAPI(title="Passport Creator SaaS")

app.add_middleware(SessionMiddleware, secret_key=app_settings.SECRET_KEY)

app.mount("/static", StaticFiles(directory="app/static"), name="static")

templates = Jinja2Templates(directory="app/templates")

app.include_router(auth.router, prefix="/auth", tags=["auth"])
app.include_router(projects.router, prefix="/projects", tags=["projects"])
app.include_router(settings.router, prefix="/settings", tags=["settings"])
app.include_router(admin.router, prefix="/admin", tags=["admin"])
app.include_router(profile.router, prefix="/profile", tags=["profile"])

@app.get("/")
async def read_root(request: Request, db: Session = Depends(get_db)):
    user_session = request.session.get("user")
    if user_session:
        user_id = user_session["id"]
        db_user = db.query(models.User).filter(models.User.id == user_id).first()
        if not db_user: return templates.TemplateResponse(request, "login.html")
        
        is_admin = db_user.is_admin
        
        # 1. Get local projects
        cleanup_expired_projects(user_id)
        user_dir = user_temp_dir(user_id)
        local_projects = set()
        project_retention = {}
        if user_dir.exists():
            for d in user_dir.iterdir():
                json_path = d / "project.json"
                if d.is_dir() and json_path.exists() and json_path.stat().st_size > 0:
                    local_projects.add(d.name)
                    project_retention[d.name] = project_remaining_text(d)
        
        # 2. Get cloud projects (for separate tab)
        cloud_projects = []
        try:
            cloud_projects = await list_cloud_projects(db_user)
        except Exception as e:
            print(f"DEBUG: Error listing cloud projects: {e}")
        
        return templates.TemplateResponse(request, "dashboard.html", {
            "user": db_user, 
            "is_admin": is_admin,
            "projects": sorted(list(local_projects)),
            "project_retention": project_retention,
            "cloud_projects": sorted(cloud_projects)
        })
    return templates.TemplateResponse(request, "login.html")
