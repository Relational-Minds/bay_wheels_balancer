"""
Load Bay Wheels CSV trip files into Postgres.

Usage:
  python scripts/load_trips.py --db postgresql://user:pass@localhost:5432/baywheels --data-dir data/ --batch-size 1000

This script:
- Reads CSV files from `data_dir` (non-recursive)
- Upserts station records into `station`
- Inserts trips into `trip_history` using `ON CONFLICT DO NOTHING` for idempotency
- Uses batched inserts for performance

Notes:
- Adjust the `DB_URL` or pass `--db` to point to your Postgres instance.
"""
import csv
import glob
import logging
import os
from datetime import datetime

from sqlalchemy import create_engine, text
from dotenv import load_dotenv

LOG = logging.getLogger("load_trips")


def build_db_url_from_env():
    user = os.environ.get('POSTGRES_USER', os.environ.get('DB_USER', 'postgres'))
    pwd = os.environ.get('POSTGRES_PASSWORD', os.environ.get('DB_PASSWORD', 'postgres'))
    host = os.environ.get('POSTGRES_HOST', os.environ.get('DB_HOST', 'localhost'))
    port = os.environ.get('DB_PORT', '5432')
    db = os.environ.get('POSTGRES_DB', os.environ.get('DB_NAME', 'baywheels'))
    return f"postgresql://{user}:{pwd}@{host}:{port}/{db}"


def isoparse_safe(s):
    if not s:
        return None
    # Try several common timestamp formats (including fractional seconds)
    for fmt in ("%Y-%m-%d %H:%M:%S.%f%z", "%Y-%m-%d %H:%M:%S.%f", "%Y-%m-%d %H:%M:%S%z", "%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S.%f%z", "%Y-%m-%dT%H:%M:%S.%f", "%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%dT%H:%M:%S"):
        try:
            return datetime.strptime(s, fmt)
        except Exception:
            continue
    # last resort
    try:
        return datetime.fromisoformat(s)
    except Exception:
        LOG.exception("Failed to parse timestamp: %s", s)
        return None


def upsert_stations(conn, stations):
    """Upsert station list. `stations` is iterable of (station_id, station_name)."""
    if not stations:
        return
    # Accept stations items where value is either a name string or a tuple (name, lat, lng)
    # We store location as a PostGIS POINT geometry (SRID 4326)
    stmt = text(
        "INSERT INTO station (station_id, station_name, geom) VALUES (:station_id, :station_name, ST_SetSRID(ST_MakePoint(:station_lng, :station_lat), 4326)) "
        "ON CONFLICT (station_id) DO UPDATE SET station_name = EXCLUDED.station_name, geom = COALESCE(EXCLUDED.geom, station.geom)"
    )
    records = []
    for sid, sval in stations:
        # sval may be a string (name) or tuple (name, lat, lng)
        if isinstance(sval, tuple) or isinstance(sval, list):
            name = sval[0]
            lat = sval[1] if len(sval) > 1 else None
            lng = sval[2] if len(sval) > 2 else None
        else:
            name = sval
            lat = None
            lng = None
        records.append(dict(station_id=sid, station_name=name, station_lat=lat, station_lng=lng))
    # Execute batched upserts; SQL uses station_lat/station_lng params to build geom
    conn.execute(stmt, records)


def insert_trips(conn, trips):
    """Bulk insert trips. trips is iterable of dicts with keys ride_id,start_station_id,end_station_id,started_at,ended_at"""
    if not trips:
        return
    stmt = text(
        "INSERT INTO trip_history (ride_id, start_station_id, end_station_id, started_at, ended_at, rideable_type, member_casual) "
        "VALUES (:ride_id, :start_station_id, :end_station_id, :started_at, :ended_at, :rideable_type, :member_casual) "
        "ON CONFLICT (ride_id) DO NOTHING"
    )
    conn.execute(stmt, trips)


def process_file(conn, filepath, batch_size=1000):
    LOG.info("Processing %s", filepath)
    stations_to_upsert = {}
    batch = []
    total = 0
    with open(filepath, newline='') as fh:
        reader = csv.DictReader(fh)
        # Normalize header keys for robust access (lowercase, strip)
        fieldnames = [fn.strip().lower() for fn in (reader.fieldnames or [])]

        def get_cell(row, *names):
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
                        return row.get(fn)
            return None

        for row in reader:
            total += 1
            # Map CSV columns (sample.csv) to DB columns
            ride_id = get_cell(row, 'ride_id')
            started_at = isoparse_safe(get_cell(row, 'started_at'))
            ended_at = isoparse_safe(get_cell(row, 'ended_at'))
            start_station_id = get_cell(row, 'start_station_id', 'start_station_code')
            start_station_name = get_cell(row, 'start_station_name')
            end_station_id = get_cell(row, 'end_station_id', 'end_station_code')
            end_station_name = get_cell(row, 'end_station_name')
            # Additional fields from sample CSV
            rideable_type = get_cell(row, 'rideable_type')
            start_lat = get_cell(row, 'start_lat', 'start_latitude')
            start_lng = get_cell(row, 'start_lng', 'start_longitude')
            end_lat = get_cell(row, 'end_lat', 'end_latitude')
            end_lng = get_cell(row, 'end_lng', 'end_longitude')
            member_casual = get_cell(row, 'member_casual')

            # Normalize strings
            if ride_id:
                ride_id = ride_id.strip()
            if start_station_id:
                start_station_id = start_station_id.strip()
            if end_station_id:
                end_station_id = end_station_id.strip()
            if start_station_name:
                start_station_name = start_station_name.strip()
            if end_station_name:
                end_station_name = end_station_name.strip()

            # Drop rows missing start or end station id
            if not start_station_id or not end_station_id:
                LOG.debug("Skipping row %s: missing start or end station id", ride_id)
                continue

            # Collect station names and optional lat/lng for upsert (only for valid rows)
            if start_station_id:
                stations_to_upsert[start_station_id] = (
                    start_station_name or (stations_to_upsert.get(start_station_id)[0] if stations_to_upsert.get(start_station_id) else None),
                    float(start_lat) if start_lat else (stations_to_upsert.get(start_station_id)[1] if stations_to_upsert.get(start_station_id) else None),
                    float(start_lng) if start_lng else (stations_to_upsert.get(start_station_id)[2] if stations_to_upsert.get(start_station_id) else None),
                )
            if end_station_id:
                stations_to_upsert[end_station_id] = (
                    end_station_name or (stations_to_upsert.get(end_station_id)[0] if stations_to_upsert.get(end_station_id) else None),
                    float(end_lat) if end_lat else (stations_to_upsert.get(end_station_id)[1] if stations_to_upsert.get(end_station_id) else None),
                    float(end_lng) if end_lng else (stations_to_upsert.get(end_station_id)[2] if stations_to_upsert.get(end_station_id) else None),
                )

            trip = dict(
                ride_id=ride_id,
                start_station_id=start_station_id,
                end_station_id=end_station_id,
                started_at=started_at,
                ended_at=ended_at,
                rideable_type=rideable_type,
                member_casual=member_casual,
            )
            batch.append(trip)

            if len(batch) >= batch_size:
                insert_trips(conn, batch)
                batch = []

    # final flush
    if batch:
        insert_trips(conn, batch)

    # upsert stations (do after trips to reduce transactions)
    upsert_stations(conn, stations_to_upsert.items())
    LOG.info("Finished %s: %d rows", filepath, total)


def main():
    logging.basicConfig(level=logging.INFO)
    # Load environment variables from a .env file in the working directory (if present).
    # This allows DATABASE_URL or individual POSTGRES_* vars to be set in .env instead of passing --db at runtime.
    load_dotenv()
    # Build DB URL from env if not set explicitly
    db_url = os.environ.get('DATABASE_URL') or build_db_url_from_env()
    engine = create_engine(db_url)

    # Read other configuration from env (no CLI args per project preference)
    data_dir = os.environ.get('DATA_DIR', 'data')
    batch_size = int(os.environ.get('BATCH_SIZE', '1000'))

    files = sorted(glob.glob(os.path.join(data_dir, "*.csv")))
    if not files:
        LOG.warning("No CSV files found in %s", data_dir)
        return

    with engine.begin() as conn:
        for f in files:
            try:
                process_file(conn, f, batch_size=batch_size)
            except Exception:
                LOG.exception("Failed to process %s", f)


if __name__ == '__main__':
    main()
