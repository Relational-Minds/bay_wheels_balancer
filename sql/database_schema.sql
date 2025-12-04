-- SQL schema and supporting objects for Person A (Data Engineering & Forecasting)
-- Target: Postgres 16
-- Run: psql -f sql/01_schema_person_a.sql

-- Create enum type for forecast risk status
DO $$ BEGIN
    CREATE TYPE forecast_risk_status AS ENUM ('empty_soon','full_soon','balanced');
EXCEPTION
    WHEN duplicate_object THEN NULL; -- ignore if type already exists
END $$;

-- Stations metadata
CREATE TABLE IF NOT EXISTS station (
    station_id VARCHAR(64) PRIMARY KEY,
    station_name VARCHAR(255),
    geom geometry(POINT,4326)
);
-- Use PostGIS geometry for station location; remove legacy lat/lng columns if they exist
CREATE EXTENSION IF NOT EXISTS postgis;
ALTER TABLE station
    DROP COLUMN IF EXISTS station_lat,
    DROP COLUMN IF EXISTS station_lng,
    ADD COLUMN IF NOT EXISTS geom geometry(POINT,4326);

-- Placeholder for current inventory (optional). Team C can populate live snapshots here.
CREATE TABLE IF NOT EXISTS station_inventory (
    station_id VARCHAR(64) PRIMARY KEY REFERENCES station(station_id) ON DELETE CASCADE,
    current_bikes INT DEFAULT 0,
    capacity INT DEFAULT 20,
    last_reported TIMESTAMP WITHOUT TIME ZONE DEFAULT now()
);

-- Historical trips (from CSV ingestion)
CREATE TABLE IF NOT EXISTS trip_history (
    ride_id VARCHAR(64) PRIMARY KEY,
    -- Original columns
    start_station_id VARCHAR(64) REFERENCES station(station_id),
    end_station_id VARCHAR(64) REFERENCES station(station_id),
    started_at TIMESTAMP WITHOUT TIME ZONE,
    ended_at TIMESTAMP WITHOUT TIME ZONE,
    -- Additional columns from sample CSV
    rideable_type VARCHAR(64),
    member_casual VARCHAR(64)
);

-- Indexes to accelerate common queries
CREATE INDEX IF NOT EXISTS idx_trip_start_station ON trip_history(start_station_id);
CREATE INDEX IF NOT EXISTS idx_trip_end_station   ON trip_history(end_station_id);
CREATE INDEX IF NOT EXISTS idx_trip_started_at    ON trip_history(started_at);

-- Historical demand patterns: per-station, per (day_of_week, hour_of_day, quarter_hour)
-- Aggregated from trip_history, storing historical avg arrivals/departures and net flow
CREATE TABLE IF NOT EXISTS station_15min_demand (
    station_id VARCHAR(64) NOT NULL REFERENCES station(station_id) ON DELETE CASCADE,
    day_of_week INT NOT NULL,  -- 0–6 (Monday–Sunday)
    hour_of_day INT NOT NULL,  -- 0–23
    quarter_hour INT NOT NULL, -- 0–3 (corresponds to 0, 15, 30, 45 minutes)
    avg_arrivals_15m NUMERIC NOT NULL DEFAULT 0,
    avg_departures_15m NUMERIC NOT NULL DEFAULT 0,
    avg_net_flow_15m NUMERIC NOT NULL DEFAULT 0,
    PRIMARY KEY (station_id, day_of_week, hour_of_day, quarter_hour)
);

-- Forecast table: predicted bikes for a station for a future bucket
CREATE TABLE IF NOT EXISTS forecast_station_status (
    station_id VARCHAR(64) NOT NULL REFERENCES station(station_id) ON DELETE CASCADE,
    forecast_ts TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    predicted_bikes_15m INT NOT NULL,
    risk_status forecast_risk_status NOT NULL,
    PRIMARY KEY (station_id, forecast_ts)
);

-- Suggestion candidates: simple moves proposed by forecasting logic
CREATE TABLE IF NOT EXISTS suggestion_candidates (
    suggestion_id BIGSERIAL PRIMARY KEY,
    from_station_id VARCHAR(64) REFERENCES station(station_id) ON DELETE SET NULL,
    to_station_id   VARCHAR(64) REFERENCES station(station_id) ON DELETE SET NULL,
    qty INT NOT NULL,
    reason VARCHAR(255),
    created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT now()
);

-- Rebalancing jobs: computed moves from sources (FULL_SOON) to sinks (EMPTY_SOON)
CREATE TABLE IF NOT EXISTS rebalancing_jobs (
    job_id BIGSERIAL PRIMARY KEY,
    from_station_id VARCHAR(64) NOT NULL REFERENCES station(station_id) ON DELETE CASCADE,
    to_station_id VARCHAR(64) NOT NULL REFERENCES station(station_id) ON DELETE CASCADE,
    bikes_to_move INT NOT NULL,
    distance_m NUMERIC,  -- distance in meters using PostGIS
    forecast_ts TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT now()
);


