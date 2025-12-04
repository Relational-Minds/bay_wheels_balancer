-- ======= Sample Stations (5 demo stations around SF) =======
INSERT INTO stations (station_id, name, capacity, lat, lon, geom) VALUES
('st_01', 'Market & 8th', 27, 37.7766, -122.4169, ST_SetSRID(ST_MakePoint(-122.4169, 37.7766), 4326)),
('st_02', '2nd & Harrison', 21, 37.7838, -122.3926, ST_SetSRID(ST_MakePoint(-122.3926, 37.7838), 4326)),
('st_03', 'Civic Center', 31, 37.7793, -122.4192, ST_SetSRID(ST_MakePoint(-122.4192, 37.7793), 4326)),
('st_04', 'Valencia & 16th', 19, 37.7646, -122.4216, ST_SetSRID(ST_MakePoint(-122.4216, 37.7646), 4326)),
('st_05', 'Townsend & 4th', 23, 37.7771, -122.3949, ST_SetSRID(ST_MakePoint(-122.3949, 37.7771), 4326))
ON CONFLICT (station_id) DO NOTHING;

-- ======= Seed a few "latest" live snapshots =======
-- Simulate critical, warning, and balanced inventory states
INSERT INTO station_status (station_id, num_bikes_available, num_docks_available, last_reported, ts) VALUES
('st_01', 1, 26, NOW() - INTERVAL '1 minute', NOW() - INTERVAL '30 seconds'),
('st_02', 10, 11, NOW() - INTERVAL '2 minutes', NOW() - INTERVAL '90 seconds'),
('st_03', 25, 6,  NOW() - INTERVAL '90 seconds', NOW() - INTERVAL '45 seconds'),
('st_04', 2, 17,  NOW() - INTERVAL '3 minutes', NOW() - INTERVAL '100 seconds'),
('st_05', 21, 2,  NOW() - INTERVAL '2 minutes', NOW() - INTERVAL '70 seconds');

-- ======= A few historical trips to populate flows =======
-- Last hour: some trips between stations
INSERT INTO trips (start_station_id, end_station_id, started_at, ended_at) VALUES
('st_01', 'st_02', NOW() - INTERVAL '50 minutes', NOW() - INTERVAL '45 minutes'),
('st_02', 'st_03', NOW() - INTERVAL '40 minutes', NOW() - INTERVAL '35 minutes'),
('st_02', 'st_01', NOW() - INTERVAL '30 minutes', NOW() - INTERVAL '25 minutes'),
('st_03', 'st_02', NOW() - INTERVAL '20 minutes', NOW() - INTERVAL '15 minutes'),
('st_04', 'st_05', NOW() - INTERVAL '70 minutes', NOW() - INTERVAL '65 minutes'),
('st_05', 'st_04', NOW() - INTERVAL '60 minutes', NOW() - INTERVAL '55 minutes');

-- ======= Initial tasks to demo backend later =======
INSERT INTO tasks (task_id, src_station_id, dst_station_id, quantity, status, created_at)
VALUES
(1, 'st_02', 'st_01', 6, 'pending', NOW() - INTERVAL '10 minutes'),
(2, 'st_03', 'st_01', 4, 'assigned', NOW() - INTERVAL '20 minutes'),
(3, 'st_05', 'st_04', 5, 'completed', NOW() - INTERVAL '30 minutes')
ON CONFLICT (task_id) DO NOTHING;

-- ======= Assignment history referencing tasks =======
INSERT INTO assignments (assignment_id, task_id, assignee, assigned_at, completed_at)
VALUES
(1, 2, 'worker_anna', NOW() - INTERVAL '18 minutes', NULL),
(2, 3, 'worker_ben', NOW() - INTERVAL '28 minutes', NOW() - INTERVAL '5 minutes')
ON CONFLICT (assignment_id) DO NOTHING;

-- ======= Backend SQLAlchemy tables (if present) =======
-- The following seed data targets the backend-owned tables created by app.db.models:
--   - suggestions   (id, from_station_id, to_station_id, qty, reason, created_at)
--   - backend_tasks (id, from_station_id, to_station_id, qty, reason, status, worker_id, created_at)
-- These inserts are safe to run only in a database where those tables exist.

-- Seed a few ML-generated suggestions
INSERT INTO suggestions (id, from_station_id, to_station_id, qty, reason, created_at)
VALUES
  (1, 1, 2, 5, 'Shift bikes from a near-full station to a low-bikes station', NOW() - INTERVAL '15 minutes'),
  (2, 2, 3, 3, 'Expected demand spike near Civic Center', NOW() - INTERVAL '10 minutes'),
  (3, 5, 4, 4, 'Even out inventory between Townsend & 4th and Valencia & 16th', NOW() - INTERVAL '5 minutes')
ON CONFLICT (id) DO NOTHING;

-- Seed backend tasks that mirror approved suggestions
INSERT INTO backend_tasks (id, from_station_id, to_station_id, qty, reason, status, worker_id, created_at)
VALUES
  (1, 1, 2, 5, 'Shift bikes from a near-full station to a low-bikes station', 'ready',    NULL,          NOW() - INTERVAL '12 minutes'),
  (2, 2, 3, 3, 'Expected demand spike near Civic Center',                      'assigned', 'worker_cli', NOW() - INTERVAL '9 minutes'),
  (3, 5, 4, 4, 'Even out inventory between Townsend & 4th and Valencia & 16th','completed','worker_ui', NOW() - INTERVAL '20 minutes')
ON CONFLICT (id) DO NOTHING;

-- First refresh so MVs reflect seed data
REFRESH MATERIALIZED VIEW station_flows;
REFRESH MATERIALIZED VIEW imbalance_scores;
