#!/usr/bin/env bash
# gtfs-etl.sh - Transform GTFS staging data into operational schema
#
# Usage:
#   ./gtfs-etl.sh                    # Run ETL (keep staging data)
#   ./gtfs-etl.sh --clear-staging    # Run ETL and clear staging
#
# Environment variables:
#   ETL_TYPE (default: incremental) - 'full_load' or 'incremental'

# Source common database setup
source /usr/local/bin/common.sh

# Check for --clear-staging flag
CLEAR_STAGING=false
if [[ "${1:-}" == "--clear-staging" ]]; then
    CLEAR_STAGING=true
fi

ETL_TYPE="${ETL_TYPE:-incremental}"


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
