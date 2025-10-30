#!/bin/bash
set -e

echo "Setting up GTFS staging tables and ETL functions..."

# Source common database setup
source /usr/local/bin/common.sh

# Apply GTFS staging schema
echo "Creating GTFS staging tables..."
psql -v ON_ERROR_STOP=1 -f /docker-entrypoint-initdb.d/03-gtfs-staging-schema.sql

echo "Creating GTFS ETL transformation functions..."
psql -v ON_ERROR_STOP=1 -f /docker-entrypoint-initdb.d/04-gtfs-etl-transform.sql

echo "GTFS staging and ETL functions created successfully"

# Check if GTFS data directory exists
if [ -d "/gtfs-data" ] && [ -n "$(ls -A /gtfs-data 2>/dev/null)" ]; then
    echo "GTFS data found, importing to staging..."
    
    # Set environment variable to run ETL after initial import
    export RUN_ETL=true
    
    # Run GTFS import to staging
    /usr/local/bin/gtfs2db.sh --with-etl
    
    echo "GTFS import and ETL completed!"
else
    echo "No GTFS data found in /gtfs-data"
    echo "You can add GTFS files later and run: gtfs2db.sh --with-etl"
fi

echo "GTFS setup complete!"
echo ""
echo "To add new GTFS data later:"
echo "  1. Copy new GTFS files to container: docker cp ./gtfs-data/. transport-db:/gtfs-data/"
echo "  2. Import to staging: docker exec transport-db gtfs2db.sh"
echo "  3. Run ETL transformation: docker exec transport-db gtfs-etl.sh"
echo "  4. Or do both: docker exec transport-db gtfs2db.sh --with-etl"
