# Data Engineering & Forecasting

This README explains how to set up the Postgres schema and run the ingestion, historical-demand aggregation, forecasting, and rebalancing job generation.

Prereqs
- Postgres 16 running and accessible.
- PostGIS enabled in the database (the schema file runs `CREATE EXTENSION IF NOT EXISTS postgis;`).
- Python 3.11 (scripts tested on 3.11).
- Install Python dependencies:

```bash
pip install sqlalchemy psycopg2-binary python-dotenv
```

Configuration
- Create a `.env` file.
- Minimum env variables:
  - `DATABASE_URL` or the set `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_HOST`, `POSTGRES_DB`, `DB_PORT`
  - `DATA_DIR` (for `load_trips.py`, default `data/`)
  - `BATCH_SIZE` (for `load_trips.py`, default `1000`)

Quick start

1. Create the database schema (this also creates the PostGIS extension):

```bash
psql -h <host> -U <user> -d <db> -f sql/database_schema_person.sql
```

2. Place your Bay Wheels CSV trip files in the `data/` directory. Each CSV should include columns similar to:
   `ride_id, started_at, ended_at, start_station_id, start_station_name, end_station_id, end_station_name, start_lat, start_lng, end_lat, end_lng`

3. Populate stations — extracts distinct stations from a CSV and upserts into `station` including geometry:

```bash
python scripts/populate_stations.py
```

4. Ingest trips into `trip_history` (reads `DATA_DIR`, uses `.env`):

```bash
python scripts/load_trips.py
```

5. Build historical 15-minute demand patterns (aggregates into `station_15min_demand`):

```bash
python scripts/build_station_flow_15min.py
```

Notes:
- This script buckets trips by (day_of_week, hour_of_day, quarter_hour) and computes historical averages (`avg_arrivals_15m`, `avg_departures_15m`, `avg_net_flow_15m`).

6. Run the forecast (reads `station_inventory`, uses demand patterns and fallback rules):

```bash
python scripts/run_forecast.py
```

Notes:
- `station_inventory` now includes `current_bikes`, `capacity`, and `last_reported` (timestamp); `run_forecast.py` converts `last_reported` into the appropriate 15-min bucket.
- Forecasts are written to `forecast_station_status` and use a fallback chain when historical demand for the exact bucket is missing.
- Configurable env vars: `EMPTY_THRESHOLD` (default 2), `FULL_MARGIN` (default 3).

7. Build rebalancing jobs (distance-based, dynamic target levels):

```bash
python scripts/build_suggestions.py
```

Notes:
- `build_suggestions.py` computes a dynamic `target_level` per station equal to 50% of station `capacity`.
- Sources (stations that can give) and sinks (stations that need) are selected using forecasted values; the script prefers `FULL_SOON`/`EMPTY_SOON` stations and falls back to `BALANCED` stations with surplus/deficit.
- Uses PostGIS `ST_Distance` and respects `MAX_DISTANCE_M` (default 5000 m). Configure with env var `MAX_DISTANCE_M`.
- The script truncates `rebalancing_jobs` and replaces it with the newly computed set each run.

Files and responsibilities
- `sql/01_schema_person_a.sql`: creates tables, PostGIS extension, and supporting objects. It defines `station_15min_demand`, `station_inventory` (with `capacity`), `forecast_station_status`, and `rebalancing_jobs`.
- `scripts/populate_stations.py`: extract distinct stations from CSV and upsert into `station` (inserts geometry via lon/lat).
- `scripts/load_trips.py`: CSV ingestion (idempotent), upserts stations and writes to `trip_history`.
- `scripts/build_station_flow_15min.py`: aggregates `trip_history` into `(day_of_week,hour_of_day,quarter_hour)` buckets and writes `station_15min_demand`.
- `scripts/run_forecast.py`: predicts short-term station status using `station_15min_demand` and `station_inventory`, writes `forecast_station_status`.
- `scripts/build_suggestions.py`: creates `rebalancing_jobs` using forecasted values, dynamic targets, and PostGIS nearest-sink matching.
