import os
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    SECRET_KEY: str = "supersecretkey_change_in_production"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 7 # 7 days
    
    SQLALCHEMY_DATABASE_URL: str = "sqlite:///./passport_creator.db"
    
    BASE_TEMP_DIR: str = "/tmp/passport_creator/users"
    
    GOOGLE_CLIENT_ID: str = os.getenv("GOOGLE_CLIENT_ID", "")
    GOOGLE_CLIENT_SECRET: str = os.getenv("GOOGLE_CLIENT_SECRET", "")
    
    YANDEX_CLIENT_ID: str = os.getenv("YANDEX_CLIENT_ID", "")
    YANDEX_CLIENT_SECRET: str = os.getenv("YANDEX_CLIENT_SECRET", "")

settings = Settings()
