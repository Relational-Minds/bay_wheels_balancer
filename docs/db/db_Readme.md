# 🚲 Bay Wheels Station Balancer – Database Documentation

This document describes the **database schema**, **tables**, **materialized views**, and **data flow** used in the Bay Wheels Station Balancer system.  
It is based on **PostgreSQL + PostGIS** and serves as the core data layer for the backend, worker, and dashboard.

---

# 📦 Database Overview

The database stores:

- Static station metadata  
- Real-time station status snapshots  
- Historical trip data for analytical modeling  
- Rebalancing tasks and assignments  
- Materialized views for high-performance analytics  

All analytic tables are refreshed via a worker process or manually during development.

---

# 🗂️ Tables

## 1. `stations`
Holds **static metadata** for every Bay Wheels station.

| Column | Type | Description |
|--------|------|-------------|
| `station_id` | TEXT (PK) | Unique GBFS station ID |
| `name` | TEXT | Station display name |
| `capacity` | INT | Total number of docks |
| `lat` | DOUBLE PRECISION | Latitude |
| `lon` | DOUBLE PRECISION | Longitude |
| `geom` | GEOGRAPHY(Point, 4326) | PostGIS point for spatial queries |

---

## 2. `station_status`
Stores **real-time snapshots** from GBFS `station_status.json`.

| Column | Type | Description |
|--------|------|-------------|
| `station_id` | TEXT (FK) | Linked to `stations.station_id` |
| `num_bikes_available` | INT | Current number of bikes |
| `num_docks_available` | INT | Current empty docks |
| `last_reported` | TIMESTAMP | Time from GBFS |
| `ts` | TIMESTAMP | Insert timestamp (NOW) |

**Purpose:**  
Time-series table used to compute imbalance scores and real-time insights.

---

## 3. `trips`
Historical ride data from Lyft trip CSVs.

| Column | Type | Description |
|--------|------|-------------|
| `trip_id` | BIGSERIAL PK | Auto-incrementing ID |
| `start_station_id` | TEXT | Starting station |
| `end_station_id` | TEXT | Ending station |
| `started_at` | TIMESTAMP | Trip start time |
| `ended_at` | TIMESTAMP | Trip end time |

**Purpose:**  
Used to model inflow/outflow behavior and demand forecasting.

---

## 4. `tasks`
Represents **bike rebalancing tasks** created by backend logic.

| Column | Type | Description |
|--------|------|-------------|
| `task_id` | BIGSERIAL PK | Unique task identifier |
| `src_station_id` | TEXT | Station to remove bikes from |
| `dst_station_id` | TEXT | Station to deliver bikes to |
| `quantity` | INT | Number of bikes to move |
| `status` | TEXT | pending / assigned / completed / canceled |
| `created_at` | TIMESTAMP | Auto timestamp |

---

## 5. `assignments`
Tracks which employee or crew completes a task.

| Column | Type | Description |
|--------|------|-------------|
| `assignment_id` | BIGSERIAL PK | Unique assignment ID |
| `task_id` | BIGINT FK | References `tasks.task_id` |
| `assignee` | TEXT | Crew or worker identifier |
| `assigned_at` | TIMESTAMP | When assigned |
| `completed_at` | TIMESTAMP | When task was completed |

---

# 📊 Materialized Views

## 6. `station_flows` (Materialized View)
Aggregates 15-minute buckets of inflow/outflow from trips.

| Column | Type | Description |
|--------|------|-------------|
| `station_id` | TEXT | Station |
| `time_bin` | TIMESTAMP | 15-minute time bucket |
| `outflow` | INT | Trips starting at this station |
| `inflow` | INT | Trips ending at this station |

**Purpose:**  
Used in demand prediction & imbalance forecasting.

---

## 7. `imbalance_scores` (Materialized View)
Calculates station urgency score based on latest status.

| Column | Type | Description |
|--------|------|-------------|
| `station_id` | TEXT | Station |
| `name` | TEXT | Station name |
| `bikes` | INT | Latest bike count |
| `docks` | INT | Latest dock availability |
| `computed_at` | TIMESTAMP | MV refresh timestamp |
| `score` | INT | Urgency score (higher = more critical) |

**Example scoring logic:**
```sql
CASE WHEN bikes <= 2 THEN 70 ELSE 0 END +
CASE WHEN docks <= 2 THEN 30 ELSE 0 END
```

---

# 🧩 Backend-Orchestration Tables (SQLAlchemy)

In addition to the warehouse-style tables above (created in `db/init/01_schema.sql`),  
the **backend service** uses SQLAlchemy models to create and manage its own tables:

## 8. `suggestions` (backend)

Created by `app.db.models.Suggestion`:

| Column            | Type       | Description                         |
|-------------------|------------|-------------------------------------|
| `id`              | INTEGER PK | Auto-incrementing primary key       |
| `from_station_id` | INTEGER    | Source station ID                   |
| `to_station_id`   | INTEGER    | Destination station ID              |
| `qty`             | INTEGER    | Number of bikes to move             |
| `reason`          | TEXT       | Explanation for the suggestion      |
| `created_at`      | TIMESTAMP  | Record creation time (UTC)          |

**Usage:** Temporary storage for ML-generated rebalancing suggestions.  
Suggestions are converted into backend tasks and then deleted.

## 9. `backend_tasks` (backend)

Created by `app.db.models.Task` (not the same shape as the ETL `tasks` table above):

| Column            | Type       | Description                                  |
|-------------------|------------|----------------------------------------------|
| `id`              | INTEGER PK | Auto-incrementing primary key                |
| `from_station_id` | INTEGER    | Source station ID                            |
| `to_station_id`   | INTEGER    | Destination station ID                       |
| `qty`             | INTEGER    | Number of bikes to move                      |
| `reason`          | TEXT NULL  | Optional explanation                         |
| `status`          | ENUM       | `ready`, `assigned`, `completed`             |
| `worker_id`       | TEXT NULL  | Assigned worker identifier                   |
| `created_at`      | TIMESTAMP  | Task creation time (UTC)                     |

**Note:**  
- The **warehouse `tasks` table** documented earlier (`task_id`, `src_station_id`, `dst_station_id`, `quantity`, `status`, `created_at`) comes from `01_schema.sql` and is used for analytics/ETL.  
- The **backend `backend_tasks` table** above is created/managed by SQLAlchemy and is what the FastAPI routes (`/task/approve`, `/dispatch/next`, `/task/{id}/complete`) interact with.

[Helper Function](db_helper_function.md)  
[Data Flow](db_data_flow.md)