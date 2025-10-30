#!/usr/bin/env bash
# csv2db.sh - Import CSV files into PostgreSQL transport database
# 
# Can be used standalone or called during Docker initialization
#
# Usage:
#   DB_HOST=localhost DB_PORT=5432 DB_NAME=mydb DB_USER=myuser PGPASSWORD=secret CSV_DIR=/path/to/csvs ./csv2db.sh
#
# Environment variables (all optional; defaults shown):
#   DB_HOST (default: /var/run/postgresql for Unix socket, or localhost)
#   DB_PORT (default: 5432)
#   DB_NAME (default: transport_db)
#   DB_USER (default: postgres)
#   PGPASSWORD (optional)
#   CSV_DIR (default: /csvs)
#   CSV_ENCODING (default: UTF8)
#   CSV_DELIM (default: ,)
#   REMOVE_STAGE_ON_SUCCESS (default: "yes") -> set to "no" to keep staging tables

set -euo pipefail

# Check if running in Docker init context (Unix socket available)
if [ -S "/var/run/postgresql/.s.PGSQL.5432" ]; then
    # Docker initialization context - use Unix socket
    DB_HOST_DEFAULT="/var/run/postgresql"
    DB_NAME_DEFAULT="${POSTGRES_DB:-transport_db}"
    DB_USER_DEFAULT="${POSTGRES_USER:-postgres}"
    CSV_DIR_DEFAULT="/csvs"
    REMOVE_STAGE_DEFAULT="yes"
else
    # Standalone execution - use TCP
    DB_HOST_DEFAULT="localhost"
    DB_NAME_DEFAULT="transport_db"
    DB_USER_DEFAULT="postgres"
    CSV_DIR_DEFAULT="./csvs"
    REMOVE_STAGE_DEFAULT="no"
fi

# --- config from env with context-aware defaults ---
DB_HOST="${DB_HOST:-$DB_HOST_DEFAULT}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-$DB_NAME_DEFAULT}"
DB_USER="${DB_USER:-$DB_USER_DEFAULT}"
CSV_DIR="${CSV_DIR:-$CSV_DIR_DEFAULT}"
CSV_ENCODING="${CSV_ENCODING:-UTF8}"
CSV_DELIM="${CSV_DELIM:-,}"
REMOVE_STAGE_ON_SUCCESS="${REMOVE_STAGE_ON_SUCCESS:-$REMOVE_STAGE_DEFAULT}"

# Check if CSV directory exists and has files
if [ ! -d "$CSV_DIR" ]; then
    echo "CSV directory not found: $CSV_DIR"
    echo "Skipping CSV import."
    exit 0
fi

if [ -z "$(ls -A "$CSV_DIR" 2>/dev/null)" ]; then
    echo "No CSV files found in: $CSV_DIR"
    echo "Skipping CSV import."
    exit 0
fi

# Filenames expected (edit if needed)
STOPS_CSV="${CSV_DIR}/stops.csv"
ROUTE_CSV="${CSV_DIR}/route.csv"
ROUTE_GEOM_CSV="${CSV_DIR}/route_geometry.csv"
ROUTE_STOP_CSV="${CSV_DIR}/route_stop.csv"

# psql convenience
export PGPASSWORD="${PGPASSWORD:-}"
PSQL="psql -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER} -d ${DB_NAME} -v ON_ERROR_STOP=1 --quiet"

echo "==== CSV import starting ===="
echo "DB: ${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
echo "CSV dir: ${CSV_DIR}"
echo

# quick file existence checks
for f in "$STOPS_CSV" "$ROUTE_CSV" "$ROUTE_GEOM_CSV" "$ROUTE_STOP_CSV"; do
  if [ ! -f "$f" ]; then
    echo "ERROR: CSV file not found: $f" >&2
    exit 2
  fi
done

echo "Copying CSVs into staging tables..."
# use client-side \copy so local files can be read by user running script
# QUOTE: we use HEADER and ability to set DELIMITER/ENCODING via psql flags
${PSQL} <<-PSQL_CMDS
  \\copy stage_stop FROM '${STOPS_CSV}' CSV HEADER DELIMITER '${CSV_DELIM}' ENCODING '${CSV_ENCODING}';
  \\copy stage_route FROM '${ROUTE_CSV}' CSV HEADER DELIMITER '${CSV_DELIM}' ENCODING '${CSV_ENCODING}';
  \\copy stage_route_geometry FROM '${ROUTE_GEOM_CSV}' CSV HEADER DELIMITER '${CSV_DELIM}' ENCODING '${CSV_ENCODING}';
  \\copy stage_route_stop FROM '${ROUTE_STOP_CSV}' CSV HEADER DELIMITER '${CSV_DELIM}' ENCODING '${CSV_ENCODING}';
PSQL_CMDS

echo "CSV copied to staging. Starting transform & insert..."

# Transform & insert. Each block uses NULLIF('','') to convert empty strings to NULL and
# safe conversions. If your CSV fields differ in name, edit the stage_xxx column names accordingly.
# NOTE: JSON casts will fail if attrs_text contains invalid JSON. Validate before running if necessary.
${PSQL} <<'SQL'
-- Stop insert
BEGIN;
INSERT INTO "stop"(code, name, geom_4326, attrs, created_at, updated_at)
SELECT
  NULLIF(code,''),
  NULLIF(name,''),
  CASE
    WHEN NULLIF(trim(geom_wkt),'') IS NULL THEN NULL
    WHEN trim(geom_wkt) ILIKE 'SRID=%' THEN ST_GeomFromEWKT(geom_wkt)
    ELSE ST_GeomFromText(geom_wkt, 4326)
  END,
  CASE WHEN NULLIF(trim(attrs_text),'') IS NULL THEN '{}'::jsonb ELSE attrs_text::jsonb END,
  COALESCE(NULLIF(trim(created_at_text),''), now()::text)::timestamptz,
  COALESCE(NULLIF(trim(updated_at_text),''), now()::text)::timestamptz
FROM stage_stop;
COMMIT;

-- Route insert
BEGIN;
INSERT INTO "route"(code, name, kind, mode, cost, one_way, operator, attrs, created_at, updated_at)
SELECT
  NULLIF(code,''),
  NULLIF(name,''),
  CASE WHEN lower(NULLIF(kind_text,'')) IN ('continuous','fixed') THEN lower(kind_text)::route_kind_t ELSE 'continuous'::route_kind_t END,
  NULLIF(mode,''),
  COALESCE(NULLIF(cost_text,''), '0')::integer,
  CASE
    WHEN NULLIF(one_way_text,'') IS NULL THEN true
    WHEN lower(one_way_text) IN ('t','true','1','yes','y') THEN true
    ELSE false
  END,
  NULLIF(operator,''),
  CASE WHEN NULLIF(trim(attrs_text),'') IS NULL THEN '{}'::jsonb ELSE attrs_text::jsonb END,
  COALESCE(NULLIF(trim(created_at_text),''), now()::text)::timestamptz,
  COALESCE(NULLIF(trim(updated_at_text),''), now()::text)::timestamptz
FROM stage_route;
COMMIT;

-- Route geometry insert
BEGIN;
INSERT INTO route_geometry(route_id, geom_4326, attrs, created_at, updated_at)
SELECT
  route_id_text::bigint,
  CASE
    WHEN NULLIF(trim(geom_wkt),'') IS NULL THEN NULL
    WHEN trim(geom_wkt) ILIKE 'SRID=%' THEN ST_GeomFromEWKT(geom_wkt)
    ELSE ST_GeomFromText(geom_wkt, 4326)
  END,
  CASE WHEN NULLIF(trim(attrs_text),'') IS NULL THEN '{}'::jsonb ELSE attrs_text::jsonb END,
  COALESCE(NULLIF(trim(created_at_text),''), now()::text)::timestamptz,
  COALESCE(NULLIF(trim(updated_at_text),''), now()::text)::timestamptz
FROM stage_route_geometry;
COMMIT;

-- Route stop insert
BEGIN;
INSERT INTO route_stop(route_id, stop_id, stop_sequence, arrival_time, departure_time, attrs, created_at, updated_at)
SELECT
  route_id_text::bigint,
  stop_id_text::bigint,
  COALESCE(NULLIF(stop_sequence_text,''), '0')::integer,
  NULLIF(trim(arrival_time_text),'')::time,
  NULLIF(trim(departure_time_text),'')::time,
  CASE WHEN NULLIF(trim(attrs_text),'') IS NULL THEN '{}'::jsonb ELSE attrs_text::jsonb END,
  COALESCE(NULLIF(trim(created_at_text),''), now()::text)::timestamptz,
  COALESCE(NULLIF(trim(updated_at_text),''), now()::text)::timestamptz
FROM stage_route_stop;
COMMIT;

-- Advance sequences for serial primary keys (in case CSV had explicit IDs inserted earlier).
-- If you did not insert explicit PK values this still sets sequence to current max.
SELECT setval(pg_get_serial_sequence('route','route_id'), COALESCE(MAX(route_id), 1)) FROM route;
SELECT setval(pg_get_serial_sequence('route_geometry','route_geom_id'), COALESCE(MAX(route_geom_id), 1)) FROM route_geometry;
SELECT setval(pg_get_serial_sequence('stop','stop_id'), COALESCE(MAX(stop_id), 1)) FROM "stop";
SELECT setval(pg_get_serial_sequence('route_stop','route_stop_id'), COALESCE(MAX(route_stop_id), 1)) FROM route_stop;

-- Optional: ANALYZE the tables to update planner statistics
ANALYZE "route";
ANALYZE route_geometry;
ANALYZE "stop";
ANALYZE route_stop;
SQL

echo "Transform & insert complete."

# print counts
echo
echo "Counts after import:"
${PSQL} <<-PSQL_END
  SELECT 'route' AS table, COUNT(*) FROM "route";
  SELECT 'route_geometry' AS table, COUNT(*) FROM route_geometry;
  SELECT 'stop' AS table, COUNT(*) FROM "stop";
  SELECT 'route_stop' AS table, COUNT(*) FROM route_stop;
PSQL_END

if [ "${REMOVE_STAGE_ON_SUCCESS}" = "yes" ]; then
  echo "Truncating staging tables as REMOVE_STAGE_ON_SUCCESS=yes"
  ${PSQL} <<-TRUNC
    TRUNCATE stage_stop, stage_route, stage_route_geometry, stage_route_stop;
  TRUNC
fi

echo
echo "==== CSV import finished successfully ===="