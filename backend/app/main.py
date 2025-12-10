from fastapi import FastAPI

from app.core.config import settings
from app.core.database import init_db
from app.api.routes import router

# Initialize database
init_db()

# Create FastAPI app
app = FastAPI(
    title=settings.API_TITLE,
    version=settings.API_VERSION
)

# Include routers
app.include_router(router)


@app.get("/")
async def root():
    """Health check endpoint"""
    return {"message": settings.API_TITLE}


