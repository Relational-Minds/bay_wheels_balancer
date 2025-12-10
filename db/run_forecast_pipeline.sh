#!/usr/bin/env bash
set -euo pipefail

# Orchestration: run forecast -> build suggestions
# Usage: ./db/run_forecast_pipeline.sh

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

echo "[forecast] Starting forecast pipeline: run_forecast -> build_suggestions"

echo "[forecast] Running run_forecast.py"
python db/run_forecast.py

echo "[forecast] Running build_suggestions.py"
python db/build_suggestions.py

echo "[forecast] Forecast pipeline finished"
