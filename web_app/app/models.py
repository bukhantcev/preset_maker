from sqlalchemy import Column, Integer, String, DateTime, Boolean
from sqlalchemy.sql import func
from .database import Base

class User(Base):
    __tablename__ = "users"
    
    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True, nullable=True)
    hashed_password = Column(String, nullable=True)
    
    # OAuth providers
    google_id = Column(String, unique=True, index=True, nullable=True)
    yandex_id = Column(String, unique=True, index=True, nullable=True)
    
    # Cloud drives tokens (JSON serialized or simple string for demo)
    google_drive_token = Column(String, nullable=True)
    yandex_disk_token = Column(String, nullable=True)
    
    # Selected storage mode: "temp", "google_drive", "yandex_disk", "sftp"
    storage_mode = Column(String, default="temp")
    
    # SFTP settings (JSON serialized)
    sftp_config = Column(String, nullable=True)
    
    # Manual Yandex Disk token (for direct API access without OAuth scopes issues)
    yandex_manual_token = Column(String, nullable=True)
    
    # Custom partitura fields configuration (JSON serialized list of fields)
    partitura_fields = Column(String, nullable=True)
    
    # Admin flag
    is_admin = Column(Boolean, default=False)
    
    created_at = Column(DateTime(timezone=True), server_default=func.now())
