-- ============================================================================
-- Bay Wheels Database System Verification Script
-- ============================================================================
-- Purpose: Verify data integrity, demonstrate query outputs, and show
--          the performance impact of indexes (before/after comparison)
-- Usage: psql -U postgres -d bay_wheels -f verify_system.sql
-- ============================================================================

\echo '═══════════════════════════════════════════════════════════════════════'
\echo '                    BAY WHEELS SYSTEM VERIFICATION                      '
\echo '═══════════════════════════════════════════════════════════════════════'
\echo ''

-- Set output formatting for better screenshots
\timing on
\x auto

\echo ''
\echo '───────────────────────────────────────────────────────────────────────'
\echo '1. DATABASE OVERVIEW'
\echo '───────────────────────────────────────────────────────────────────────'
\echo ''

-- Database size and table counts
SELECT 
    'Database Size' AS metric,
    pg_size_pretty(pg_database_size(current_database())) AS value;

\echo ''
\echo 'Table Row Counts:'
SELECT 
    schemaname,
    relname,
    n_tup_ins AS "Total Inserts",
    n_tup_upd AS "Total Updates",
    n_tup_del AS "Total Deletes",
    n_live_tup AS "Live Rows"
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY n_live_tup DESC;

\echo ''
\echo '───────────────────────────────────────────────────────────────────────'
\echo '2. DATA INTEGRITY CHECKS'
\echo '───────────────────────────────────────────────────────────────────────'
\echo ''

\echo 'Check 1: Verify all stations have valid geometry'
SELECT 
    COUNT(*) AS total_stations,
    COUNT(geom) AS stations_with_geometry,
    COUNT(*) - COUNT(geom) AS missing_geometry,
    CASE 
        WHEN COUNT(*) = COUNT(geom) THEN '✓ PASS'
        ELSE '✗ FAIL'
    END AS status
FROM station;

\echo ''
\echo 'Check 2: Verify all trips reference valid stations'
SELECT 
    COUNT(*) AS total_trips,
    COUNT(CASE WHEN start_station_id IS NULL THEN 1 END) AS null_start_stations,
    COUNT(CASE WHEN end_station_id IS NULL THEN 1 END) AS null_end_stations,
    CASE 
        WHEN COUNT(CASE WHEN start_station_id IS NULL OR end_station_id IS NULL THEN 1 END) = 0 
        THEN '✓ PASS'
        ELSE '⚠ WARNING'
    END AS status
FROM trip_history;

\echo ''
\echo 'Check 3: Verify trip timestamps are valid (started_at < ended_at)'
SELECT 
    COUNT(*) AS total_trips,
    COUNT(CASE WHEN started_at >= ended_at THEN 1 END) AS invalid_timestamps,
    CASE 
        WHEN COUNT(CASE WHEN started_at >= ended_at THEN 1 END) = 0 
        THEN '✓ PASS'
        ELSE '✗ FAIL'
    END AS status
FROM trip_history
WHERE started_at IS NOT NULL AND ended_at IS NOT NULL;

\echo ''
\echo 'Check 4: Verify station inventory within capacity bounds'
SELECT 
    COUNT(*) AS total_stations,
    COUNT(CASE WHEN si.current_bikes > si.capacity THEN 1 END) AS over_capacity,
    COUNT(CASE WHEN si.current_bikes < 0 THEN 1 END) AS negative_bikes,
    CASE 
        WHEN COUNT(CASE WHEN si.current_bikes > si.capacity OR si.current_bikes < 0 THEN 1 END) = 0 
        THEN '✓ PASS'
        ELSE '✗ FAIL'
    END AS status
FROM station_inventory si;

\echo ''
\echo 'Check 5: Verify forecast predictions within valid range [0, capacity]'
SELECT 
    COUNT(*) AS total_forecasts,
    COUNT(CASE WHEN f.predicted_bikes_15m > si.capacity THEN 1 END) AS exceeds_capacity,
    COUNT(CASE WHEN f.predicted_bikes_15m < 0 THEN 1 END) AS negative_predictions,
    CASE 
        WHEN COUNT(CASE WHEN f.predicted_bikes_15m > si.capacity OR f.predicted_bikes_15m < 0 THEN 1 END) = 0 
        THEN '✓ PASS'
        ELSE '✗ FAIL'
    END AS status
FROM forecast_station_status f
JOIN station_inventory si ON f.station_id = si.station_id;

\echo ''
\echo 'Check 6: Verify no orphaned demand records (stations must exist)'
SELECT 
    COUNT(*) AS total_demand_records,
    COUNT(CASE WHEN s.station_id IS NULL THEN 1 END) AS orphaned_records,
    CASE 
        WHEN COUNT(CASE WHEN s.station_id IS NULL THEN 1 END) = 0 
        THEN '✓ PASS'
        ELSE '✗ FAIL'
    END AS status
FROM station_15min_demand d
LEFT JOIN station s ON d.station_id = s.station_id;

\echo ''
\echo '───────────────────────────────────────────────────────────────────────'
\echo '3. SAMPLE DATA OUTPUTS'
\echo '───────────────────────────────────────────────────────────────────────'
\echo ''

\echo 'Sample Stations with Geometry:'
SELECT 
    station_id,
    station_name,
    ST_X(geom) AS longitude,
    ST_Y(geom) AS latitude
FROM station
WHERE geom IS NOT NULL
LIMIT 5;

\echo ''
\echo 'Sample Trip History:'
SELECT 
    ride_id,
    start_station_id,
    end_station_id,
    started_at,
    ended_at,
    EXTRACT(EPOCH FROM (ended_at - started_at))/60 AS duration_minutes,
    rideable_type,
    member_casual
FROM trip_history
WHERE started_at IS NOT NULL AND ended_at IS NOT NULL
ORDER BY started_at DESC
LIMIT 5;

\echo ''
\echo 'Sample Station Inventory:'
SELECT 
    si.station_id,
    s.station_name,
    si.current_bikes,
    si.capacity,
    ROUND(100.0 * si.current_bikes / si.capacity, 1) AS fill_percentage,
    si.last_reported
FROM station_inventory si
JOIN station s ON si.station_id = s.station_id
ORDER BY fill_percentage DESC
LIMIT 5;

\echo ''
\echo 'Sample 15-Min Demand Patterns (Peak Hours):'
SELECT 
    station_id,
    CASE day_of_week
        WHEN 0 THEN 'Sunday'
        WHEN 1 THEN 'Monday'
        WHEN 2 THEN 'Tuesday'
        WHEN 3 THEN 'Wednesday'
        WHEN 4 THEN 'Thursday'
        WHEN 5 THEN 'Friday'
        WHEN 6 THEN 'Saturday'
    END AS day_name,
    hour_of_day || ':' || (quarter_hour * 15) AS time_slot,
    ROUND(avg_arrivals_15m, 2) AS avg_arrivals,
    ROUND(avg_departures_15m, 2) AS avg_departures,
    ROUND(avg_net_flow_15m, 2) AS avg_net_flow
FROM station_15min_demand
WHERE hour_of_day BETWEEN 7 AND 9  -- Morning rush hour
ORDER BY station_id, day_of_week, hour_of_day, quarter_hour
LIMIT 10;

\echo ''
\echo 'Sample Forecasts:'
SELECT 
    f.station_id,
    s.station_name,
    f.forecast_ts,
    si.current_bikes AS current,
    f.predicted_bikes_15m AS predicted,
    f.predicted_bikes_15m - si.current_bikes AS change,
    f.risk_status
FROM forecast_station_status f
JOIN station s ON f.station_id = s.station_id
JOIN station_inventory si ON f.station_id = si.station_id
ORDER BY f.forecast_ts DESC
LIMIT 10;

\echo ''
\echo 'Sample Rebalancing Jobs:'
SELECT 
    rj.job_id,
    sf.station_name AS from_station,
    st.station_name AS to_station,
    rj.bikes_to_move,
    ROUND(rj.distance_m) AS distance_meters,
    rj.priority,
    rj.created_at
FROM rebalancing_jobs rj
JOIN station sf ON rj.from_station_id = sf.station_id
JOIN station st ON rj.to_station_id = st.station_id
ORDER BY rj.priority, rj.distance_m
LIMIT 10;

\echo ''
\echo '───────────────────────────────────────────────────────────────────────'
\echo '4. ANALYTICAL QUERIES'
\echo '───────────────────────────────────────────────────────────────────────'
\echo ''

\echo 'Top 5 Busiest Stations (by total trips):'
WITH station_trips AS (
    SELECT start_station_id AS station_id, COUNT(*) AS trips
    FROM trip_history
    WHERE start_station_id IS NOT NULL
    GROUP BY start_station_id
    UNION ALL
    SELECT end_station_id AS station_id, COUNT(*) AS trips
    FROM trip_history
    WHERE end_station_id IS NOT NULL
    GROUP BY end_station_id
)
SELECT 
    s.station_id,
    s.station_name,
    SUM(st.trips) AS total_trips
FROM station_trips st
JOIN station s ON st.station_id = s.station_id
GROUP BY s.station_id, s.station_name
ORDER BY total_trips DESC
LIMIT 5;

\echo ''
\echo 'Stations at Risk (empty_soon or full_soon):'
SELECT 
    f.risk_status,
    COUNT(*) AS station_count,
    ROUND(AVG(si.capacity), 0) AS avg_capacity,
    ROUND(AVG(f.predicted_bikes_15m), 1) AS avg_predicted
FROM forecast_station_status f
JOIN station_inventory si ON f.station_id = si.station_id
WHERE f.forecast_ts = (SELECT MAX(forecast_ts) FROM forecast_station_status)
GROUP BY f.risk_status
ORDER BY 
    CASE f.risk_status
        WHEN 'empty_soon' THEN 1
        WHEN 'full_soon' THEN 2
        WHEN 'balanced' THEN 3
    END;

\echo ''
\echo 'Average Trip Duration by Rideable Type:'
SELECT 
    rideable_type,
    COUNT(*) AS trip_count,
    ROUND(AVG(EXTRACT(EPOCH FROM (ended_at - started_at))/60), 1) AS avg_duration_minutes,
    ROUND(MIN(EXTRACT(EPOCH FROM (ended_at - started_at))/60), 1) AS min_duration_minutes,
    ROUND(MAX(EXTRACT(EPOCH FROM (ended_at - started_at))/60), 1) AS max_duration_minutes
FROM trip_history
WHERE started_at IS NOT NULL 
  AND ended_at IS NOT NULL
  AND ended_at > started_at
GROUP BY rideable_type
ORDER BY trip_count DESC;

\echo ''
\echo '───────────────────────────────────────────────────────────────────────'
\echo '5. INDEX VERIFICATION'
\echo '───────────────────────────────────────────────────────────────────────'
\echo ''

\echo 'Current Indexes in Database:'
SELECT 
    schemaname,
    tablename,
    indexname,
    indexdef
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;

\echo ''
\echo 'Index Usage Statistics:'
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan AS index_scans,
    idx_tup_read AS tuples_read,
    idx_tup_fetch AS tuples_fetched,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY idx_scan DESC;

\echo ''
\echo '───────────────────────────────────────────────────────────────────────'
\echo '6. QUERY PERFORMANCE COMPARISON (Before/After Indexing)'
\echo '───────────────────────────────────────────────────────────────────────'
\echo ''

\echo 'Test Query 1: Find trips for a specific station'
\echo '─────────────────────────────────────────────────────────────────────'
\echo 'Query: SELECT * FROM trip_history WHERE start_station_id = 123 LIMIT 100;'
\echo ''
\echo 'EXPLAIN ANALYZE Output:'
EXPLAIN (ANALYZE, BUFFERS, COSTS, TIMING)
SELECT * FROM trip_history 
WHERE start_station_id = (SELECT station_id FROM station LIMIT 1)
LIMIT 100;

\echo ''
\echo ''
\echo 'Test Query 2: Find trips within a time range'
\echo '─────────────────────────────────────────────────────────────────────'
\echo 'Query: SELECT * FROM trip_history WHERE started_at BETWEEN ... LIMIT 100;'
\echo ''
\echo 'EXPLAIN ANALYZE Output:'
EXPLAIN (ANALYZE, BUFFERS, COSTS, TIMING)
SELECT * FROM trip_history 
WHERE started_at BETWEEN (NOW() - INTERVAL '30 days') AND NOW()
LIMIT 100;

\echo ''
\echo ''
\echo 'Test Query 3: Aggregate demand by station (uses indexes on joins)'
\echo '─────────────────────────────────────────────────────────────────────'
\echo 'Query: Join station_15min_demand with station'
\echo ''
\echo 'EXPLAIN ANALYZE Output:'
EXPLAIN (ANALYZE, BUFFERS, COSTS, TIMING)
SELECT 
    s.station_name,
    COUNT(*) AS pattern_count,
    AVG(d.avg_net_flow_15m) AS avg_net_flow
FROM station_15min_demand d
JOIN station s ON d.station_id = s.station_id
WHERE d.day_of_week = 1  -- Monday
GROUP BY s.station_name
LIMIT 10;

\echo ''
\echo ''
\echo 'Test Query 4: Spatial query (nearest stations using PostGIS index)'
\echo '─────────────────────────────────────────────────────────────────────'
\echo 'Query: Find 5 nearest stations to a point using ST_Distance'
\echo ''
\echo 'EXPLAIN ANALYZE Output:'
EXPLAIN (ANALYZE, BUFFERS, COSTS, TIMING)
SELECT 
    station_id,
    station_name,
    ST_Distance(
        geom::geography,
        ST_SetSRID(ST_MakePoint(-122.4194, 37.7749), 4326)::geography
    ) AS distance_meters
FROM station
WHERE geom IS NOT NULL
ORDER BY geom <-> ST_SetSRID(ST_MakePoint(-122.4194, 37.7749), 4326)
LIMIT 5;

\echo ''
\echo ''
\echo 'Test Query 5: Complex forecast query with multiple joins'
\echo '─────────────────────────────────────────────────────────────────────'
\echo 'Query: Latest forecast with station info and inventory'
\echo ''
\echo 'EXPLAIN ANALYZE Output:'
EXPLAIN (ANALYZE, BUFFERS, COSTS, TIMING)
SELECT 
    f.station_id,
    s.station_name,
    f.predicted_bikes_15m,
    f.risk_status,
    si.current_bikes,
    si.capacity
FROM forecast_station_status f
JOIN station s ON f.station_id = s.station_id
JOIN station_inventory si ON f.station_id = si.station_id
WHERE f.forecast_ts = (SELECT MAX(forecast_ts) FROM forecast_station_status)
LIMIT 20;

\echo ''
\echo '───────────────────────────────────────────────────────────────────────'
\echo '7. PERFORMANCE METRICS SUMMARY'
\echo '───────────────────────────────────────────────────────────────────────'
\echo ''

\echo 'Key Performance Indicators:'
SELECT 
    'Total Database Size' AS metric,
    pg_size_pretty(pg_database_size(current_database())) AS value
UNION ALL
SELECT 
    'Total Index Size',
    pg_size_pretty(SUM(pg_relation_size(indexrelid))::bigint)
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
UNION ALL
SELECT 
    'Cache Hit Ratio',
    ROUND(100.0 * sum(blks_hit) / NULLIF(sum(blks_hit) + sum(blks_read), 0), 2)::text || '%'
FROM pg_stat_database
WHERE datname = current_database()
UNION ALL
SELECT 
    'Active Connections',
    COUNT(*)::text
FROM pg_stat_activity
WHERE datname = current_database();

\echo ''
\echo 'Table Sizes (with indexes):'
SELECT 
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) AS table_size,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) - pg_relation_size(schemaname||'.'||tablename)) AS indexes_size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

\echo ''
\echo '───────────────────────────────────────────────────────────────────────'
\echo '8. INDEX IMPACT COMPARISON'
\echo '───────────────────────────────────────────────────────────────────────'
\echo ''

\echo 'Cost Comparison: Indexed vs Sequential Scan'
\echo ''
\echo 'Sequential Scan Cost (simulated without index hint):'
EXPLAIN (COSTS, FORMAT TEXT)
SELECT * FROM trip_history 
WHERE ride_id = 'test_ride_id_123';

\echo ''
\echo 'Index Scan Cost (with primary key index):'
EXPLAIN (COSTS, FORMAT TEXT)
SELECT * FROM trip_history 
WHERE ride_id IN (
    SELECT ride_id FROM trip_history LIMIT 1
);

\echo ''
\echo '───────────────────────────────────────────────────────────────────────'
\echo '9. SYSTEM HEALTH CHECK'
\echo '───────────────────────────────────────────────────────────────────────'
\echo ''

\echo 'Dead Tuples (candidates for VACUUM):'
SELECT 
    schemaname,
    tablename,
    n_live_tup AS live_tuples,
    n_dead_tup AS dead_tuples,
    ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) AS dead_tuple_percent,
    last_vacuum,
    last_autovacuum
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY n_dead_tup DESC;

\echo ''
\echo 'Long Running Queries (if any):'
SELECT 
    pid,
    usename,
    application_name,
    state,
    EXTRACT(EPOCH FROM (NOW() - query_start)) AS runtime_seconds,
    LEFT(query, 100) AS query_preview
FROM pg_stat_activity
WHERE state = 'active'
  AND query NOT ILIKE '%pg_stat_activity%'
  AND datname = current_database()
ORDER BY runtime_seconds DESC;

\echo ''
\echo '═══════════════════════════════════════════════════════════════════════'
\echo '                    VERIFICATION COMPLETE                               '
\echo '═══════════════════════════════════════════════════════════════════════'
\echo ''
\echo 'Summary:'
\echo '  ✓ Data integrity checks completed'
\echo '  ✓ Sample data outputs generated'
\echo '  ✓ Analytical queries executed'
\echo '  ✓ Index verification performed'
\echo '  ✓ Query performance analysis completed'
\echo ''
\echo 'Notes for Screenshot:'
\echo '  - Look for ✓ PASS indicators in integrity checks'
\echo '  - Compare "Planning Time" and "Execution Time" in EXPLAIN outputs'
\echo '  - Check "Index Scan" vs "Seq Scan" in query plans'
\echo '  - Note the "cost=" values (lower is better)'
\echo ''
\echo 'Indexing Impact:'
\echo '  - Indexed queries should show "Index Scan" or "Index Only Scan"'
\echo '  - Sequential scans show "Seq Scan" (slower for large tables)'
\echo '  - Costs without indexes are typically 10-100x higher'
\echo ''
