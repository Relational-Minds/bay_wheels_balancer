# 📡 API Reference

Complete API documentation for the Bay Wheels Orchestration & Dispatch Service.

---

## Base URL

```
http://localhost:8000
```

All endpoints return JSON responses.

---

## Endpoints

### 1. Health Check

**GET** `/`

Check if the service is running.

**Response:** `200 OK`
```json
{
  "message": "Bay Wheels Orchestration & Dispatch Service"
}
```

---

### 2. Get All Suggestions

**GET** `/suggestions`

Retrieve the latest station suggestion cards by joining `stations` with the freshest `station_status` snapshot. Each object surfaces a station’s inventory plus urgency classification.

**Response:** `200 OK`

**Fields (`SuggestionResponse`):**
- `id`: Station identifier (matches `stations.station_id`)
- `name`: Human-readable station name
- `lat` / `lng`: Station coordinates
- `capacity`: Total docks at the station (0 if unknown)
- `available`: Latest `num_bikes_available` value (0 if no snapshot yet)
- `status`: `"critical" | "warning" | "balanced"`
- `type`: `"empty" | "full" | "null"`

**Status/Type rules (ratio = `available / capacity`):**
- `capacity <= 0` → `status="balanced"`, `type="null"`
- `ratio ≤ 0.10` → `status="critical"`, `type="empty"`
- `ratio ≥ 0.90` → `status="critical"`, `type="full"`
- `ratio ≤ 0.20` → `status="warning"`, `type="empty"`
- `ratio ≥ 0.80` → `status="warning"`, `type="full"`
- Otherwise → `status="balanced"`, `type="null"`

**Response Example:**
```json
[
  {
    "id": "st_01",
    "name": "Market & 8th",
    "lat": 37.7766,
    "lng": -122.4169,
    "capacity": 27,
    "available": 1,
    "status": "critical",
    "type": "empty"
  },
  {
    "id": "st_02",
    "name": "2nd & Harrison",
    "lat": 37.7838,
    "lng": -122.3926,
    "capacity": 21,
    "available": 10,
    "status": "balanced",
    "type": "null"
  },
  {
    "id": "st_03",
    "name": "Civic Center",
    "lat": 37.7793,
    "lng": -122.4192,
    "capacity": 31,
    "available": 25,
    "status": "warning",
    "type": "full"
  }
]
```

**Response Model:** `list[SuggestionResponse]`

**Example:**
```bash
curl http://localhost:8000/suggestions
```

---

### 3. Approve Suggestion

**POST** `/task/approve`

Convert a suggestion into an executable task.

**Request Body:**
```json
{
  "suggestion_id": 123
}
```

**Request Schema:** `TaskApproveRequest`
- `suggestion_id` (integer, required): ID of the suggestion to approve

**Response:** `200 OK`

**Response Schema:**
```json
{
  "id": 456,
  "from_station_id": 100,
  "to_station_id": 200,
  "qty": 5,
  "reason": "Station 100 is full, Station 200 needs bikes",
  "status": "ready",
  "worker_id": null,
  "created_at": "2024-01-15T10:30:00Z"
}
```

**Response Model:** `TaskResponse`

**Status Codes:**
- `200`: Task created successfully
- `404`: Suggestion not found
- `500`: Internal server error

**Example:**
```bash
curl -X POST http://localhost:8000/task/approve \
  -H "Content-Type: application/json" \
  -d '{"suggestion_id": 123}'
```

**Business Logic:**
1. Finds the suggestion by ID
2. Creates a new task with `status='ready'`
3. Deletes the original suggestion
4. Returns the created task

---

### 4. Dispatch Next Task

**POST** `/dispatch/next`

Assign the next available task to a worker. **Thread-safe** - uses row-level locking.

**Request Body:**
```json
{
  "worker_id": "user_456"
}
```

**Request Schema:** `DispatchRequest`
- `worker_id` (string, required): Identifier for the worker requesting the task

**Response:** `200 OK`

**Response Schema:**
```json
{
  "id": 456,
  "from_station_id": 100,
  "to_station_id": 200,
  "qty": 5,
  "reason": "Station 100 is full, Station 200 needs bikes",
  "status": "assigned",
  "worker_id": "user_456",
  "created_at": "2024-01-15T10:30:00Z"
}
```

**Response Model:** `TaskResponse`

**Status Codes:**
- `200`: Task assigned successfully
- `404`: No available tasks with status 'ready'
- `500`: Internal server error

**Example:**
```bash
curl -X POST http://localhost:8000/dispatch/next \
  -H "Content-Type: application/json" \
  -d '{"worker_id": "worker_123"}'
```

**Concurrency Behavior:**
- Uses `SELECT ... FOR UPDATE SKIP LOCKED`
- Multiple workers can request simultaneously
- Each worker receives a different task
- No duplicate assignments possible

**Selection Criteria:**
- Oldest task with `status='ready'` (by `created_at`)

---

### 5. Complete Task

**POST** `/task/{task_id}/complete`

Mark a task as completed.

**Path Parameters:**
- `task_id` (integer, required): ID of the task to complete

**Response:** `200 OK`

**Response Schema:**
```json
{
  "id": 456,
  "from_station_id": 100,
  "to_station_id": 200,
  "qty": 5,
  "reason": "Station 100 is full, Station 200 needs bikes",
  "status": "completed",
  "worker_id": "user_456",
  "created_at": "2024-01-15T10:30:00Z"
}
```

**Response Model:** `TaskResponse`

**Status Codes:**
- `200`: Task completed successfully
- `404`: Task not found
- `500`: Internal server error

**Example:**
```bash
curl -X POST http://localhost:8000/task/456/complete
```

**Business Logic:**
1. Finds the task by ID
2. Updates `status` to `'completed'`
3. Returns the updated task

---

## Data Models

### SuggestionResponse

```json
{
  "id": "st_01",
  "name": "Market & 8th",
  "lat": 37.7766,
  "lng": -122.4169,
  "capacity": 27,
  "available": 1,
  "status": "critical",
  "type": "empty"
}
```

**Fields:**
- `id` (string): Station identifier (`stations.station_id`)
- `name` (string): Station display name
- `lat` / `lng` (numbers): Coordinates
- `capacity` (integer): Dock count (0 if missing)
- `available` (integer): Bikes available (0 if missing)
- `status` (string): `"critical" | "warning" | "balanced"`
- `type` (string): `"empty" | "full" | "null"`

---

### TaskResponse

```json
{
  "id": 456,
  "from_station_id": 100,
  "to_station_id": 200,
  "qty": 5,
  "reason": "Station 100 is full, Station 200 needs bikes",
  "status": "assigned",
  "worker_id": "user_456",
  "created_at": "2024-01-15T10:30:00Z"
}
```

**Fields:**
- `id` (integer): Task ID
- `from_station_id` (integer): Source station ID
- `to_station_id` (integer): Destination station ID
- `qty` (integer): Number of bikes to move
- `reason` (string, nullable): Optional explanation
- `status` (enum): `"ready"`, `"assigned"`, or `"completed"`
- `worker_id` (string, nullable): Assigned worker identifier
- `created_at` (datetime): Task creation timestamp (ISO 8601)

---

### TaskApproveRequest

```json
{
  "suggestion_id": 123
}
```

**Fields:**
- `suggestion_id` (integer, required): ID of the suggestion to approve

---

### DispatchRequest

```json
{
  "worker_id": "user_456"
}
```

**Fields:**
- `worker_id` (string, required): Worker identifier

---

## Error Responses

All errors follow this format:

```json
{
  "detail": "Error message description"
}
```

### Common Error Codes

| Status Code | Meaning | Example |
|-------------|---------|---------|
| `400` | Bad Request | Invalid request body |
| `404` | Not Found | Resource not found |
| `500` | Internal Server Error | Database error, server error |

### Example Error Response

```json
{
  "detail": "Suggestion with id 999 not found"
}
```

---

## Rate Limiting

Currently, no rate limiting is implemented. Consider adding rate limiting for production use.

---

## Authentication

Currently, no authentication is implemented. Consider adding:
- API keys
- JWT tokens
- OAuth2

---

## Interactive Documentation

Visit http://localhost:8000/docs for:
- Swagger UI with try-it-out functionality
- Request/response examples
- Schema definitions

Visit http://localhost:8000/redoc for:
- ReDoc documentation
- Clean, readable API docs


