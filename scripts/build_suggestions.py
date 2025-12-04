"""Build rebalancing jobs using PostGIS distance matching with dynamic target levels.

Logical steps:
1. Read forecast results and station geometry.
2. Compute dynamic target_level = 50% of station capacity (not static).
3. Identify primary sources (FULL_SOON) and sinks (EMPTY_SOON).
4. For each primary source, find nearest sink (EMPTY_SOON or fallback BALANCED with capacity to receive).
5. For each primary sink, find nearest source (FULL_SOON or fallback BALANCED with surplus to give).
6. Use PostGIS ST_Distance with MAX_DISTANCE constraint (skip pairs beyond threshold).
7. Assign moves: move_count = min(available_to_give, needed), respecting forecasted values.

Configuration: uses `.env` / environment variables. No CLI args.

Env vars supported:
- `DATABASE_URL` (optional) or POSTGRES_USER/POSTGRES_PASSWORD/POSTGRES_HOST/DB_PORT/POSTGRES_DB
- `MAX_DISTANCE_M`: max allowed distance in meters (default 5000m = 5km)
"""

import logging
import os

from sqlalchemy import create_engine, text
from dotenv import load_dotenv

LOG = logging.getLogger("build_suggestions")


def build_db_url_from_env():
    user = os.environ.get('POSTGRES_USER', os.environ.get('DB_USER', 'postgres'))
    pwd = os.environ.get('POSTGRES_PASSWORD', os.environ.get('DB_PASSWORD', 'postgres'))
    host = os.environ.get('POSTGRES_HOST', os.environ.get('DB_HOST', 'localhost'))
    port = os.environ.get('DB_PORT', '5432')
    db = os.environ.get('POSTGRES_DB', os.environ.get('DB_NAME', 'baywheels'))
    return f"postgresql://{user}:{pwd}@{host}:{port}/{db}"


def main():
    logging.basicConfig(level=logging.INFO)
    load_dotenv()
    db_url = os.environ.get('DATABASE_URL') or build_db_url_from_env()
    engine = create_engine(db_url)

    max_distance_m = int(os.environ.get('MAX_DISTANCE_M', '5000'))

    # SQL to compute rebalancing jobs using PostGIS distance matching with dynamic target levels
    # Step 1: Get latest forecast and join with station geometry and capacity
    # Step 2: Compute dynamic target_level = 50% of capacity per station
    # Step 3: Classify stations: primary (FULL_SOON/EMPTY_SOON) and fallback (BALANCED with surplus/deficit)
    # Step 4: For each source, find nearest sink (primary first, then fallback) within MAX_DISTANCE
    # Step 5: Upsert into rebalancing_jobs respecting distance and forecasted values
    rebalancing_sql = text("""
    WITH forecast_with_geom AS (
      -- Join latest forecasts with station geometry and capacity
      SELECT
        fs.station_id,
        fs.forecast_ts,
        fs.predicted_bikes_15m,
        fs.risk_status,
        s.geom,
        si.capacity
      FROM forecast_station_status fs
      JOIN station s ON fs.station_id = s.station_id
      JOIN station_inventory si ON fs.station_id = si.station_id
      WHERE fs.forecast_ts = (SELECT MAX(forecast_ts) FROM forecast_station_status)
    ), stations_with_targets AS (
      -- Compute dynamic target_level = 50% of capacity per station
      SELECT
        station_id,
        forecast_ts,
        predicted_bikes_15m,
        risk_status,
        geom,
        capacity,
        ROUND(capacity * 0.5)::int AS target_level
      FROM forecast_with_geom
    ), sources_primary AS (
      -- Primary sources: FULL_SOON stations with surplus to give
      SELECT
        station_id,
        forecast_ts,
        geom,
        capacity,
        target_level,
        GREATEST(0, predicted_bikes_15m - target_level) AS available_to_give,
        predicted_bikes_15m,
        1 AS priority  -- priority 1 = primary source
      FROM stations_with_targets
      WHERE risk_status = 'full_soon'::forecast_risk_status
        AND predicted_bikes_15m > target_level
    ), sources_fallback AS (
      -- Fallback sources: BALANCED stations that can still give away bikes
      SELECT
        station_id,
        forecast_ts,
        geom,
        capacity,
        target_level,
        GREATEST(0, predicted_bikes_15m - target_level) AS available_to_give,
        predicted_bikes_15m,
        2 AS priority  -- priority 2 = fallback source
      FROM stations_with_targets
      WHERE risk_status = 'balanced'::forecast_risk_status
        AND predicted_bikes_15m > target_level
    ), all_sources AS (
      SELECT * FROM sources_primary
      UNION ALL
      SELECT * FROM sources_fallback
    ), sinks_primary AS (
      -- Primary sinks: EMPTY_SOON stations needing bikes
      SELECT
        station_id,
        forecast_ts,
        geom,
        capacity,
        target_level,
        GREATEST(0, target_level - predicted_bikes_15m) AS needed,
        predicted_bikes_15m,
        1 AS priority  -- priority 1 = primary sink
      FROM stations_with_targets
      WHERE risk_status = 'empty_soon'::forecast_risk_status
        AND predicted_bikes_15m < target_level
    ), sinks_fallback AS (
      -- Fallback sinks: BALANCED stations that can still receive bikes
      SELECT
        station_id,
        forecast_ts,
        geom,
        capacity,
        target_level,
        GREATEST(0, target_level - predicted_bikes_15m) AS needed,
        predicted_bikes_15m,
        2 AS priority  -- priority 2 = fallback sink
      FROM stations_with_targets
      WHERE risk_status = 'balanced'::forecast_risk_status
        AND predicted_bikes_15m < target_level
    ), all_sinks AS (
      SELECT * FROM sinks_primary
      UNION ALL
      SELECT * FROM sinks_fallback
    ), source_sink_pairs AS (
      -- For each source, find nearest sink using ST_Distance
      -- Prioritize primary sinks first, then fallback
      SELECT
        src.station_id AS from_station_id,
        snk.station_id AS to_station_id,
        src.forecast_ts,
        src.available_to_give,
        snk.needed,
        LEAST(src.available_to_give, snk.needed) AS move_count,
        ST_Distance(src.geom, snk.geom) AS distance_m,
        src.priority AS source_priority,
        snk.priority AS sink_priority,
        ROW_NUMBER() OVER (
          PARTITION BY src.station_id
          ORDER BY snk.priority ASC, ST_Distance(src.geom, snk.geom) ASC
        ) AS rn
      FROM all_sources src
      CROSS JOIN all_sinks snk
      WHERE ST_Distance(src.geom, snk.geom) <= :max_distance_m  -- Enforce max distance constraint
        AND src.station_id != snk.station_id  -- Don't pair station with itself
    ), ranked_pairs AS (
      -- Keep only the nearest sink for each source (respecting distance constraint)
      SELECT *
      FROM source_sink_pairs
      WHERE rn = 1 AND move_count > 0
    )
    INSERT INTO rebalancing_jobs (from_station_id, to_station_id, bikes_to_move, distance_m, forecast_ts)
    SELECT from_station_id, to_station_id, move_count, distance_m, forecast_ts
    FROM ranked_pairs;
    """)

    with engine.begin() as conn:
      LOG.info("Computing rebalancing jobs (max_distance=%dm, dynamic target=50%% capacity)...", max_distance_m)
      # Replace any existing jobs with fresh computation
      conn.execute(text("TRUNCATE rebalancing_jobs"))
      conn.execute(rebalancing_sql, dict(max_distance_m=max_distance_m))

      # Log summary of created jobs
      result = conn.execute(text(
        "SELECT COUNT(*) as cnt, SUM(bikes_to_move) as total_bikes FROM rebalancing_jobs WHERE created_at >= NOW() - INTERVAL '1 minute'"
      )).mappings().first()
      if result:
        LOG.info("Rebalancing jobs created: count=%s, total_bikes=%s", result['cnt'], result['total_bikes'])


if __name__ == '__main__':
    main()
