# Exit on error
set -euo pipefail

# PostgreSQL connection via Unix socket (Docker only)
export PGHOST=/var/run/postgresql
export PGPORT=5432
export PGUSER="${POSTGRES_USER:-postgres}"
export PGDATABASE="${POSTGRES_DB:-transport_db}"
export PGPASSWORD="${PGPASSWORD:-}"

# Database connection details
DB_HOST="$PGHOST"
DB_PORT="$PGPORT"
DB_NAME="$PGDATABASE"
DB_USER="$PGUSER"

# psql command with standard options
PSQL="psql -h ${DB_HOST} -p ${DB_PORT} -U ${DB_USER} -d ${DB_NAME} -v ON_ERROR_STOP=1 --quiet"

# Default GTFS data directory
GTFS_DIR="${GTFS_DIR:-/gtfs-data}"
