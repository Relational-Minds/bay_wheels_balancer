import os
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Application settings"""
    
    # Database
    DATABASE_URL: str = os.getenv(
        "DATABASE_URL",
        "postgresql://postgres:postgres@db:5432/baywheels"
    )
    
    # API
    API_TITLE: str = "Bay Wheels Orchestration & Dispatch Service"
    API_VERSION: str = "1.0.0"
    
    model_config = {
        "env_file": ".env",
        "case_sensitive": True
    }


settings = Settings()

