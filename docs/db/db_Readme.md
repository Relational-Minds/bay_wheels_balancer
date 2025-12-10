# Bay Wheels Database — Data Engineering & Forecasting

This README helps first-time users understand the database logic, data flow, and how to set up and run the Bay Wheels Station Balancer database pipeline.

---

## Table of Contents
1. [Understanding the System](#understanding-the-system)
2. [Data Flow & Logic](#data-flow--logic)
3. [Database Schema](#database-schema)
4. [Setup & Configuration](#setup--configuration)
5. [Running the Pipeline](#running-the-pipeline)
6. [Manual Script Execution](#manual-script-execution)
7. [Performance & Optimization](#performance--optimization)

---

## Understanding the System

### What does this system do?

The Bay Wheels Station Balancer predicts which bike-share stations will be **empty** or **full** in the next 15 minutes and generates **rebalancing jobs** to move bikes between stations.

**Key concepts:**
- **Historical demand**: We analyze past trip patterns (arrivals/departures) aggregated by day-of-week, hour, and 15-minute intervals.
- **Forecasting**: Using current inventory + historical patterns, we predict future bike counts at each station.
- **Risk categorization**: Stations are labeled as `empty_soon`, `full_soon`, or `balanced`.
- **Rebalancing suggestions**: The system matches "full" stations (sources) with "empty" stations (sinks) within a distance limit and respects capacity constraints.

### Why these components?

| Component | Purpose |
|-----------|---------|
| **trip_history** | Stores raw trip data (who rode from where to where, when) |
| **station_15min_demand** | Historical averages: how many bikes typically arrive/depart per station per 15-min bucket |
| **station_inventory** | Real-time snapshot: current bikes, capacity, last update time (populated by live GBFS feed) |
| **forecast_station_status** | Predicted bike count + risk level for each station |
| **rebalancing_jobs** | Actionable moves: from_station → to_station, how many bikes, distance |

---

## Data Flow & Logic

### High-Level Pipeline

```
CSV Trip Data
     ↓
[1] Ingest Pipeline
     ↓
trip_history + station (with PostGIS geom)
     ↓
[2] Aggregation (15-min buckets)
     ↓
station_15min_demand
     ↓
[3] Forecasting (+ station_inventory)
     ↓
forecast_station_status
     ↓
[4] Rebalancing Suggestion
     ↓
rebalancing_jobs
```

### Detailed Data Flow

#### **Step 1: Ingestion** (`db/populate_stations.py`, `db/load_trips.py`)

**Input:** CSV files with columns like:
- `ride_id, started_at, ended_at, start_station_id, start_station_name, end_station_id, end_station_name, start_lat, start_lng, end_lat, end_lng`

**Process:**
1. Extract distinct stations from CSVs → upsert into `station` table with PostGIS geometry (`ST_MakePoint(lng, lat)`).
2. Parse trip rows (timestamps with fractional seconds) → insert into `trip_history`.
3. Skip rows with missing start/end station IDs.

**Output:**
- `trip_history`: ride_id, started_at, ended_at, start_station_id, end_station_id
- `station`: station_id, station_name, geom (POINT geometry, SRID 4326)

---

#### **Step 2: Aggregation** (`db/build_station_flow_15min.py`)

**Input:** `trip_history` (all historical trips)

**Process:**
1. Bucket each trip by:
   - `day_of_week` (0=Monday, 6=Sunday)
   - `hour_of_day` (0-23)
   - `quarter_hour` (0-3, representing 0, 15, 30, 45 minutes)
2. For each bucket + station:
   - Count **departures** (trips starting at station)
   - Count **arrivals** (trips ending at station)
   - Compute **net flow** = arrivals - departures
3. Calculate historical averages: `avg_arrivals_15m`, `avg_departures_15m`, `avg_net_flow_15m`
4. Upsert into `station_15min_demand`

**Output:**
- `station_15min_demand`: (station_id, day_of_week, hour_of_day, quarter_hour) → avg values

**Why?** This captures **intra-day demand patterns** (e.g., "Station X typically gains 5 bikes between 8:00-8:15 AM on Mondays").

---

#### **Step 3: Forecasting** (`db/run_forecast.py`)

**Input:**
- `station_inventory` (current_bikes, capacity, last_reported timestamp)
- `station_15min_demand` (historical patterns)

**Process:**
1. For each station, convert `last_reported` timestamp into a 15-min bucket (day_of_week, hour, quarter).
2. Look up historical `avg_net_flow_15m` for that bucket from `station_15min_demand`.
3. **Fallback chain** if no data:
   - Try exact (day, hour, quarter)
   - Try same hour/day, any quarter
   - Try same hour, any day
   - Use station's overall average
   - Default to 0
4. Predict: `predicted_bikes = current_bikes + avg_net_flow_15m`
5. Clamp to `[0, capacity]`
6. Categorize risk:
   - `empty_soon`: predicted ≤ EMPTY_THRESHOLD (default 2)
   - `full_soon`: predicted ≥ capacity - FULL_MARGIN (default 3)
   - `balanced`: otherwise
7. Upsert into `forecast_station_status`

**Output:**
- `forecast_station_status`: station_id, forecast_ts, predicted_bikes_15m, risk_status

**Why?** Simple heuristic forecast (current + historical pattern). Can be replaced with ML models.

---

#### **Step 4: Rebalancing Suggestions** (`db/build_suggestions.py`)

**Input:**
- `forecast_station_status` (latest forecast per station)
- `station_inventory` (capacity info)
- `station` (PostGIS geometry for distance)

**Process:**
1. Compute `target_level = 50% of capacity` for each station.
2. Classify:
   - **Sources** (can give bikes): predicted > target
     - Priority 1: FULL_SOON
     - Priority 2: BALANCED with surplus
   - **Sinks** (need bikes): predicted < target
     - Priority 1: EMPTY_SOON
     - Priority 2: BALANCED with deficit
3. **Greedy allocation** (Python, in-memory):
   - For each source (sorted by priority, then available DESC):
     - Find nearest sinks (sorted by priority, then distance ASC)
     - Compute distance via haversine or `ST_Distance`
     - Skip if distance > MAX_DISTANCE_M (default 5000 m)
     - Compute `move = min(source.available, sink.needed)`
     - Check sink capacity: don't exceed `capacity - predicted_bikes`
     - If `move > 0`: record job, decrement source/sink budgets
4. Truncate `rebalancing_jobs` and bulk-insert new jobs.

**Output:**
- `rebalancing_jobs`: from_station_id, to_station_id, bikes_to_move, distance_m, created_at

**Why capacity checks?** Prevents overfilling sinks or draining sources beyond safe limits.

---

### Example Walkthrough

**Scenario:**
- Station A: capacity 20, predicted 18 → **FULL_SOON**, target 10, available = 8
- Station B: capacity 20, predicted 2 → **EMPTY_SOON**, target 10, needed = 8
- Distance A→B: 2000 m (within 5000 m limit)

**Result:**
- Rebalancing job created: `from_station_id=A, to_station_id=B, bikes_to_move=8, distance_m=2000`

**After move (hypothetical):**
- Station A: 18 - 8 = 10 (now **BALANCED**)
- Station B: 2 + 8 = 10 (now **BALANCED**)

---

## Database Schema

### Core Tables

| Table | Purpose | Key Columns |
|-------|---------|-------------|
| **station** | Station metadata with location | station_id (PK), station_name, geom (PostGIS POINT) |
| **trip_history** | Raw trip records | ride_id (PK), started_at, ended_at, start_station_id, end_station_id |
| **station_inventory** | Real-time state (updated by GBFS poller) | station_id (PK), current_bikes, capacity, last_reported |
| **station_15min_demand** | Historical demand averages | (station_id, day_of_week, hour_of_day, quarter_hour) PK, avg_arrivals_15m, avg_departures_15m, avg_net_flow_15m |
| **forecast_station_status** | Short-term predictions | (station_id, forecast_ts) PK, predicted_bikes_15m, risk_status (enum) |
| **rebalancing_jobs** | Actionable moves | job_id (PK), from_station_id, to_station_id, bikes_to_move, distance_m, created_at |

### Indexes & Performance

**Key indexes** (defined in `db/sql/indexes.sql`):
- **Spatial GiST index** on `station.geom` for distance queries
- **Composite indexes** on `trip_history(start_station_id, started_at)` and `(end_station_id, ended_at)` for time-range scans
- **Index on** `station_15min_demand(station_id, day_of_week, hour_of_day, quarter_hour)` for forecast lookups
- **Index on** `forecast_station_status(station_id, forecast_ts DESC)` for latest forecast queries

**Optimization tips:**
- Use `COPY` for bulk CSV ingestion (faster than INSERTs)
- Partition `trip_history` by time (monthly) for large datasets
- Run `ANALYZE` after large loads to update planner stats
- Consider materialized views for `station_15min_demand` with REFRESH CONCURRENTLY

---

## Setup & Configuration

### Prerequisites

- **PostgreSQL 16** running and accessible
- **PostGIS extension** enabled (auto-created by schema file)
- **Python 3.11** (scripts tested on 3.11)
- Python dependencies:
  ```bash
  pip install sqlalchemy psycopg2-binary python-dotenv
  ```

### Configuration

Create a `.env` file in the project root with:

```bash
# Database connection (choose one approach)
DATABASE_URL=postgresql://user:password@host:5432/baywheels

# OR individual params
POSTGRES_USER=postgres
POSTGRES_PASSWORD=yourpassword
POSTGRES_HOST=localhost
POSTGRES_DB=baywheels
DB_PORT=5432

# Data paths
DATA_DIR=db/data/
STATION_CSV_PATH=db/data/202509-baywheels-tripdata.csv

# Ingestion
BATCH_SIZE=1000

# Forecasting thresholds
EMPTY_THRESHOLD=2
FULL_MARGIN=3

# Rebalancing
MAX_DISTANCE_M=5000
```

### Database Schema Setup

Run from repo root:

```bash
# Create schema (tables, PostGIS extension)
psql -h <host> -U <user> -d <db> -f db/sql/schema.sql

# Add indexes for performance
psql -h <host> -U <user> -d <db> -f db/sql/indexes.sql
```

---

## Running the Pipeline

### Recommended: Use Shell Orchestration Scripts

**Make scripts executable (once):**
```bash
chmod +x db/run_ingest_pipeline.sh db/run_forecast_pipeline.sh
```

### 1. Ingest Pipeline (One-time or Backfill)

Place CSV files in `db/data/`, then run:

```bash
./db/run_ingest_pipeline.sh
```

**This runs:**
1. `db/populate_stations.py` — extract stations from CSV
2. `db/load_trips.py` — ingest trips into `trip_history`
3. `db/build_station_flow_15min.py` — aggregate into `station_15min_demand`

**When to run:** Initial setup, or when adding historical data.

---

### 2. Forecast Pipeline (Regular/Scheduled)

After `station_inventory` is updated (by GBFS poller), run:

```bash
./db/run_forecast_pipeline.sh
```

**This runs:**
1. `db/run_forecast.py` — predict bike counts and risk levels
2. `db/build_suggestions.py` — generate rebalancing jobs

**When to run:** Continuously (via cron, Airflow, or after inventory updates).

**Example cron job (every 15 minutes):**
```bash
*/15 * * * * cd /path/to/bay_wheels_balancer && ./db/run_forecast_pipeline.sh >> logs/forecast.log 2>&1
```

**Notes:**
- Both scripts auto-source `.env` and activate `bay-wheels` virtualenv if present.
- Logs are printed to stdout; redirect to files for production use.

---

## Manual Script Execution

For finer control or debugging, run individual Python scripts:

### Populate Stations (Optional)
```bash
python db/populate_stations.py
```
Extracts distinct stations from CSV and upserts into `station` table with geometry.

### Ingest Trips
```bash
python db/load_trips.py
```
Reads CSV files from `DATA_DIR`, upserts stations, inserts trips into `trip_history`.

### Aggregate Historical Demand
```bash
python db/build_station_flow_15min.py
```
Buckets trips by (day_of_week, hour_of_day, quarter_hour), computes averages, writes to `station_15min_demand`.

### Run Forecast
```bash
python db/run_forecast.py
```
Predicts short-term station status using historical demand + current inventory, writes to `forecast_station_status`.

### Build Rebalancing Jobs
```bash
python db/build_suggestions.py
```
Computes rebalancing jobs using forecasts, dynamic targets (50% capacity), PostGIS distance, and capacity checks. Truncates and replaces `rebalancing_jobs`.

---

## Performance & Optimization

### Indexing Strategy

All indexes are in `db/sql/indexes.sql`:
- **PostGIS GiST** on `station.geom` for `ST_Distance` queries
- **Composite indexes** on `trip_history` for fast station + time filtering
- **Index on** `station_15min_demand` for forecast lookups
- **Indexes on** `forecast_station_status` for latest forecast + risk filtering

### Large Dataset Recommendations

1. **Partitioning**: Partition `trip_history` by time (monthly):
   ```sql
   CREATE TABLE trip_history_2025_12 PARTITION OF trip_history
     FOR VALUES FROM ('2025-12-01') TO ('2026-01-01');
   ```

2. **Bulk loading**: Use `COPY` instead of INSERT for CSVs:
   ```sql
   COPY trip_history(ride_id, started_at, ended_at, start_station_id, end_station_id)
   FROM '/path/to/file.csv' WITH (FORMAT csv, HEADER true);
   ```

3. **Materialized views**: Convert `station_15min_demand` to a materialized view:
   ```sql
   CREATE MATERIALIZED VIEW mv_station_15min_demand AS
     SELECT ... FROM trip_history ...;
   REFRESH MATERIALIZED VIEW CONCURRENTLY mv_station_15min_demand;
   ```

4. **Maintenance**: Run `ANALYZE` after large loads:
   ```sql
   ANALYZE trip_history;
   ANALYZE station_15min_demand;
   ```

5. **Query tuning**: Use `EXPLAIN (ANALYZE, BUFFERS)` to verify index usage.

### Environment Variable Reference

| Variable | Default | Purpose |
|----------|---------|---------|
| `DATA_DIR` | `db/data/` | CSV input directory |
| `BATCH_SIZE` | `1000` | Batch size for trip inserts |
| `STATION_CSV_PATH` | `db/data/202509-baywheels-tripdata.csv` | CSV for station population |
| `EMPTY_THRESHOLD` | `2` | Min bikes for `empty_soon` classification |
| `FULL_MARGIN` | `3` | Bikes below capacity for `full_soon` |
| `MAX_DISTANCE_M` | `5000` | Max rebalancing distance (meters) |
| `FORECAST_TS` | `NOW()` | Override forecast timestamp (for testing) |

---

## Data Dependencies

```
trip_history
    ↓
station_15min_demand
    ↓
forecast_station_status ← station_inventory (updated by GBFS poller)
    ↓
rebalancing_jobs
```

**Critical**: `station_inventory` must be populated (by Person C's GBFS poller) before running forecasts. Without it, forecasts will have no baseline `current_bikes`.

---

## Testing & Verification

### System Verification Script

To verify data integrity, view sample outputs, and analyze query performance (including before/after indexing comparison), use the comprehensive test script:

**File:** `db/sql/test_cases.sql`

**Usage:**
```bash
PGPASSWORD=baywheels psql -U baywheels -d baywheels -h localhost -p 5432 -f db/sql/test_cases.sql > db/sql/test_cases_output.txt 2>&1
```

**What it tests:**
1. **Database Overview** - Size, row counts, table statistics
2. **Data Integrity Checks** - 6 validation tests with ✓ PASS/✗ FAIL indicators:
   - Valid station geometry
   - Trip-station referential integrity
   - Valid timestamps (started_at < ended_at)
   - Inventory within capacity bounds
   - Forecast predictions in valid range
   - No orphaned demand records
3. **Sample Data Outputs** - Representative data from all tables
4. **Analytical Queries** - Busiest stations, at-risk stations, trip patterns
5. **Index Verification** - Current indexes and usage statistics
6. **Query Performance Comparison** - EXPLAIN ANALYZE for 5 key queries showing index impact
7. **Performance Metrics** - Database size, cache hit ratio, connection stats
8. **Index Impact Comparison** - Direct cost comparison of indexed vs sequential scans
9. **System Health Check** - Dead tuples, long-running queries

**Output:** `db/sql/test_cases_output.txt` contains full results suitable for screenshots and documentation.

**Key Metrics to Review:**
- All integrity checks should show ✓ PASS
- Query plans should prefer "Index Scan" over "Seq Scan"
- Planning/Execution times demonstrate index effectiveness
- Cache hit ratio should be >90% for optimal performance

---

## Troubleshooting

**Q: Forecast always returns BALANCED?**
- Check if `station_inventory` has data: `SELECT COUNT(*) FROM station_inventory;`
- Check if `station_15min_demand` is populated: `SELECT COUNT(*) FROM station_15min_demand;`

**Q: No rebalancing jobs generated?**
- Verify forecasts exist: `SELECT * FROM forecast_station_status LIMIT 10;`
- Check if any stations are `empty_soon` or `full_soon`: `SELECT risk_status, COUNT(*) FROM forecast_station_status GROUP BY risk_status;`

**Q: Scripts fail with "tuple index out of range"?**
- Ensure scripts use `.mappings()` for SQLAlchemy result rows (already fixed in current version).

**Q: PostGIS extension not found?**
- Install PostGIS: `sudo apt install postgresql-16-postgis-3` (Ubuntu) or `brew install postgis` (macOS).
- Create extension manually: `CREATE EXTENSION postgis;`

**Q: Test cases script fails or returns empty output?**
- Verify database connection: `psql -U baywheels -d baywheels -h localhost -c "SELECT version();"`
- Ensure all tables are populated: Run ingest and forecast pipelines first
- Check PostgreSQL version supports all features (requires PostgreSQL 12+, PostGIS 3+)

---

## Files & Responsibilities

| File | Purpose |
|------|---------|
| `db/sql/schema.sql` | Database schema (tables, PostGIS extension) |
| `db/sql/indexes.sql` | Performance indexes (spatial, composite) |
| `db/populate_stations.py` | Extract stations from CSV → `station` table |
| `db/load_trips.py` | Ingest trips → `trip_history` |
| `db/build_station_flow_15min.py` | Aggregate trips → `station_15min_demand` |
| `db/run_forecast.py` | Predict bike counts → `forecast_station_status` |
| `db/build_suggestions.py` | Generate moves → `rebalancing_jobs` |
| `db/run_ingest_pipeline.sh` | Orchestration: populate + load + aggregate |
| `db/run_forecast_pipeline.sh` | Orchestration: forecast + suggestions |
| `db/sql/test_cases.sql` | Comprehensive verification script (integrity + performance) |
| `db/sql/test_cases_output.txt` | Output from test cases (for documentation/screenshots) |

---

## Next Steps

1. **Initial setup**: Run schema SQL, load historical CSVs with ingest pipeline.
2. **Verify data**: Check row counts in `trip_history`, `station_15min_demand`.
3. **Integrate GBFS poller** (Person C): Populate `station_inventory` with live data.
4. **Run forecast pipeline**: Generate predictions and rebalancing jobs.
5. **Schedule forecast pipeline**: Set up cron/Airflow to run every 15 minutes.
6. **Monitor & tune**: Use `EXPLAIN`, check index usage, adjust thresholds as needed.

For advanced optimization (partitioning, materialized views, BRIN indexes), see inline comments in `db/sql/indexes.sql`.
