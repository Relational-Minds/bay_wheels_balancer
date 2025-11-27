-- Enable PostGIS
CREATE EXTENSION IF NOT EXISTS postgis;

-- ========== Core Tables ==========

-- Station metadata (from station_information.json)
CREATE TABLE IF NOT EXISTS stations (
  station_id TEXT PRIMARY KEY,
  name       TEXT NOT NULL,
  capacity   INT,
  lat        DOUBLE PRECISION,
  lon        DOUBLE PRECISION,
  geom       GEOGRAPHY(Point, 4326)
);

-- Live status snapshots (from station_status.json)
CREATE TABLE IF NOT EXISTS station_status (
  station_id TEXT REFERENCES stations(station_id),
  num_bikes_available INT,
  num_docks_available INT,
  last_reported       TIMESTAMP,
  ts                  TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_station_status_ts ON station_status(ts);
CREATE INDEX IF NOT EXISTS idx_station_status_station_ts
  ON station_status(station_id, ts DESC);

-- Historical trips (subset or full)
CREATE TABLE IF NOT EXISTS trips (
  trip_id BIGSERIAL PRIMARY KEY,
  start_station_id TEXT,
  end_station_id   TEXT,
  started_at       TIMESTAMP,
  ended_at         TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_trips_started_at ON trips(started_at);
CREATE INDEX IF NOT EXISTS idx_trips_end_station ON trips(end_station_id);
CREATE INDEX IF NOT EXISTS idx_trips_start_station ON trips(start_station_id);

-- (Optional) Rebalancing tasks scaffolding so backend can plug in later
CREATE TABLE IF NOT EXISTS tasks (
  task_id BIGSERIAL PRIMARY KEY,
  src_station_id TEXT,
  dst_station_id TEXT,
  quantity INT CHECK (quantity >= 0),
  status TEXT DEFAULT 'pending', -- pending | assigned | completed | canceled
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS assignments (
  assignment_id BIGSERIAL PRIMARY KEY,
  task_id BIGINT REFERENCES tasks(task_id),
  assignee TEXT,
  assigned_at TIMESTAMP DEFAULT NOW(),
  completed_at TIMESTAMP
);

-- ========== Materialized Views ==========

-- 15-minute inflow/outflow aggregate from trips
CREATE MATERIALIZED VIEW IF NOT EXISTS station_flows AS
SELECT
  s.station_id,
  date_trunc('minute', t.started_at)
    - make_interval(mins => (extract(minute from t.started_at)::int % 15)) AS time_bin,
  COUNT(*) FILTER (WHERE t.start_station_id = s.station_id) AS outflow,
  COUNT(*) FILTER (WHERE t.end_station_id   = s.station_id) AS inflow
FROM stations s
LEFT JOIN trips t
  ON (t.start_station_id = s.station_id OR t.end_station_id = s.station_id)
GROUP BY s.station_id, time_bin;

CREATE INDEX IF NOT EXISTS idx_station_flows_sid_bin
  ON station_flows(station_id, time_bin);

-- Simple rule-based imbalance scoring using the latest station_status
CREATE MATERIALIZED VIEW IF NOT EXISTS imbalance_scores AS
WITH latest AS (
  SELECT DISTINCT ON (station_id)
         station_id, num_bikes_available, num_docks_available, last_reported, ts
  FROM station_status
  ORDER BY station_id, ts DESC
)
SELECT
  s.station_id,
  s.name,
  COALESCE(l.num_bikes_available, 0) AS bikes,
  COALESCE(l.num_docks_available, 0) AS docks,
  NOW() AS computed_at,
  -- Score: higher = more urgent
  (CASE WHEN COALESCE(l.num_bikes_available,0) <= 2 THEN 70 ELSE 0 END) +
  (CASE WHEN COALESCE(l.num_docks_available,0) <= 2 THEN 30 ELSE 0 END) AS score
FROM stations s
LEFT JOIN latest l USING (station_id);

CREATE INDEX IF NOT EXISTS idx_imbalance_scores_score
  ON imbalance_scores(score DESC);

-- Helper function to refresh MVs (the worker can call this later)
CREATE OR REPLACE FUNCTION refresh_balancer_materialized_views()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM 1;
  REFRESH MATERIALIZED VIEW CONCURRENTLY station_flows;
  REFRESH MATERIALIZED VIEW CONCURRENTLY imbalance_scores;
END;
$$;
