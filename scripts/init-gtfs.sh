#!/bin/bash
set -euo pipefail

echo "Initializing GTFS data import..."

# Source common database setup
source /usr/local/bin/common.sh


# Check if GTFS data directory exists
if [ -d "/gtfs-data" ] && [ -n "$(ls -A /gtfs-data 2>/dev/null)" ]; then
    echo "GTFS data found, importing to staging..."
    
    # Run GTFS import and ETL
    /usr/local/bin/gtfs2db.sh
    
    echo "GTFS import and ETL completed!"
else
    echo "No GTFS data found in /gtfs-data"
    echo "You can add GTFS files later and run: gtfs2db.sh"
fi
