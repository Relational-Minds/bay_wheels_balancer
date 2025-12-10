-- Comprehensive indexes for Bay Wheels Station Balancer (Person A)
-- Run after: psql -f db/sql/schema.sql
-- Purpose: optimize query performance for ingestion, aggregation, forecasting, and rebalancing

-- ============================================================================
-- 1. SPATIAL INDEXES (PostGIS)
-- ============================================================================
-- Used by: build_suggestions.py (ST_Distance for nearest-neighbor queries)
-- Benefit: fast KNN queries and distance calculations

CREATE INDEX IF NOT EXISTS idx_station_geom_gist 
    ON station USING GIST (geom);

-- ============================================================================
-- 2. TRIP_HISTORY INDEXES
-- ============================================================================
-- Used by: load_trips.py, build_station_flow_15min.py
-- Benefit: accelerate filtering by station + time range

-- Simple indexes for individual columns
CREATE INDEX IF NOT EXISTS idx_trip_start_station_id 
    ON trip_history (start_station_id);
CREATE INDEX IF NOT EXISTS idx_trip_end_station_id   
    ON trip_history (end_station_id);

-- Composite index: station_id + timestamp (used in aggregation queries)
-- Scans trips for a specific station within a time range efficiently
CREATE INDEX IF NOT EXISTS idx_trip_history_start_station_started_at
    ON trip_history (start_station_id, started_at);
CREATE INDEX IF NOT EXISTS idx_trip_history_end_station_ended_at
    ON trip_history (end_station_id, ended_at);

-- Time range indexes (for broad time-based filters)
CREATE INDEX IF NOT EXISTS idx_trip_started_at
    ON trip_history (started_at);
CREATE INDEX IF NOT EXISTS idx_trip_ended_at
    ON trip_history (ended_at);

-- ============================================================================
-- 3. STATION_15MIN_DEMAND INDEXES
-- ============================================================================
-- Used by: run_forecast.py (lookup demand patterns by station + bucket)
-- Benefit: fast bucket lookups during forecasting

-- Primary key already creates an index, but adding explicit one for clarity
CREATE INDEX IF NOT EXISTS idx_station_15min_demand_station_bucket
    ON station_15min_demand (station_id, day_of_week, hour_of_day, quarter_hour);

-- Partial index: high-traffic stations (if needed for very large deployments)
-- Helps forecast queries on busy stations
CREATE INDEX IF NOT EXISTS idx_station_15min_demand_station_only
    ON station_15min_demand (station_id);

-- ============================================================================
-- 4. FORECAST_STATION_STATUS INDEXES
-- ============================================================================
-- Used by: build_suggestions.py (join latest forecast per station)
-- Benefit: fast lookups and ordering by forecast_ts

-- Latest forecast per station is often queried; this helps with ORDER BY + DISTINCT ON
CREATE INDEX IF NOT EXISTS idx_forecast_station_status_station_ts_desc
    ON forecast_station_status (station_id, forecast_ts DESC);

-- Risk status filtering (for finding FULL_SOON / EMPTY_SOON stations)
CREATE INDEX IF NOT EXISTS idx_forecast_station_status_risk_status
    ON forecast_station_status (risk_status);

-- Composite: station + risk (used in rebalancing logic)
CREATE INDEX IF NOT EXISTS idx_forecast_station_status_station_risk
    ON forecast_station_status (station_id, risk_status);

-- ============================================================================
-- 5. REBALANCING_JOBS INDEXES
-- ============================================================================
-- Used by: queries on rebalancing_jobs table (reporting, analytics)
-- Benefit: fast lookups by source/sink station or timestamp

CREATE INDEX IF NOT EXISTS idx_rebalancing_jobs_from_station
    ON rebalancing_jobs (from_station_id);
CREATE INDEX IF NOT EXISTS idx_rebalancing_jobs_to_station
    ON rebalancing_jobs (to_station_id);
CREATE INDEX IF NOT EXISTS idx_rebalancing_jobs_created_at
    ON rebalancing_jobs (created_at DESC);

-- Composite: for queries filtering by from+to stations
CREATE INDEX IF NOT EXISTS idx_rebalancing_jobs_from_to
    ON rebalancing_jobs (from_station_id, to_station_id);

-- ============================================================================
-- 6. STATION_INVENTORY INDEXES
-- ============================================================================
-- Used by: run_forecast.py (join station_inventory with forecasts)
-- Benefit: fast lookups by station; capacity-based filters if needed

CREATE INDEX IF NOT EXISTS idx_station_inventory_capacity
    ON station_inventory (capacity) WHERE capacity > 0;

-- ============================================================================
-- 7. SUGGESTION_CANDIDATES INDEXES (Legacy, kept for compatibility)
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_suggestion_candidates_from_station
    ON suggestion_candidates (from_station_id);
CREATE INDEX IF NOT EXISTS idx_suggestion_candidates_to_station
    ON suggestion_candidates (to_station_id);
CREATE INDEX IF NOT EXISTS idx_suggestion_candidates_created_at
    ON suggestion_candidates (created_at DESC);

-- ============================================================================
-- NOTES ON PERFORMANCE & MAINTENANCE
-- ============================================================================
--
-- Index Strategy:
-- - Composite indexes on (station_id, timestamp/bucket) are used heavily in aggregation.
-- - Spatial GiST index on station.geom accelerates ST_Distance queries.
-- - Risk status + station indexes speed up forecasting logic filters.
--
-- Maintenance:
-- - Run ANALYZE after large data loads to update index statistics:
--   ANALYZE trip_history;
--   ANALYZE station_15min_demand;
--   ANALYZE forecast_station_status;
--   ANALYZE rebalancing_jobs;
--
-- - For very large trip_history (millions of rows), consider:
--   1. CLUSTER trip_history USING idx_trip_history_start_station_started_at;
--   2. Partition trip_history by time range (monthly or weekly).
--   3. Use BRIN index for old/archive partitions.
--
-- - Monitor index bloat: pg_stat_user_indexes view or pgAdmin.
--   REINDEX INDEX idx_name; if bloat is high.
--
-- Query Tuning:
-- - Use EXPLAIN (ANALYZE, BUFFERS) to verify index usage:
--   EXPLAIN (ANALYZE, BUFFERS) SELECT ... FROM trip_history WHERE start_station_id = '123' AND started_at > '2025-01-01';
--
-- - Verify planner stats are up-to-date:
--   SELECT * FROM pg_stat_user_indexes WHERE schemaname = 'public';
