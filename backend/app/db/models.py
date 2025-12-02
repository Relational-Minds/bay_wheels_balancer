from datetime import datetime
from sqlalchemy import Column, Integer, String, DateTime, Enum as SQLEnum
import enum

from app.db.base import Base


class TaskStatusEnum(str, enum.Enum):
    """Task status enumeration for database"""
    READY = "ready"
    ASSIGNED = "assigned"
    COMPLETED = "completed"


class Suggestion(Base):
    """SQLAlchemy model for suggestions table"""
    __tablename__ = "suggestions"

    id = Column(Integer, primary_key=True, index=True)
    from_station_id = Column(Integer, nullable=False)
    to_station_id = Column(Integer, nullable=False)
    qty = Column(Integer, nullable=False)
    reason = Column(String, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)


class Task(Base):
    """SQLAlchemy model for tasks table"""
    __tablename__ = "tasks"

    id = Column(Integer, primary_key=True, index=True)
    from_station_id = Column(Integer, nullable=False)
    to_station_id = Column(Integer, nullable=False)
    qty = Column(Integer, nullable=False)
    reason = Column(String, nullable=True)
    status = Column(SQLEnum(TaskStatusEnum), default=TaskStatusEnum.READY, nullable=False)
    worker_id = Column(String, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)


