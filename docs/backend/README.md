# 🚀 Bay Wheels Orchestration & Dispatch Service

The **Orchestration & Dispatch Service** is a high-performance backend API that manages the lifecycle of bike rebalancing suggestions and tasks. It provides endpoints for approving ML-generated suggestions, dispatching tasks to workers with concurrency safety, and tracking task completion.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Tech Stack](#tech-stack)
- [Architecture](#architecture)
- [Project Structure](#project-structure)
- [Setup & Deployment](#setup--deployment)
- [API Endpoints](#api-endpoints)
- [Database Models](#database-models)
- [Concurrency Handling](#concurrency-handling)
- [Configuration](#configuration)

---

## 🎯 Overview

This service acts as the central orchestrator for the Bay Wheels Station Balancer system:

1. **Receives suggestions** from the ML engine (stored in `suggestions` table)
2. **Approves suggestions** → converts them to executable tasks
3. **Dispatches tasks** to workers with race-condition protection
4. **Tracks task completion** status

### Key Features

- ✅ **Concurrency-safe task dispatch** using PostgreSQL row-level locking
- ✅ **FastAPI** for high-performance async endpoints
- ✅ **SQLAlchemy ORM** with PostgreSQL for robust data management
- ✅ **Dockerized** for easy deployment
- ✅ **Type-safe** with Pydantic schemas

---

## 🛠️ Tech Stack

| Component | Technology | Version |
|-----------|-----------|---------|
| **Language** | Python | 3.11 |
| **Framework** | FastAPI | 0.104.1 |
| **ORM** | SQLAlchemy | 2.0.23 |
| **Database** | PostgreSQL | 15 |
| **Validation** | Pydantic | 2.5.0 |
| **Server** | Uvicorn | 0.24.0 |
| **Deployment** | Docker & Docker Compose | - |

---

## 🏗️ Architecture

```
┌─────────────────┐
│   ML Engine     │
│  (Suggestions)  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Backend API    │
│  (This Service) │
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
┌────────┐ ┌──────────┐
│ Workers│ │ Dashboard│
└────────┘ └──────────┘
```

### Data Flow

1. **ML Engine** → Creates `suggestions` records
2. **Backend API** → Approves suggestions → Creates `tasks` (status: `ready`)
3. **Workers** → Request tasks via `/dispatch/next` → Get assigned task (status: `assigned`)
4. **Workers** → Complete tasks → Update status to `completed`

---

## 📁 Project Structure

```
backend/
├── app/
│   ├── __init__.py
│   ├── main.py                    # FastAPI app initialization
│   ├── api/
│   │   ├── __init__.py
│   │   └── routes.py              # API endpoints
│   ├── core/
│   │   ├── __init__.py
│   │   ├── config.py              # Application settings
│   │   └── database.py            # Database setup & session management
│   ├── db/
│   │   ├── __init__.py
│   │   ├── base.py                # SQLAlchemy Base
│   │   └── models.py              # Database models (Suggestion, Task)
│   └── schemas/
│       ├── __init__.py
│       └── schemas.py             # Pydantic request/response schemas
├── Dockerfile
├── docker-compose.yml
└── requirements.txt
```

### Module Responsibilities

- **`app/main.py`**: FastAPI application entry point, initializes database, includes routers
- **`app/api/routes.py`**: All HTTP endpoints (GET, POST handlers)
- **`app/core/config.py`**: Centralized configuration management
- **`app/core/database.py`**: Database engine, session factory, dependency injection
- **`app/db/models.py`**: SQLAlchemy ORM models for database tables
- **`app/schemas/schemas.py`**: Pydantic models for request/response validation

---

## 🚀 Setup & Deployment

### Prerequisites

- Docker & Docker Compose
- PostgreSQL 15 (or use Docker Compose)

### Quick Start

1. **Navigate to backend directory:**
   ```bash
   cd backend
   ```

2. **Start services:**
   ```bash
   docker-compose up --build
   ```

3. **Access the API:**
   - API: http://localhost:8000
   - Interactive Docs: http://localhost:8000/docs
   - ReDoc: http://localhost:8000/redoc

### Environment Variables

Create a `.env` file (optional, defaults provided):

```env
DATABASE_URL=postgresql://postgres:postgres@db:5432/baywheels
```

### Manual Setup (Development)

1. **Install dependencies:**
   ```bash
   pip install -r requirements.txt
   ```

2. **Set up PostgreSQL database:**
   - Create database: `baywheels`
   - Update `DATABASE_URL` in `.env` or `app/core/config.py`

3. **Run migrations** (tables auto-created on startup):
   ```bash
   python -m app.main
   ```

4. **Start server:**
   ```bash
   uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
   ```

---

## 📡 API Endpoints

### Base URL
```
http://localhost:8000
```

### 1. Health Check

**GET** `/`

Returns service health status.

**Response:**
```json
{
  "message": "Bay Wheels Orchestration & Dispatch Service"
}
```

---

### 2. Get All Suggestions

**GET** `/suggestions`

Fetches all records from the `suggestions` table.

**Response:** `200 OK`
```json
[
  {
    "id": 1,
    "from_station_id": 100,
    "to_station_id": 200,
    "qty": 5,
    "reason": "Station 100 is full, Station 200 needs bikes"
  }
]
```

---

### 3. Approve Suggestion → Create Task

**POST** `/task/approve`

Approves a suggestion and converts it to an executable task.

**Request Body:**
```json
{
  "suggestion_id": 123
}
```

**Response:** `200 OK`
```json
{
  "id": 456,
  "from_station_id": 100,
  "to_station_id": 200,
  "qty": 5,
  "reason": "Station 100 is full, Station 200 needs bikes",
  "status": "ready",
  "worker_id": null,
  "created_at": "2024-01-15T10:30:00"
}
```

**Business Logic:**
1. Find suggestion by ID
2. Create new `Task` with status `ready`
3. Delete the `Suggestion` record
4. Return created task

**Errors:**
- `404`: Suggestion not found
- `500`: Database error

---

### 4. Dispatch Next Task (CRITICAL)

**POST** `/dispatch/next`

Dispatches the oldest available task to a worker. **Uses row-level locking** to prevent race conditions.

**Request Body:**
```json
{
  "worker_id": "user_456"
}
```

**Response:** `200 OK`
```json
{
  "id": 456,
  "from_station_id": 100,
  "to_station_id": 200,
  "qty": 5,
  "reason": "Station 100 is full, Station 200 needs bikes",
  "status": "assigned",
  "worker_id": "user_456",
  "created_at": "2024-01-15T10:30:00"
}
```

**Business Logic:**
1. Find oldest task with `status='ready'`
2. Use `SELECT ... FOR UPDATE SKIP LOCKED` for exclusive access
3. Update task: `status='assigned'`, `worker_id=<input>`
4. Return assigned task

**Concurrency Safety:**
- Multiple workers can request simultaneously
- Each worker gets a **different** task
- No duplicate assignments possible

**Errors:**
- `404`: No available tasks
- `500`: Database error

---

### 5. Complete Task

**POST** `/task/{task_id}/complete`

Marks a task as completed.

**Path Parameters:**
- `task_id` (integer): Task ID to complete

**Response:** `200 OK`
```json
{
  "id": 456,
  "from_station_id": 100,
  "to_station_id": 200,
  "qty": 5,
  "reason": "Station 100 is full, Station 200 needs bikes",
  "status": "completed",
  "worker_id": "user_456",
  "created_at": "2024-01-15T10:30:00"
}
```

**Errors:**
- `404`: Task not found
- `500`: Database error

---

## 🗄️ Database Models

### Table: `suggestions`

Represents ML-generated rebalancing candidates.

| Column | Type | Description |
|--------|------|-------------|
| `id` | INTEGER (PK) | Auto-incrementing primary key |
| `from_station_id` | INTEGER | Source station ID |
| `to_station_id` | INTEGER | Destination station ID |
| `qty` | INTEGER | Number of bikes to move |
| `reason` | STRING | Explanation for the suggestion |
| `created_at` | TIMESTAMP | Record creation time |

**Model:** `app.db.models.Suggestion`

---

### Table: `tasks`

Represents approved, executable rebalancing tasks.

| Column | Type | Description |
|--------|------|-------------|
| `id` | INTEGER (PK) | Auto-incrementing primary key |
| `from_station_id` | INTEGER | Source station ID |
| `to_station_id` | INTEGER | Destination station ID |
| `qty` | INTEGER | Number of bikes to move |
| `reason` | STRING (nullable) | Optional explanation |
| `status` | ENUM | `ready`, `assigned`, `completed` |
| `worker_id` | STRING (nullable) | Assigned worker identifier |
| `created_at` | TIMESTAMP | Task creation time |

**Model:** `app.db.models.Task`

**Status Flow:**
```
ready → assigned → completed
```

---

## 🔒 Concurrency Handling

### Problem

When multiple workers request tasks simultaneously, there's a risk of:
- Two workers getting the same task
- Race conditions causing duplicate assignments

### Solution

The `/dispatch/next` endpoint uses **PostgreSQL row-level locking**:

```python
stmt = (
    select(Task)
    .where(Task.status == TaskStatusEnum.READY)
    .order_by(Task.created_at.asc())
    .with_for_update(skip_locked=True)  # ← Critical!
    .limit(1)
)
```

**How it works:**

1. **`SELECT ... FOR UPDATE`**: Locks the selected row for the current transaction
2. **`SKIP LOCKED`**: If a row is locked by another transaction, skip it and get the next available row
3. **Transaction isolation**: Each worker's request runs in its own transaction

**Result:**
- Worker A requests → Gets Task #1 (locked)
- Worker B requests simultaneously → Skips Task #1, gets Task #2
- No conflicts, no duplicates ✅

### Database Requirements

- **PostgreSQL 9.5+** (supports `SKIP LOCKED`)
- **Row-level locking** enabled (default in PostgreSQL)
- **Transaction isolation level**: `READ COMMITTED` (default)

---

## ⚙️ Configuration

### Settings File

`app/core/config.py` manages all configuration:

```python
class Settings(BaseSettings):
    DATABASE_URL: str = "postgresql://postgres:postgres@db:5432/baywheels"
    API_TITLE: str = "Bay Wheels Orchestration & Dispatch Service"
    API_VERSION: str = "1.0.0"
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DATABASE_URL` | `postgresql://postgres:postgres@db:5432/baywheels` | PostgreSQL connection string |

### Docker Compose Configuration

See `docker-compose.yml` for:
- PostgreSQL service configuration
- Backend service configuration
- Volume mounts
- Health checks

---

## 📚 Additional Documentation

- [API Reference](api_reference.md) - Detailed API documentation
- [Database Schema](../db/db_Readme.md) - Full database documentation

---

## 🧪 Testing

### Manual Testing with cURL

**Get suggestions:**
```bash
curl http://localhost:8000/suggestions
```

**Approve suggestion:**
```bash
curl -X POST http://localhost:8000/task/approve \
  -H "Content-Type: application/json" \
  -d '{"suggestion_id": 1}'
```

**Dispatch task:**
```bash
curl -X POST http://localhost:8000/dispatch/next \
  -H "Content-Type: application/json" \
  -d '{"worker_id": "worker_123"}'
```

**Complete task:**
```bash
curl -X POST http://localhost:8000/task/456/complete
```

### Interactive API Documentation

Visit http://localhost:8000/docs for Swagger UI with:
- Try-it-out functionality
- Request/response schemas
- Example payloads

---

## 🔧 Troubleshooting

### Database Connection Issues

- Verify PostgreSQL is running: `docker-compose ps`
- Check `DATABASE_URL` environment variable
- Ensure database exists: `psql -U postgres -d baywheels`

### Port Already in Use

Change port in `docker-compose.yml`:
```yaml
ports:
  - "8001:8000"  # Use 8001 instead of 8000
```

### Import Errors

Ensure you're running from the `backend/` directory and Python path includes `app/`.

---

## 📝 License

Part of the Bay Wheels Station Balancer project.


