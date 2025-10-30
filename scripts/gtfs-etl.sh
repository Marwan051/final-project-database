#!/usr/bin/env bash
# gtfs-etl.sh - Transform GTFS staging data into operational schema
#
# This script runs the ETL process to transform raw GTFS data
# from staging tables into your operational transport schema.
#
# Usage:
#   ./gtfs-etl.sh                    # Run ETL (keep staging data)
#   ./gtfs-etl.sh --clear-staging    # Run ETL and clear staging
#   DB_HOST=localhost ./gtfs-etl.sh
#
# Environment variables:
#   DB_HOST (default: /var/run/postgresql or localhost)
#   DB_PORT (default: 5432)
#   DB_NAME (default: transport_db)
#   DB_USER (default: postgres)
#   PGPASSWORD (optional)
#   ETL_TYPE (default: incremental) - 'full_load' or 'incremental'

set -euo pipefail

# Check for --clear-staging flag
CLEAR_STAGING=false
if [[ "${1:-}" == "--clear-staging" ]]; then
    CLEAR_STAGING=true
fi

# Check if running in Docker init context
if [ -S "/var/run/postgresql/.s.PGSQL.5432" ]; then
    DB_HOST_DEFAULT="/var/run/postgresql"
    DB_NAME_DEFAULT="${POSTGRES_DB:-transport_db}"
    DB_USER_DEFAULT="${POSTGRES_USER:-postgres}"
else
    DB_HOST_DEFAULT="localhost"
    DB_NAME_DEFAULT="transport_db"
    DB_USER_DEFAULT="postgres"
fi

# Configuration
DB_HOST="${DB_HOST:-$DB_HOST_DEFAULT}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-$DB_NAME_DEFAULT}"
DB_USER="${DB_USER:-$DB_USER_DEFAULT}"
ETL_TYPE="${ETL_TYPE:-incremental}"

# psql convenience
export PGPASSWORD="${PGPASSWORD:-}"
PSQL="psql -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER} -d ${DB_NAME} -v ON_ERROR_STOP=1"

echo "==== GTFS ETL Transformation starting ===="
echo "DB: ${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
echo "ETL Type: ${ETL_TYPE}"
echo "Clear staging after: ${CLEAR_STAGING}"
echo

# Run ETL function
echo "Running ETL transformation..."
${PSQL} <<-SQL
    SELECT gtfs_etl_to_operational('${ETL_TYPE}', ${CLEAR_STAGING});
SQL

echo
echo "ETL Log (last 5 runs):"
${PSQL} <<-SQL
    SELECT 
        etl_id,
        etl_type,
        started_at,
        completed_at,
        status,
        records_processed
    FROM gtfs_etl_log
    ORDER BY etl_id DESC
    LIMIT 5;
SQL

echo
echo "Operational data summary:"
${PSQL} <<-SQL
    SELECT 'routes' AS table, COUNT(*) AS count FROM "route"
    UNION ALL
    SELECT 'stops', COUNT(*) FROM "stop"
    UNION ALL
    SELECT 'route_geometries', COUNT(*) FROM route_geometry
    UNION ALL
    SELECT 'route_stops', COUNT(*) FROM route_stop;
SQL

echo
echo "==== GTFS ETL Transformation completed ===="
