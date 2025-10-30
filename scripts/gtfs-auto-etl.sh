#!/usr/bin/env bash
# gtfs-auto-etl.sh - Automated ETL monitoring and execution
#
# This script monitors for new GTFS data in staging and runs ETL automatically
# Can be run as a cron job or background service
#
# Usage:
#   ./gtfs-auto-etl.sh --daemon      # Run in background (check every hour)
#   ./gtfs-auto-etl.sh --once        # Check once and exit
#   ./gtfs-auto-etl.sh --interval 30 # Check every 30 minutes
#
# Environment variables:
#   DB_HOST, DB_PORT, DB_NAME, DB_USER, PGPASSWORD (same as gtfs-etl.sh)
#   ETL_INTERVAL (default: 60) - Minutes between checks

set -euo pipefail

# Parse arguments
MODE="once"
INTERVAL_MINUTES="${ETL_INTERVAL:-60}"

while [[ $# -gt 0 ]]; do
    case $1 in
        --daemon)
            MODE="daemon"
            shift
            ;;
        --once)
            MODE="once"
            shift
            ;;
        --interval)
            INTERVAL_MINUTES="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--daemon|--once] [--interval MINUTES]"
            exit 1
            ;;
    esac
done

# Check if running in Docker
if [ -S "/var/run/postgresql/.s.PGSQL.5432" ]; then
    DB_HOST_DEFAULT="/var/run/postgresql"
    DB_NAME_DEFAULT="${POSTGRES_DB:-transport_db}"
    DB_USER_DEFAULT="${POSTGRES_USER:-postgres}"
else
    DB_HOST_DEFAULT="localhost"
    DB_NAME_DEFAULT="transport_db"
    DB_USER_DEFAULT="postgres"
fi

DB_HOST="${DB_HOST:-$DB_HOST_DEFAULT}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-$DB_NAME_DEFAULT}"
DB_USER="${DB_USER:-$DB_USER_DEFAULT}"

export PGPASSWORD="${PGPASSWORD:-}"
PSQL="psql -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER} -d ${DB_NAME} -v ON_ERROR_STOP=1 --quiet -t"

echo "==== GTFS Auto-ETL Monitor ===="
echo "Mode: ${MODE}"
echo "Check interval: ${INTERVAL_MINUTES} minutes"
echo

check_and_run_etl() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Check if auto ETL is enabled
    local auto_enabled=$(${PSQL} -c "SELECT config_value FROM gtfs_etl_config WHERE config_key = 'auto_etl_enabled';" | tr -d ' ')
    
    if [ "$auto_enabled" != "true" ]; then
        echo "[$timestamp] Auto-ETL is disabled in config. Skipping."
        return 0
    fi
    
    # Check if there's new data in staging (imported in last interval)
    local new_data=$(${PSQL} -c "
        SELECT COUNT(*) > 0 
        FROM gtfs_staging_routes 
        WHERE imported_at > now() - interval '${INTERVAL_MINUTES} minutes';
    " | tr -d ' ')
    
    if [ "$new_data" = "t" ]; then
        echo "[$timestamp] New GTFS data detected in staging. Running ETL..."
        
        # Run ETL
        if gtfs-etl.sh; then
            echo "[$timestamp] ETL completed successfully"
        else
            echo "[$timestamp] ETL failed!" >&2
            return 1
        fi
    else
        echo "[$timestamp] No new data in staging. Skipping ETL."
    fi
}

# Main execution loop
if [ "$MODE" = "daemon" ]; then
    echo "Starting in daemon mode. Press Ctrl+C to stop."
    while true; do
        check_and_run_etl || true  # Continue even if ETL fails
        echo "Sleeping for ${INTERVAL_MINUTES} minutes..."
        sleep $((INTERVAL_MINUTES * 60))
    done
else
    # Run once
    check_and_run_etl
fi
