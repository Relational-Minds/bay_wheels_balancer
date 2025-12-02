from fastapi import APIRouter, HTTPException, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.db.models import Suggestion, Task, TaskStatusEnum
from app.schemas import (
    SuggestionResponse,
    TaskApproveRequest,
    TaskResponse,
    DispatchRequest
)

router = APIRouter()


@router.get("/suggestions", response_model=list[SuggestionResponse])
async def get_suggestions(db: Session = Depends(get_db)):
    """
    Fetch all records from the suggestions table.
    """
    try:
        suggestions = db.query(Suggestion).all()
        return [SuggestionResponse.model_validate(s) for s in suggestions]
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error fetching suggestions: {str(e)}")


@router.post("/task/approve", response_model=TaskResponse)
async def approve_task(request: TaskApproveRequest, db: Session = Depends(get_db)):
    """
    Approve a suggestion and create a task.
    
    Logic:
    1. Find the Suggestion by ID
    2. Create a new Task row with data from Suggestion (status='ready')
    3. Delete the Suggestion row
    4. Commit transaction
    """
    try:
        # Find the suggestion
        suggestion = db.query(Suggestion).filter(Suggestion.id == request.suggestion_id).first()
        
        if not suggestion:
            raise HTTPException(status_code=404, detail=f"Suggestion with id {request.suggestion_id} not found")
        
        # Create a new task from the suggestion
        task = Task(
            from_station_id=suggestion.from_station_id,
            to_station_id=suggestion.to_station_id,
            qty=suggestion.qty,
            reason=suggestion.reason,
            status=TaskStatusEnum.READY
        )
        
        # Add task to session
        db.add(task)
        
        # Delete the suggestion
        db.delete(suggestion)
        
        # Commit the transaction
        db.commit()
        
        # Refresh to get the generated ID
        db.refresh(task)
        
        return TaskResponse.model_validate(task)
        
    except HTTPException:
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Error approving task: {str(e)}")


@router.post("/dispatch/next", response_model=TaskResponse)
async def dispatch_next_task(request: DispatchRequest, db: Session = Depends(get_db)):
    """
    Dispatch the next available task to a worker.
    
    CRITICAL: Uses row-level locking to prevent race conditions.
    
    Logic:
    1. Find the oldest Task where status='ready'
    2. Use SELECT ... FOR UPDATE SKIP LOCKED to ensure exclusive access
    3. Update that task to status='assigned' and set worker_id
    4. Return the Task
    
    This ensures that even if multiple workers request simultaneously,
    each will get a different task.
    """
    try:
        # Use SELECT ... FOR UPDATE SKIP LOCKED for concurrency safety
        # This ensures that if two workers request simultaneously, they get different tasks
        stmt = (
            select(Task)
            .where(Task.status == TaskStatusEnum.READY)
            .order_by(Task.created_at.asc())
            .with_for_update(skip_locked=True)
            .limit(1)
        )
        
        result = db.execute(stmt)
        task = result.scalar_one_or_none()
        
        if not task:
            raise HTTPException(
                status_code=404,
                detail="No available tasks with status 'ready'"
            )
        
        # Update the task
        task.status = TaskStatusEnum.ASSIGNED
        task.worker_id = request.worker_id
        
        # Commit the transaction
        db.commit()
        
        # Refresh to ensure we have the latest state
        db.refresh(task)
        
        return TaskResponse.model_validate(task)
        
    except HTTPException:
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Error dispatching task: {str(e)}")


@router.post("/task/{task_id}/complete", response_model=TaskResponse)
async def complete_task(task_id: int, db: Session = Depends(get_db)):
    """
    Mark a task as completed.
    
    Updates the task status to 'completed'.
    """
    try:
        # Find the task
        task = db.query(Task).filter(Task.id == task_id).first()
        
        if not task:
            raise HTTPException(status_code=404, detail=f"Task with id {task_id} not found")
        
        # Update status to completed
        task.status = TaskStatusEnum.COMPLETED
        
        # Commit the transaction
        db.commit()
        
        # Refresh to ensure we have the latest state
        db.refresh(task)
        
        return TaskResponse.model_validate(task)
        
    except HTTPException:
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Error completing task: {str(e)}")


