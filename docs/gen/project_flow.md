# 🚲 Bay Wheels Station Balancer — End-to-End Project Flow
*(Updated version with suggestion-based workflow & no AI layer)*

This system helps Bay Wheels operations staff keep stations balanced by:
- forecasting shortages and surpluses,
- generating suggested moves,
- approving them into tasks, and
- dispatching them safely to crews.

## 🧩 1. Data Sources (Historical + Live)

### A. Historical Trip Data (CSV)
- Millions of past rides
- Contains timestamps, start & end stations
- Used for:
  - Feature engineering
  - Flow modeling
  - Time-series forecasting
  - Understanding typical station behavior

### B. Live GBFS Feed (Real-Time JSON)
- Real-time bikes and docks available per station
- Polled every 30–60 seconds
- Used for:
  - Current station status
  - Short-term trend correction
  - Live imbalance detection

## 🧩 2. Data Pipeline Layer

Role A (Data Engineering & Forecasting) builds:

### Step 1 — Ingest Historical Trips into MySQL
- Load CSV → trip_history
- Normalize station IDs
- Store metadata in station table

### Step 2 — Feature Engineering
Creates aggregated materialized views:
- mv_station_flow_15min (inflow/outflow)
- Rolling averages
- Time-of-day / weekday patterns

### Step 3 — Forecast Future Station Bikes
Blend:
- Historical long-term flow averages
- Short-term live trend

Output:
forecast_station_status(station_id, predicted_bikes_15m)

Stations are labeled as:
- empty_soon
- full_soon
- balanced

## 🧩 3. Suggestion Generation Layer

Role A (Forecasting) + Role B (Orchestration) combine to create:

### Step 4 — Suggestion Candidates Table
For each high-risk station:
- Find nearby surplus stations using PostGIS
- Suggest moves like:
from_station_id = 310
to_station_id = 205
qty = 8
reason = 'Station 205 predicted empty in 15m'

### Step 5 — Deduplication Logic (Role B)
New suggestions are compared against:
- Existing tasks (task table)
- Active suggestions not yet approved

Prevents repeated or redundant suggestions.

## 🧩 4. Operations Dashboard & User Interaction

Role C (Live Data + Dashboard) builds:

### Step 6 — Live Dashboard Components

#### A. Station Map
- Shows station color status:
  - Red: predicted empty
  - Blue: predicted full
  - Green: healthy

#### B. Suggestions Panel
- Displays actions like:
“Move 8 bikes from Station 310 → Station 205”
- Each row has an “Approve Task” button
- On click: /task/approve (handled by Role B)

#### C. Task List View
- Shows approved tasks that crews will execute
- Status: ready → assigned → completed

#### D. Trend Charts
- Stockout rates
- Forecast accuracy
- Bikes moved per hour

#### E. Grafana Panels (Role C + D)
- Query performance
- Transaction latency
- Live feed reliability

## 🧩 5. Task Lifecycle (Backend + Transactions)

Role B (Backend Orchestration) owns all backend logic:

### Step 7 — When User Approves a Suggestion
/task/approve endpoint inserts a new row:
task_id | from_station | to_station | qty | status='ready'

Duplicate protection ensures:
- No two tasks represent the same suggestion
- No conflicting moves are created

### Step 8 — Crew Dispatch (Concurrency Demo)
Workers call:
/dispatch/next

Internally uses:
SELECT task_id FROM task
WHERE status='ready'
ORDER BY priority, created_at
FOR UPDATE SKIP LOCKED
LIMIT 1;

Guarantees only one worker gets the task.

### Step 9 — Task Completion (SERIALIZABLE Safety)
When a worker finishes, they call /task/{id}/complete.
The backend performs:
- SERIALIZABLE transaction
- Advisory locks on both stations
- Inventory adjustment
- Database invariants:
  - No negative bikes
  - No exceeding dock capacity

## 🧩 6. Monitoring, Query Optimization & Deployment

Role D (Infrastructure & Testing) owns:

### Step 10 — Indexing & Optimization
- Create indexes on common queries
- Benchmark using EXPLAIN ANALYZE
- Optimize heavy joins (forecasting, suggestions)

### Step 11 — System Monitoring (Grafana)
Track:
- Stockout rate
- Query latency
- Error/retry rate
- API call frequency

### Step 12 — Deployment
- Docker Compose for local
- Cloud deployment for demo
- Connection pooling
- CI/CD
- Performance and integration testing

## 🧩 7. End-to-End Flow Summary (Quick Reference)

Data → Forecast → Suggestion → Approval → Task → Dispatch → Complete

1. Live feed + historical data
2. Forecast future bike levels
3. Generate move suggestions
4. User approves suggestion → becomes task
5. Dispatch task with concurrency-safe logic
6. Worker completes task
7. Dashboard updates in real-time
8. Grafana monitors system health and performance

## 🧩 8. How Roles Interconnect (High-Level Diagram)

| Stage                         | Person Responsible | Output                          |
|-------------------------------|--------------------|---------------------------------|
| Data ingestion + features     | A                  | Aggregates & MVs                |
| Forecasting                   | A                  | Future bike predictions         |
| Suggestion candidates         | A                  | suggestion_candidates table     |
| Deduplication + task approval | B                  | task table                      |
| Dispatch + complete           | B                  | Task lifecycle                  |
| Live GBFS feed                | C                  | station_status_snap             |
| Dashboard                     | C                  | UI + approval flow              |
| Monitoring + deployment       | D                  | Grafana + system stability      |
