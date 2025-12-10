# 🏗️ Architecture Documentation

Technical architecture and design decisions for the Bay Wheels Orchestration & Dispatch Service.

---

## System Overview

The Orchestration & Dispatch Service is a **stateless REST API** that manages the lifecycle of bike rebalancing tasks. It serves as the central coordination layer between:

- **ML Engine**: Generates rebalancing suggestions
- **Workers**: Execute rebalancing tasks
- **Dashboard**: Monitors system status

---

## Architecture Layers

```
┌─────────────────────────────────────────┐
│         API Layer (FastAPI)             │
│  - Request/Response handling            │
│  - Validation (Pydantic)                 │
│  - Error handling                        │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│      Business Logic Layer               │
│  - Task approval logic                  │
│  - Dispatch logic (with locking)        │
│  - Status updates                       │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│      Data Access Layer (SQLAlchemy)    │
│  - ORM models                          │
│  - Database sessions                   │
│  - Transactions                        │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│      Database (PostgreSQL)             │
│  - Row-level locking                   │
│  - ACID transactions                   │
└────────────────────────────────────────┘
```

---

## Component Details

### 1. API Layer (`app/api/routes.py`)

**Responsibilities:**
- HTTP request/response handling
- Input validation via Pydantic schemas
- Error handling and status codes
- Route definitions

**Technology:** FastAPI with async/await support

**Key Features:**
- Automatic OpenAPI/Swagger documentation
- Type validation
- Dependency injection for database sessions

---

### 2. Business Logic Layer (`app/api/routes.py`)

**Responsibilities:**
- Task approval workflow
- Task dispatch with concurrency safety
- Status transitions

**Key Operations:**

#### Approve Suggestion
```
1. Find suggestion by ID
2. Create task with status='ready'
3. Delete suggestion
4. Commit transaction
```

#### Dispatch Task
```
1. Query oldest ready task
2. Lock row (FOR UPDATE SKIP LOCKED)
3. Update status='assigned', set worker_id
4. Commit transaction
```

#### Complete Task
```
1. Find task by ID
2. Update status='completed'
3. Commit transaction
```

---

### 3. Data Access Layer (`app/db/`)

**Responsibilities:**
- Database model definitions
- Session management
- Transaction handling

**Components:**
- `base.py`: SQLAlchemy declarative base
- `models.py`: ORM models (Suggestion, Task)
- `database.py`: Engine, session factory, dependency injection

**Session Management:**
- Uses FastAPI dependency injection
- Automatic session cleanup
- Transaction boundaries per request

---

### 4. Configuration Layer (`app/core/config.py`)

**Responsibilities:**
- Centralized configuration
- Environment variable management
- Settings validation

**Technology:** Pydantic Settings

**Configuration Sources:**
1. Environment variables
2. `.env` file
3. Default values

---

## Concurrency Model

### Problem Statement

Multiple workers may request tasks simultaneously. Without proper locking:
- Two workers could get the same task
- Race conditions could cause data corruption

### Solution: Row-Level Locking

**PostgreSQL Feature:** `SELECT ... FOR UPDATE SKIP LOCKED`

**Implementation:**
```python
stmt = (
    select(Task)
    .where(Task.status == TaskStatusEnum.READY)
    .order_by(Task.created_at.asc())
    .with_for_update(skip_locked=True)  # ← Critical
    .limit(1)
)
```

**How It Works:**

1. **Transaction Start**: Each request starts a database transaction
2. **Lock Acquisition**: `FOR UPDATE` locks the selected row
3. **Skip Locked Rows**: `SKIP LOCKED` ignores rows locked by other transactions
4. **Update & Commit**: Task is updated and transaction commits, releasing lock

**Timeline Example:**

```
Time    Worker A                    Worker B
─────────────────────────────────────────────
T1      SELECT ... FOR UPDATE
        (locks Task #1)
T2                              SELECT ... FOR UPDATE
                                (skips Task #1, locks Task #2)
T3      UPDATE Task #1
        COMMIT
T4                              UPDATE Task #2
                                COMMIT
```

**Result:** Each worker gets a different task ✅

---

## Database Design

### Tables

#### `suggestions`
- **Purpose**: Temporary storage for ML-generated suggestions
- **Lifecycle**: Created by ML engine → Deleted when approved
- **Indexes**: `id` (primary key)

#### `tasks`
- **Purpose**: Executable rebalancing tasks
- **Lifecycle**: `ready` → `assigned` → `completed`
- **Indexes**: `id` (primary key), `status` (for querying)

### Status State Machine

```
┌─────────┐
│ ready   │ ← Created when suggestion approved
└────┬────┘
     │
     │ POST /dispatch/next
     ▼
┌─────────┐
│assigned │ ← Worker assigned
└────┬────┘
     │
     │ POST /task/{id}/complete
     ▼
┌──────────┐
│completed │ ← Task finished
└──────────┘
```

---

## Request Flow

### Approve Suggestion Flow

```
Client Request
    │
    ▼
FastAPI Router
    │
    ▼
Validate Request (Pydantic)
    │
    ▼
Get DB Session (Dependency Injection)
    │
    ▼
Query Suggestion
    │
    ▼
Create Task
    │
    ▼
Delete Suggestion
    │
    ▼
Commit Transaction
    │
    ▼
Return TaskResponse
```

### Dispatch Task Flow

```
Worker Request
    │
    ▼
FastAPI Router
    │
    ▼
Validate Request (Pydantic)
    │
    ▼
Get DB Session (Dependency Injection)
    │
    ▼
BEGIN TRANSACTION
    │
    ▼
SELECT ... FOR UPDATE SKIP LOCKED
    │
    ▼
Update Task (status, worker_id)
    │
    ▼
COMMIT TRANSACTION
    │
    ▼
Return TaskResponse
```

---

## Error Handling

### Error Types

1. **Validation Errors** (400)
   - Invalid request body
   - Missing required fields
   - Type mismatches

2. **Not Found Errors** (404)
   - Suggestion not found
   - Task not found
   - No available tasks

3. **Server Errors** (500)
   - Database connection issues
   - Transaction failures
   - Unexpected exceptions

### Error Response Format

```json
{
  "detail": "Human-readable error message"
}
```

### Transaction Rollback

All database operations use transactions. On error:
1. Rollback transaction
2. Return appropriate HTTP status
3. Log error (in production)

---

## Scalability Considerations

### Current Limitations

- **Single Database**: All requests hit one PostgreSQL instance
- **No Caching**: Every request queries the database
- **No Load Balancing**: Single backend instance

### Future Improvements

1. **Database Scaling**
   - Read replicas for GET requests
   - Connection pooling (already implemented)
   - Partitioning for large tables

2. **Caching**
   - Redis for frequently accessed data
   - Cache suggestion lists
   - Cache task status

3. **Horizontal Scaling**
   - Multiple backend instances
   - Load balancer
   - Stateless design (already achieved)

4. **Message Queue**
   - RabbitMQ/Kafka for task dispatch
   - Decouple workers from API
   - Better scalability

---

## Security Considerations

### Current State

- **No Authentication**: All endpoints are public
- **No Authorization**: No role-based access control
- **No Rate Limiting**: Unlimited requests

### Production Recommendations

1. **Authentication**
   - API keys for workers
   - JWT tokens for dashboard
   - OAuth2 for admin endpoints

2. **Authorization**
   - Role-based access control (RBAC)
   - Workers can only dispatch/complete
   - Admins can approve suggestions

3. **Rate Limiting**
   - Per-IP rate limits
   - Per-worker rate limits
   - Prevent abuse

4. **Input Validation**
   - Already implemented via Pydantic
   - SQL injection protection (SQLAlchemy)
   - XSS protection (JSON responses)

5. **HTTPS**
   - TLS/SSL encryption
   - Certificate management

---

## Monitoring & Observability

### Recommended Metrics

1. **Request Metrics**
   - Request rate (requests/second)
   - Response times (p50, p95, p99)
   - Error rates

2. **Business Metrics**
   - Tasks created per hour
   - Tasks dispatched per hour
   - Average time from ready to assigned
   - Average time from assigned to completed

3. **Database Metrics**
   - Connection pool usage
   - Query performance
   - Transaction duration

### Logging

**Current State:** Basic error logging

**Recommendations:**
- Structured logging (JSON format)
- Log levels (DEBUG, INFO, WARNING, ERROR)
- Request/response logging
- Correlation IDs for tracing

---

## Deployment Architecture

### Docker Compose Setup

```
┌─────────────────┐
│  Backend        │
│  (FastAPI)      │
│  Port: 8000     │
└────────┬────────┘
         │
         │ SQL
         │
┌────────▼────────┐
│  PostgreSQL     │
│  Port: 5432     │
└─────────────────┘
```

### Production Deployment

**Recommended:**
- Kubernetes for orchestration
- Separate containers for backend and database
- Persistent volumes for database
- Health checks and auto-restart
- Secrets management for credentials

---

## Technology Choices

### Why FastAPI?

- **Performance**: Async support, comparable to Node.js
- **Type Safety**: Pydantic validation
- **Documentation**: Auto-generated OpenAPI docs
- **Modern**: Python 3.11+ features

### Why SQLAlchemy?

- **ORM**: Object-relational mapping
- **Type Safety**: Type hints support
- **Flexibility**: Can use raw SQL when needed
- **Migrations**: Alembic support (future)

### Why PostgreSQL?

- **Row-Level Locking**: Required for concurrency
- **ACID**: Transaction guarantees
- **Performance**: Excellent for concurrent reads/writes
- **Features**: JSON, arrays, full-text search

---

## Future Enhancements

1. **Task Prioritization**
   - Priority scores
   - Urgency-based dispatch

2. **Worker Management**
   - Worker registration
   - Worker status tracking
   - Capacity management

3. **Analytics**
   - Task completion rates
   - Worker performance metrics
   - Station rebalancing history

4. **Notifications**
   - WebSocket for real-time updates
   - Push notifications for workers

5. **Batch Operations**
   - Approve multiple suggestions
   - Bulk task creation

---

## References

- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [SQLAlchemy Documentation](https://docs.sqlalchemy.org/)
- [PostgreSQL Row-Level Locking](https://www.postgresql.org/docs/current/explicit-locking.html)
- [Pydantic Documentation](https://docs.pydantic.dev/)


