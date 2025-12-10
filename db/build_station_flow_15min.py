"""Build historical demand patterns: aggregate trip_history into (day_of_week, hour_of_day, quarter_hour) buckets.

Logical steps:
1. Read trip_history records.
2. For departures: bucket by started_at; for arrivals: bucket by ended_at.
3. Bucket definition: day_of_week (0–6), hour_of_day (0–23), quarter_hour (0–3 for 0, 15, 30, 45 min).
4. Aggregate: count departures and arrivals per bucket.
5. Compute historical averages: avg_arrivals_15m, avg_departures_15m, avg_net_flow_15m.
6. Upsert into station_15min_demand table.

Configuration: uses `.env` or environment variables. No CLI args.

Env vars supported:
- `DATABASE_URL` (optional) or POSTGRES_USER/POSTGRES_PASSWORD/POSTGRES_HOST/DB_PORT/POSTGRES_DB
"""

import logging
import os

from sqlalchemy import create_engine, text
from dotenv import load_dotenv

LOG = logging.getLogger("build_station_flow_15min")


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

    # SQL to compute historical demand patterns
    # Step 1: Extract departures by (station_id, day_of_week, hour_of_day, quarter_hour)
    # Step 2: Extract arrivals by (station_id, day_of_week, hour_of_day, quarter_hour)
    # Step 3: Union and aggregate, computing counts and averages
    # Step 4: Upsert into station_15min_demand
    aggregation_sql = text("""
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
    INSERT INTO station_15min_demand (station_id, day_of_week, hour_of_day, quarter_hour, avg_arrivals_15m, avg_departures_15m, avg_net_flow_15m)
    SELECT station_id, day_of_week, hour_of_day, quarter_hour, avg_arrivals_15m, avg_departures_15m, avg_net_flow_15m
    FROM aggregated
    ON CONFLICT (station_id, day_of_week, hour_of_day, quarter_hour) DO UPDATE
      SET avg_arrivals_15m = EXCLUDED.avg_arrivals_15m,
          avg_departures_15m = EXCLUDED.avg_departures_15m,
          avg_net_flow_15m = EXCLUDED.avg_net_flow_15m;
    """)

    with engine.begin() as conn:
        LOG.info("Building historical demand patterns from trip_history...")
        conn.execute(aggregation_sql)
        LOG.info("Demand patterns successfully written to station_15min_demand")


if __name__ == '__main__':
    main()
