#!/usr/bin/env bash
set -euo pipefail

# Orchestration: populate stations -> load trips -> build station flow
# Usage: ./db/run_ingest_pipeline.sh

# Move to repo root (script is in db/)
cd "$(dirname "$0")/.."

# Activate local venv if present
if [ -f "bay-wheels/bin/activate" ]; then
  # shellcheck source=/dev/null
  source bay-wheels/bin/activate
fi

# Load .env if present
if [ -f .env ]; then
  set -a
  # shellcheck source=/dev/null
  source .env
  set +a
fi

echo "[ingest] Starting ingest pipeline: populate_stations -> load_trips -> build_station_flow_15min"

echo "[ingest] Running populate_stations.py"
python db/populate_stations.py

echo "[ingest] Running load_trips.py"
python db/load_trips.py

echo "[ingest] Running build_station_flow_15min.py"
python db/build_station_flow_15min.py

echo "[ingest] Ingest pipeline finished"
