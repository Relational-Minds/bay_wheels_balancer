"""Populate station table with distinct start/end stations from a CSV file.

Configuration: uses `.env` or environment variables. No CLI args.

Env vars supported:
- `DATABASE_URL` (optional) or POSTGRES_USER/POSTGRES_PASSWORD/POSTGRES_HOST/DB_PORT/POSTGRES_DB
- `STATION_CSV_PATH`: path to CSV file to read stations from (default: 'db/data/sample.csv')

This script extracts all distinct (start_station_id, start_station_name) and (end_station_id, end_station_name)
pairs from the CSV and upserts them into the `station` table.
"""

import csv
import logging
import os

from sqlalchemy import create_engine, text
from dotenv import load_dotenv

LOG = logging.getLogger("populate_stations")


def build_db_url_from_env():
    user = os.environ.get('POSTGRES_USER', os.environ.get('DB_USER', 'postgres'))
    pwd = os.environ.get('POSTGRES_PASSWORD', os.environ.get('DB_PASSWORD', 'postgres'))
    host = os.environ.get('POSTGRES_HOST', os.environ.get('DB_HOST', 'localhost'))
    port = os.environ.get('DB_PORT', '5432')
    db = os.environ.get('POSTGRES_DB', os.environ.get('DB_NAME', 'baywheels'))
    return f"postgresql://{user}:{pwd}@{host}:{port}/{db}"


def get_cell(row, fieldnames, *names):
    """Return first non-empty value for candidate header names (case-insensitive)."""
    for name in names:
        if name is None:
            continue
        # try direct lookup
        v = row.get(name)
        if v:
            return v
        # try uppercase/lowercase variants
        v = row.get(name.lower()) or row.get(name.upper())
        if v:
            return v
        # try normalized fieldnames
        for fn in fieldnames:
            if fn == name.strip().lower():
                val = row.get(fn)
                if val:
                    return val
    return None


def extract_stations_from_csv(filepath):
    """Extract distinct (station_id, station_name) pairs from CSV."""
    stations = {}  # dict to avoid duplicates
    
    if not os.path.exists(filepath):
        LOG.warning("CSV file not found: %s", filepath)
        return stations
    
    LOG.info("Extracting stations from %s", filepath)
    with open(filepath, newline='') as fh:
        reader = csv.DictReader(fh)
        # Normalize header keys
        fieldnames = [fn.strip().lower() for fn in (reader.fieldnames or [])]
        
        for row in reader:
            # Extract start station
            start_id = get_cell(row, fieldnames, 'start_station_id', 'start_station_code')
            start_name = get_cell(row, fieldnames, 'start_station_name')
            start_lat = get_cell(row, fieldnames, 'start_lat', 'start_latitude')
            start_lng = get_cell(row, fieldnames, 'start_lng', 'start_longitude')
            if start_id:
                start_id = start_id.strip()
                if start_name:
                    start_name = start_name.strip()
                # store tuple of (name, lat, lng)
                stations[start_id] = (start_name or stations.get(start_id, (None, None, None))[0],
                                       float(start_lat) if start_lat else stations.get(start_id, (None, None, None))[1],
                                       float(start_lng) if start_lng else stations.get(start_id, (None, None, None))[2])
            
            # Extract end station
            end_id = get_cell(row, fieldnames, 'end_station_id', 'end_station_code')
            end_name = get_cell(row, fieldnames, 'end_station_name')
            end_lat = get_cell(row, fieldnames, 'end_lat', 'end_latitude')
            end_lng = get_cell(row, fieldnames, 'end_lng', 'end_longitude')
            if end_id:
                end_id = end_id.strip()
                if end_name:
                    end_name = end_name.strip()
                stations[end_id] = (end_name or stations.get(end_id, (None, None, None))[0],
                                     float(end_lat) if end_lat else stations.get(end_id, (None, None, None))[1],
                                     float(end_lng) if end_lng else stations.get(end_id, (None, None, None))[2])
    
    return stations


def upsert_stations(conn, stations):
    """Upsert station list into the station table."""
    if not stations:
        LOG.warning("No stations to upsert")
        return
    # Use PostGIS geometry for station location
    stmt = text(
        "INSERT INTO station (station_id, station_name, geom) VALUES (:station_id, :station_name, ST_SetSRID(ST_MakePoint(:station_lng, :station_lat), 4326)) "
        "ON CONFLICT (station_id) DO UPDATE SET station_name = EXCLUDED.station_name, geom = COALESCE(EXCLUDED.geom, station.geom)"
    )

    records = []
    for sid, (sname, slat, slng) in stations.items():
        records.append(dict(station_id=sid, station_name=sname, station_lat=slat, station_lng=slng))
    conn.execute(stmt, records)
    LOG.info("Upserted %d station(s)", len(records))


def main():
    logging.basicConfig(level=logging.INFO)
    load_dotenv()
    
    # Build DB URL from env
    db_url = os.environ.get('DATABASE_URL') or build_db_url_from_env()
    engine = create_engine(db_url)
    
    # Get CSV path from env (default to sample.csv)
    csv_path = os.environ.get('STATION_CSV_PATH', 'db/data/202509-baywheels-tripdata.csv')
    
    # Extract stations from CSV
    stations = extract_stations_from_csv(csv_path)
    
    if not stations:
        LOG.warning("No stations extracted from CSV. Exiting.")
        return
    
    # Upsert into DB
    with engine.begin() as conn:
        upsert_stations(conn, stations)
    
    LOG.info("Successfully populated station table with %d distinct station(s)", len(stations))


if __name__ == '__main__':
    main()
