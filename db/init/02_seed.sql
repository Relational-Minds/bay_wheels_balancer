-- ======= Sample Stations (3 demo stations around SF) =======
INSERT INTO stations (station_id, name, capacity, lat, lon, geom) VALUES
('st_01', 'Market & 8th', 27, 37.7766, -122.4169, ST_SetSRID(ST_MakePoint(-122.4169, 37.7766), 4326)),
('st_02', '2nd & Harrison', 21, 37.7838, -122.3926, ST_SetSRID(ST_MakePoint(-122.3926, 37.7838), 4326)),
('st_03', 'Civic Center', 31, 37.7793, -122.4192, ST_SetSRID(ST_MakePoint(-122.4192, 37.7793), 4326))
ON CONFLICT (station_id) DO NOTHING;

-- ======= Seed a few "latest" live snapshots =======
-- Simulate one critical (low bikes), one balanced, one low docks
INSERT INTO station_status (station_id, num_bikes_available, num_docks_available, last_reported, ts) VALUES
('st_01', 1, 26, NOW() - INTERVAL '1 minute', NOW() - INTERVAL '30 seconds'),
('st_02', 10, 11, NOW() - INTERVAL '1 minute', NOW() - INTERVAL '30 seconds'),
('st_03', 25, 6,  NOW() - INTERVAL '1 minute', NOW() - INTERVAL '30 seconds');

-- ======= A few historical trips to populate flows =======
-- Last hour: some trips between stations
INSERT INTO trips (start_station_id, end_station_id, started_at, ended_at) VALUES
('st_01', 'st_02', NOW() - INTERVAL '50 minutes', NOW() - INTERVAL '45 minutes'),
('st_02', 'st_03', NOW() - INTERVAL '40 minutes', NOW() - INTERVAL '35 minutes'),
('st_02', 'st_01', NOW() - INTERVAL '30 minutes', NOW() - INTERVAL '25 minutes'),
('st_03', 'st_02', NOW() - INTERVAL '20 minutes', NOW() - INTERVAL '15 minutes');

-- ======= Initial tasks/assignments to demo backend later =======
INSERT INTO tasks (src_station_id, dst_station_id, quantity, status)
VALUES
('st_02', 'st_01', 6, 'pending'),
('st_03', 'st_01', 4, 'pending');

-- First refresh so MVs reflect seed data
REFRESH MATERIALIZED VIEW station_flows;
REFRESH MATERIALIZED VIEW imbalance_scores;
