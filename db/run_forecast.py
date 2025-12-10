"""Run forecast for station status using historical demand patterns and current inventory.

Logical steps:
1. Read current station state from station_inventory (bikes available, capacity, timestamp).
2. Convert each station's last_reported timestamp into a 15-min bucket: day_of_week, hour_of_day, quarter_hour.
3. Lookup expected net flow from station_15min_demand using the bucket (exact match → fallback chain).
4. Predict 15-minute future bike count: predicted_bikes = current_bikes + expected_net_flow.
5. Clamp to [0, capacity].
6. Categorize station: EMPTY_SOON / FULL_SOON / BALANCED.
7. Write results to forecast_station_status.

Configuration: uses `.env` or environment variables. No CLI args.

Env vars supported:
- `DATABASE_URL` (optional) or POSTGRES_USER/POSTGRES_PASSWORD/POSTGRES_HOST/DB_PORT/POSTGRES_DB
- `EMPTY_THRESHOLD`: bikes at or below this → EMPTY_SOON (default 2)
- `FULL_MARGIN`: capacity - FULL_MARGIN → FULL_SOON (default 3)
"""

import logging
import os
from datetime import datetime

from sqlalchemy import create_engine, text
from dotenv import load_dotenv

LOG = logging.getLogger("run_forecast")


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

    empty_threshold = int(os.environ.get('EMPTY_THRESHOLD', '2'))
    full_margin = int(os.environ.get('FULL_MARGIN', '3'))

    # SQL to:
    # 1. Read current inventory (bikes, capacity, last_reported timestamp)
    # 2. Convert timestamp to bucket (day_of_week, hour_of_day, quarter_hour)
    # 3. Lookup expected_net_flow from station_15min_demand with fallback chain:
    #    - Exact bucket match → same hour/day_of_week → same hour only → station average → 0
    # 4. Predict bikes and categorize
    # 5. Upsert into forecast_station_status
    forecast_sql = text("""
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
    """)

    with engine.begin() as conn:
        LOG.info("Running forecast (empty_threshold=%d, full_margin=%d)...", empty_threshold, full_margin)
        conn.execute(forecast_sql, dict(empty_threshold=empty_threshold, full_margin=full_margin))
        LOG.info("Forecasts written to forecast_station_status")


if __name__ == '__main__':
    main()
