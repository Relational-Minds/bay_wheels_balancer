from datetime import datetime
from typing import Optional
from enum import Enum
from pydantic import BaseModel


class TaskStatus(str, Enum):
    """Task status enumeration"""
    READY = "ready"
    ASSIGNED = "assigned"
    COMPLETED = "completed"


class SuggestionResponse(BaseModel):
    """Response schema for a suggestion"""
    id: int
    from_station_id: int
    to_station_id: int
    qty: int
    reason: str

    model_config = {"from_attributes": True}


class TaskCreate(BaseModel):
    """Input schema for creating a task"""
    suggestion_id: Optional[int] = None
    from_station_id: Optional[int] = None
    to_station_id: Optional[int] = None
    qty: Optional[int] = None
    reason: Optional[str] = None


class TaskApproveRequest(BaseModel):
    """Input schema for approving a suggestion and creating a task"""
    suggestion_id: int


class DispatchRequest(BaseModel):
    """Input schema for dispatching a task to a worker"""
    worker_id: str


class TaskResponse(BaseModel):
    """Response schema for a task"""
    id: int
    from_station_id: int
    to_station_id: int
    qty: int
    reason: Optional[str] = None
    status: TaskStatus
    worker_id: Optional[str] = None
    created_at: datetime

    model_config = {"from_attributes": True}


class TaskCompleteRequest(BaseModel):
    """Input schema for completing a task (optional, can be empty body)"""
    pass


