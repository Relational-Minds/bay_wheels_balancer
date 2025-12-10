# Complex SQL Queries Reference

This document catalogs all complex SQL queries used in the Bay Wheels database system with detailed annotations explaining their purpose, logic, and results.

---

## Table of Contents

1. [Historical Demand Aggregation](#1-historical-demand-aggregation)
2. [Forecasting with Fallback Chain](#2-forecasting-with-fallback-chain)
3. [Rebalancing Job Generation](#3-rebalancing-job-generation)
4. [Station Geometry Upsert](#4-station-geometry-upsert)
5. [Trip Ingestion](#5-trip-ingestion)

---

## 1. Historical Demand Aggregation

**Script:** `db/build_station_flow_15min.py`

**Purpose:** Aggregate historical trip data into 15-minute demand patterns per station, computing average arrivals, departures, and net flow for each time bucket.

**Query:**

```sql
WITH dep AS (
  -- Departures: group by start_station_id and bucket (day_of_week, hour_of_day, quarter_hour)
  SELECT
    start_station_id AS station_id,
    EXTRACT(dow FROM started_at)::int AS day_of_week,
    EXTRACT(hour FROM started_at)::int AS hour_of_day,
    (EXTRACT(minute FROM started_at)::int) / 15 AS quarter_hour,
    COUNT(*) AS departures,
    0 AS arrivals
  FROM trip_history
  WHERE start_station_id IS NOT NULL AND started_at IS NOT NULL
  GROUP BY station_id, day_of_week, hour_of_day, quarter_hour
), arr AS (
  -- Arrivals: group by end_station_id and bucket (day_of_week, hour_of_day, quarter_hour)
  SELECT
    end_station_id AS station_id,
    EXTRACT(dow FROM ended_at)::int AS day_of_week,
    EXTRACT(hour FROM ended_at)::int AS hour_of_day,
    (EXTRACT(minute FROM ended_at)::int) / 15 AS quarter_hour,
    0 AS departures,
    COUNT(*) AS arrivals
  FROM trip_history
  WHERE end_station_id IS NOT NULL AND ended_at IS NOT NULL
  GROUP BY station_id, day_of_week, hour_of_day, quarter_hour
), combined AS (
  -- Union departures and arrivals
  SELECT * FROM dep
  UNION ALL
  SELECT * FROM arr
), aggregated AS (
  -- Sum arrivals/departures per bucket, then compute average and net flow
  SELECT
    station_id,
    day_of_week,
    hour_of_day,
    quarter_hour,
    AVG(arrivals) AS avg_arrivals_15m,
    AVG(departures) AS avg_departures_15m,
    AVG(arrivals - departures) AS avg_net_flow_15m
  FROM combined
  GROUP BY station_id, day_of_week, hour_of_day, quarter_hour
)
INSERT INTO station_15min_demand (
  station_id, day_of_week, hour_of_day, quarter_hour, 
  avg_arrivals_15m, avg_departures_15m, avg_net_flow_15m
)
SELECT 
  station_id, day_of_week, hour_of_day, quarter_hour, 
  avg_arrivals_15m, avg_departures_15m, avg_net_flow_15m
FROM aggregated
ON CONFLICT (station_id, day_of_week, hour_of_day, quarter_hour) DO UPDATE
  SET avg_arrivals_15m = EXCLUDED.avg_arrivals_15m,
      avg_departures_15m = EXCLUDED.avg_departures_15m,
      avg_net_flow_15m = EXCLUDED.avg_net_flow_15m;
```

**Annotations:**

### CTE 1: `dep` (Departures)
- **Input:** `trip_history` table
- **Logic:** 
  - Groups trips by `start_station_id` (station where trip began)
  - Extracts temporal bucket from `started_at`:
    - `day_of_week`: 0=Sunday, 1=Monday, ..., 6=Saturday
    - `hour_of_day`: 0-23 (24-hour format)
    - `quarter_hour`: 0-3 (0=:00-:14, 1=:15-:29, 2=:30-:44, 3=:45-:59)
  - Counts departures per bucket
- **Output:** Rows with `(station_id, day_of_week, hour_of_day, quarter_hour, departures, 0)`

### CTE 2: `arr` (Arrivals)
- **Input:** `trip_history` table
- **Logic:** 
  - Groups trips by `end_station_id` (station where trip ended)
  - Uses same temporal bucketing on `ended_at`
  - Counts arrivals per bucket
- **Output:** Rows with `(station_id, day_of_week, hour_of_day, quarter_hour, 0, arrivals)`

### CTE 3: `combined`
- **Logic:** Unions departures and arrivals into a single result set
- **Why UNION ALL?** We want to keep separate rows for departures and arrivals at the same bucket to compute separate averages

### CTE 4: `aggregated`
- **Logic:**
  - Groups by `(station_id, day_of_week, hour_of_day, quarter_hour)`
  - Computes:
    - `avg_arrivals_15m`: Average number of trips ending at this station in this time bucket
    - `avg_departures_15m`: Average number of trips starting at this station in this time bucket
    - `avg_net_flow_15m`: Average net change (arrivals - departures)
- **Interpretation:**
  - Positive `avg_net_flow_15m`: Station typically **gains** bikes during this period
  - Negative `avg_net_flow_15m`: Station typically **loses** bikes during this period

### Final INSERT
- **Conflict Resolution:** `ON CONFLICT ... DO UPDATE` makes this query **idempotent** — can be re-run to update existing patterns with new data
- **Result:** `station_15min_demand` table populated with historical demand patterns

**Use Case:** Foundation for forecasting. Tells us "Station X typically gains 5 bikes on Mondays at 8:00-8:15 AM."

---

## 2. Forecasting with Fallback Chain

**Script:** `db/run_forecast.py`

**Purpose:** Predict future bike counts at each station using current inventory + historical demand patterns with a multi-level fallback strategy when exact patterns are unavailable.

**Query:**

```sql
WITH current_state AS (
  -- Read current inventory and compute bucket from last_reported
  SELECT
    si.station_id,
    si.current_bikes,
    si.capacity,
    si.last_reported,
    EXTRACT(dow FROM si.last_reported)::int AS day_of_week,
    EXTRACT(hour FROM si.last_reported)::int AS hour_of_day,
    (EXTRACT(minute FROM si.last_reported)::int) / 15 AS quarter_hour
  FROM station_inventory si
), demand_lookup AS (
  -- Lookup expected net flow with fallback chain
  SELECT
    cs.station_id,
    cs.current_bikes,
    cs.capacity,
    cs.last_reported,
    COALESCE(
      -- Exact match: day_of_week, hour_of_day, quarter_hour
      (SELECT avg_net_flow_15m FROM station_15min_demand d
       WHERE d.station_id = cs.station_id
       AND d.day_of_week = cs.day_of_week
       AND d.hour_of_day = cs.hour_of_day
       AND d.quarter_hour = cs.quarter_hour
       LIMIT 1),
      -- Fallback 1: same day/hour, any quarter
      (SELECT AVG(avg_net_flow_15m) FROM station_15min_demand d
       WHERE d.station_id = cs.station_id
       AND d.day_of_week = cs.day_of_week
       AND d.hour_of_day = cs.hour_of_day
       LIMIT 1),
      -- Fallback 2: any day, same hour/quarter
      (SELECT AVG(avg_net_flow_15m) FROM station_15min_demand d
       WHERE d.station_id = cs.station_id
       AND d.hour_of_day = cs.hour_of_day
       AND d.quarter_hour = cs.quarter_hour
       LIMIT 1),
      -- Fallback 3: station-level average across all buckets
      (SELECT AVG(avg_net_flow_15m) FROM station_15min_demand d
       WHERE d.station_id = cs.station_id
       LIMIT 1),
      -- Fallback 4: no historical data, assume 0
      0.0
    )::numeric AS expected_net_flow
  FROM current_state cs
), predictions AS (
  -- Compute predicted bikes and categorize
  SELECT
    station_id,
    last_reported AS forecast_ts,
    GREATEST(0, LEAST(capacity, ROUND(current_bikes + expected_net_flow)::int)) AS predicted_bikes,
    CASE
      WHEN ROUND(current_bikes + expected_net_flow)::int <= :empty_threshold THEN 'empty_soon'::forecast_risk_status
      WHEN ROUND(current_bikes + expected_net_flow)::int >= (capacity - :full_margin) THEN 'full_soon'::forecast_risk_status
      ELSE 'balanced'::forecast_risk_status
    END AS risk_status
  FROM demand_lookup
)
INSERT INTO forecast_station_status (station_id, forecast_ts, predicted_bikes_15m, risk_status)
SELECT station_id, forecast_ts, predicted_bikes, risk_status FROM predictions
ON CONFLICT (station_id, forecast_ts) DO UPDATE
  SET predicted_bikes_15m = EXCLUDED.predicted_bikes_15m,
      risk_status = EXCLUDED.risk_status;
```

**Annotations:**

### CTE 1: `current_state`
- **Input:** `station_inventory` (current bikes, capacity, timestamp of last update)
- **Logic:**
  - Reads current state for all stations
  - Converts `last_reported` timestamp into temporal bucket (day_of_week, hour_of_day, quarter_hour)
- **Output:** Current state with computed time bucket

### CTE 2: `demand_lookup` (Fallback Chain Logic)
- **Purpose:** Find the best historical demand pattern to predict future flow
- **COALESCE Fallback Strategy:**

#### Priority 1: Exact Match
```sql
SELECT avg_net_flow_15m FROM station_15min_demand d
WHERE d.station_id = cs.station_id
AND d.day_of_week = cs.day_of_week
AND d.hour_of_day = cs.hour_of_day
AND d.quarter_hour = cs.quarter_hour
```
- **Use when:** We have historical data for this **exact time pattern** (e.g., "Monday 8:00-8:15 AM")
- **Most accurate:** Same station, same day-of-week, same hour, same 15-min slot

#### Priority 2: Same Day & Hour, Any Quarter
```sql
SELECT AVG(avg_net_flow_15m) FROM station_15min_demand d
WHERE d.station_id = cs.station_id
AND d.day_of_week = cs.day_of_week
AND d.hour_of_day = cs.hour_of_day
```
- **Use when:** No exact quarter match, but we have data for this day/hour
- **Averages** all 15-minute slots within that hour (e.g., average of 8:00, 8:15, 8:30, 8:45)

#### Priority 3: Any Day, Same Hour & Quarter
```sql
SELECT AVG(avg_net_flow_15m) FROM station_15min_demand d
WHERE d.station_id = cs.station_id
AND d.hour_of_day = cs.hour_of_day
AND d.quarter_hour = cs.quarter_hour
```
- **Use when:** We have data for this time-of-day but not for this specific day-of-week
- **Averages** across all days (e.g., "8:00-8:15 AM on any day")

#### Priority 4: Station Average
```sql
SELECT AVG(avg_net_flow_15m) FROM station_15min_demand d
WHERE d.station_id = cs.station_id
```
- **Use when:** Very sparse data — average across **all time buckets** for this station
- **Least accurate** but better than nothing

#### Priority 5: Default Zero
```sql
0.0
```
- **Use when:** No historical data exists for this station at all
- **Assumes** no net change in bikes

### CTE 3: `predictions`
- **Formula:** `predicted_bikes = CLAMP(current_bikes + expected_net_flow, 0, capacity)`
  - `GREATEST(0, ...)`: Floor at 0 (can't have negative bikes)
  - `LEAST(capacity, ...)`: Cap at capacity (can't exceed station capacity)
- **Risk Categorization:**
  - `empty_soon`: predicted ≤ `empty_threshold` (default 2) — station running out
  - `full_soon`: predicted ≥ `capacity - full_margin` (default capacity-3) — station nearly full
  - `balanced`: everything else — station is fine

### Final INSERT
- **Idempotent:** `ON CONFLICT ... DO UPDATE` allows re-running with updated inventory
- **Result:** `forecast_station_status` table updated with predictions

**Example:**
- Station A: `current_bikes=10`, `capacity=20`, `expected_net_flow=-5` → `predicted=5` → `balanced`
- Station B: `current_bikes=18`, `capacity=20`, `expected_net_flow=+3` → `predicted=20` (clamped) → `full_soon`

---

## 3. Rebalancing Job Generation

**Script:** `db/build_suggestions.py`

**Purpose:** Generate actionable rebalancing jobs by matching "full" stations (sources) with "empty" stations (sinks) using PostGIS spatial queries and capacity-aware allocation.

**Query Structure:**

The query is implemented in **Python** (not pure SQL) due to the complexity of greedy allocation with capacity tracking. However, it uses this key SQL to load data:

```sql
WITH latest_forecast AS (
  SELECT DISTINCT ON (station_id) 
    station_id, forecast_ts, predicted_bikes_15m, risk_status
  FROM forecast_station_status
  ORDER BY station_id, forecast_ts DESC
)
SELECT
  lf.station_id,
  lf.predicted_bikes_15m,
  lf.risk_status::text AS risk_status,
  si.capacity,
  ROUND(si.capacity * 0.5)::int AS target_level,
  ST_X(s.geom) AS lon,
  ST_Y(s.geom) AS lat
FROM latest_forecast lf
JOIN station_inventory si ON lf.station_id = si.station_id
JOIN station s ON lf.station_id = s.station_id;
```

**Annotations:**

### CTE: `latest_forecast`
- **Purpose:** Get the **most recent** forecast for each station
- **Logic:** `DISTINCT ON (station_id)` with `ORDER BY forecast_ts DESC` returns the latest row per station
- **Why needed:** `forecast_station_status` may have multiple forecasts per station (historical runs)

### Main SELECT
- **Joins:**
  - `station_inventory`: Get `capacity` (max bikes station can hold)
  - `station`: Get PostGIS geometry for distance calculations
- **Computed Fields:**
  - `target_level = 50% of capacity`: Dynamic target (not hardcoded)
  - `ST_X(geom)`, `ST_Y(geom)`: Extract longitude and latitude from PostGIS POINT

### Python Greedy Allocation Logic

After loading the data, the Python script performs:

```python
# Classify stations
sources = stations where predicted > target (have bikes to give)
sinks = stations where predicted < target (need bikes)

# Priority levels
priority 1: FULL_SOON sources / EMPTY_SOON sinks
priority 2: BALANCED sources/sinks with surplus/deficit

# For each source (sorted by priority, then available DESC):
for source in sources:
    # Find nearest sinks (sorted by priority, then distance ASC)
    candidates = sinks within MAX_DISTANCE_M
    
    for sink in candidates:
        # Compute safe move amount
        move = min(
            source.available,           # Don't give more than surplus
            sink.needed,                # Don't give more than deficit
            sink.capacity - sink.predicted  # Don't exceed sink capacity
        )
        
        if move > 0:
            # Record job
            jobs.append({
                from_station: source.station_id,
                to_station: sink.station_id,
                bikes_to_move: move,
                distance_m: haversine(source, sink)
            })
            
            # Decrement budgets
            source.available -= move
            sink.needed -= move
```

**Distance Calculation:**

Uses **Haversine formula** (great-circle distance):
```python
def haversine_m(lat1, lon1, lat2, lon2):
    R = 6371000.0  # Earth radius in meters
    dlat = radians(lat2 - lat1)
    dlon = radians(lon2 - lon1)
    a = sin(dlat/2)**2 + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlon/2)**2
    c = 2 * asin(sqrt(a))
    return R * c
```

**Capacity Constraints:**

The script ensures:
1. **Source constraint:** Don't give more bikes than `available = predicted - target`
2. **Sink constraint:** Don't exceed sink capacity: `capacity - predicted`
3. **Distance constraint:** Skip pairs beyond `MAX_DISTANCE_M` (default 5000m)

**Final Output:**
- `TRUNCATE rebalancing_jobs` — clear old jobs
- Bulk `INSERT` new jobs

**Result Example:**
```
from_station_id | to_station_id | bikes_to_move | distance_m
----------------|---------------|---------------|------------
A               | B             | 8             | 2000
C               | D             | 5             | 3500
```

**Why Python instead of pure SQL?**
- Need to **track remaining capacity** as we allocate moves
- Greedy algorithm requires **stateful iteration** (hard in SQL)
- Alternative: Use SQL window functions + recursive CTEs (complex and less maintainable)

---

## 4. Station Geometry Upsert

**Script:** `db/load_trips.py`, `db/populate_stations.py`

**Purpose:** Insert or update station records with PostGIS geometry from latitude/longitude coordinates.

**Query:**

```sql
INSERT INTO station (station_id, station_name, geom) 
VALUES (
  :station_id, 
  :station_name, 
  ST_SetSRID(ST_MakePoint(:station_lng, :station_lat), 4326)
)
ON CONFLICT (station_id) DO UPDATE 
SET station_name = EXCLUDED.station_name, 
    geom = COALESCE(EXCLUDED.geom, station.geom)
```

**Annotations:**

### PostGIS Functions
- **`ST_MakePoint(longitude, latitude)`:**
  - Creates a PostGIS POINT geometry
  - **Order matters:** longitude first, then latitude (X, Y convention)
- **`ST_SetSRID(geometry, 4326)`:**
  - Sets Spatial Reference System Identifier (SRID)
  - `4326` = WGS 84 (standard GPS coordinate system)
  - Required for distance calculations with `ST_Distance`

### Conflict Resolution
- **`ON CONFLICT (station_id)`:** If station already exists
- **`DO UPDATE`:** Update existing row instead of failing
- **`COALESCE(EXCLUDED.geom, station.geom)`:**
  - If new data has geometry → use it
  - If new data is NULL → keep existing geometry
  - Prevents accidentally overwriting valid coordinates with NULLs

**Use Case:** CSV files may contain station info multiple times; this ensures we keep one record per station with the most complete data.

---

## 5. Trip Ingestion

**Script:** `db/load_trips.py`

**Purpose:** Bulk insert trip records from CSV files with idempotent behavior (skip duplicates).

**Query:**

```sql
INSERT INTO trip_history (
  ride_id, start_station_id, end_station_id, 
  started_at, ended_at, rideable_type, member_casual
)
VALUES (
  :ride_id, :start_station_id, :end_station_id, 
  :started_at, :ended_at, :rideable_type, :member_casual
)
ON CONFLICT (ride_id) DO NOTHING
```

**Annotations:**

### Idempotent Ingestion
- **`ON CONFLICT (ride_id) DO NOTHING`:**
  - If trip with this `ride_id` already exists → skip insert
  - Allows re-running ingestion without creating duplicates
  - **Critical** for backfill operations and recovery from failures

### Batched Execution
The Python script batches inserts:
```python
BATCH_SIZE = 1000  # configurable via env
for batch in chunks(trips, BATCH_SIZE):
    conn.execute(stmt, batch)
```

**Why batching?**
- Single large transaction = faster than many small ones
- Reduces network round-trips
- PostgreSQL optimizes bulk inserts

**Alternative for huge datasets:**
```sql
COPY trip_history(ride_id, started_at, ended_at, ...)
FROM '/path/to/file.csv' WITH (FORMAT csv, HEADER true);
```
- 10-100x faster than INSERT for millions of rows
- Requires file access on DB server (or stdin piping)

---

## Query Performance Tips

### 1. Use EXPLAIN ANALYZE
```sql
EXPLAIN (ANALYZE, BUFFERS) 
WITH dep AS (...) 
SELECT * FROM aggregated;
```
- Shows actual execution time and row counts
- `BUFFERS` shows I/O statistics

### 2. Check Index Usage
```sql
SELECT schemaname, tablename, indexname, idx_scan
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY idx_scan;
```
- `idx_scan = 0` means index is never used (candidate for removal)

### 3. Update Statistics
```sql
ANALYZE trip_history;
ANALYZE station_15min_demand;
```
- Run after large data loads
- Helps planner choose optimal query plans

### 4. Monitor Query Performance
```sql
SELECT query, calls, total_time, mean_time
FROM pg_stat_statements
WHERE query LIKE '%trip_history%'
ORDER BY total_time DESC
LIMIT 10;
```
- Requires `pg_stat_statements` extension
- Shows slowest queries in production

---

## Common Query Patterns

### Pattern 1: Temporal Bucketing
```sql
-- Convert timestamp to 15-minute buckets
EXTRACT(dow FROM timestamp)::int AS day_of_week,
EXTRACT(hour FROM timestamp)::int AS hour_of_day,
(EXTRACT(minute FROM timestamp)::int) / 15 AS quarter_hour
```

### Pattern 2: COALESCE Fallback Chain
```sql
COALESCE(
  (SELECT exact_match ...),
  (SELECT broader_match ...),
  (SELECT even_broader ...),
  default_value
)
```
- Returns first non-NULL result
- Implements priority-based fallback logic

### Pattern 3: Clamping Values
```sql
GREATEST(min_value, LEAST(max_value, computed_value))
```
- Clamps `computed_value` to `[min_value, max_value]`
- Example: `GREATEST(0, LEAST(20, predicted))` → clamp to [0, 20]

### Pattern 4: Enum Casting
```sql
'empty_soon'::forecast_risk_status
```
- Explicitly casts text to custom enum type
- Required when inserting into enum columns

### Pattern 5: PostGIS Distance
```sql
ST_Distance(
  s1.geom::geography,
  s2.geom::geography
)
```
- Cast to `geography` for meter-based distance
- Default `geometry` type uses degree-based distance

---

## Troubleshooting

### Issue: Query timeout on large tables
**Solution:** Add `SET statement_timeout = '5min';` or partition `trip_history` by time.

### Issue: Slow aggregation
**Solution:** Ensure composite indexes exist on `(station_id, timestamp)` columns.

### Issue: Inaccurate forecasts
**Solution:** Check if `station_15min_demand` is populated: `SELECT COUNT(*) FROM station_15min_demand;`

### Issue: No rebalancing jobs generated
**Solution:** Verify forecasts exist with `empty_soon`/`full_soon` status:
```sql
SELECT risk_status, COUNT(*) 
FROM forecast_station_status 
GROUP BY risk_status;
```

---

## Summary

| Query | Purpose | Key Technique | Output Table |
|-------|---------|---------------|--------------|
| **Aggregation** | Historical demand patterns | CTE with UNION ALL, temporal bucketing | `station_15min_demand` |
| **Forecasting** | Predict bike counts | COALESCE fallback chain, clamping | `forecast_station_status` |
| **Rebalancing** | Generate move jobs | PostGIS distance, greedy allocation (Python) | `rebalancing_jobs` |
| **Station Upsert** | Insert/update stations | PostGIS ST_MakePoint, COALESCE | `station` |
| **Trip Ingestion** | Load CSV trips | ON CONFLICT DO NOTHING, batching | `trip_history` |

All queries prioritize:
- **Idempotency** — safe to re-run
- **Performance** — leveraging indexes and CTEs
- **Data quality** — NULL handling, clamping, validation
