#!/usr/bin/env bash
# gtfs2db.sh - Import GTFS data into PostgreSQL staging tables
#
# Usage:
#   ./gtfs2db.sh [--with-etl]
#   --with-etl: Run ETL after import
#
# Examples:
#   ./gtfs2db.sh              # Import only
#   ./gtfs2db.sh --with-etl   # Import and run ETL
#
# Environment variables:
#   GTFS_DIR (default: /gtfs-data)
#   RUN_ETL (default: false)

# Source common database setup
source /usr/local/bin/common.sh

# Parse arguments
RUN_ETL_FLAG=false

for arg in "$@"; do
    if [[ "$arg" == "--with-etl" ]]; then
        RUN_ETL_FLAG=true
    fi
done

# Always generate a UUID for the feed
FEED_ID=$(uuidgen)

RUN_ETL="${RUN_ETL:-$RUN_ETL_FLAG}"

# Check if GTFS directory exists
if [ ! -d "$GTFS_DIR" ]; then
    echo "GTFS directory not found: $GTFS_DIR"
    echo "Skipping GTFS import."
    exit 1
fi

echo "==== GTFS STAGING import starting ===="
echo "Feed ID: ${FEED_ID}"
echo "DB: ${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
echo "GTFS dir: ${GTFS_DIR}"
echo "Run ETL after import: ${RUN_ETL}"
echo

echo "Importing GTFS data for feed '${FEED_ID}'..."

# Delete existing data for this feed_id only
echo "Removing existing data for feed_id='${FEED_ID}'..."
${PSQL} <<-SQL
    DELETE FROM gtfs_staging_agency WHERE feed_id = '${FEED_ID}';
    DELETE FROM gtfs_staging_calendar WHERE feed_id = '${FEED_ID}';
    DELETE FROM gtfs_staging_routes WHERE feed_id = '${FEED_ID}';
    DELETE FROM gtfs_staging_stops WHERE feed_id = '${FEED_ID}';
    DELETE FROM gtfs_staging_shapes WHERE feed_id = '${FEED_ID}';
    DELETE FROM gtfs_staging_trips WHERE feed_id = '${FEED_ID}';
    DELETE FROM gtfs_staging_stop_times WHERE feed_id = '${FEED_ID}';
    DELETE FROM gtfs_staging_feed_info WHERE feed_id = '${FEED_ID}';
SQL

# 1. Agency
if [ -f "${GTFS_DIR}/agency.csv" ]; then
    echo "  - agency.csv → gtfs_staging_agency"
    ${PSQL} <<-SQL
	CREATE TEMP TABLE temp_agency (agency_id TEXT, agency_name TEXT, agency_url TEXT, agency_timezone TEXT);
	\copy temp_agency FROM '${GTFS_DIR}/agency.csv' CSV HEADER;
	INSERT INTO gtfs_staging_agency (feed_id, agency_id, agency_name, agency_url, agency_timezone)
	SELECT '${FEED_ID}', agency_id, agency_name, agency_url, agency_timezone FROM temp_agency;
	DROP TABLE temp_agency;
SQL
fi

# 2. Calendar
if [ -f "${GTFS_DIR}/calendar.csv" ]; then
    echo "  - calendar.csv → gtfs_staging_calendar"
    ${PSQL} <<-SQL
	CREATE TEMP TABLE temp_calendar (monday INT, tuesday INT, wednesday INT, thursday INT, friday INT, saturday INT, sunday INT, start_date TEXT, end_date TEXT, service_id TEXT);
	\copy temp_calendar FROM '${GTFS_DIR}/calendar.csv' CSV HEADER;
	INSERT INTO gtfs_staging_calendar (feed_id, monday, tuesday, wednesday, thursday, friday, saturday, sunday, start_date, end_date, service_id)
	SELECT '${FEED_ID}', monday, tuesday, wednesday, thursday, friday, saturday, sunday, start_date, end_date, service_id FROM temp_calendar;
	DROP TABLE temp_calendar;
SQL
fi

# 3. Routes
if [ -f "${GTFS_DIR}/routes.csv" ]; then
    echo "  - routes.csv → gtfs_staging_routes"
    ${PSQL} <<-SQL
	CREATE TEMP TABLE temp_routes (route_id TEXT, agency_id TEXT, route_long_name TEXT, route_short_name TEXT, route_type INT, continuous_pickup INT, continuous_drop_off INT);
	\copy temp_routes FROM '${GTFS_DIR}/routes.csv' CSV HEADER;
	INSERT INTO gtfs_staging_routes (feed_id, route_id, agency_id, route_long_name, route_short_name, route_type, continuous_pickup, continuous_drop_off)
	SELECT '${FEED_ID}', route_id, agency_id, route_long_name, route_short_name, route_type, continuous_pickup, continuous_drop_off FROM temp_routes;
	DROP TABLE temp_routes;
SQL
fi

# 4. Stops
if [ -f "${GTFS_DIR}/stops.csv" ]; then
    echo "  - stops.csv → gtfs_staging_stops"
    ${PSQL} <<-SQL
	CREATE TEMP TABLE temp_stops (stop_id TEXT, stop_name TEXT, stop_lat DOUBLE PRECISION, stop_lon DOUBLE PRECISION);
	\copy temp_stops FROM '${GTFS_DIR}/stops.csv' CSV HEADER;
	INSERT INTO gtfs_staging_stops (feed_id, stop_id, stop_name, stop_lat, stop_lon)
	SELECT '${FEED_ID}', stop_id, stop_name, stop_lat, stop_lon FROM temp_stops;
	DROP TABLE temp_stops;
SQL
fi

# 5. Shapes
if [ -f "${GTFS_DIR}/shapes.csv" ]; then
    echo "  - shapes.csv → gtfs_staging_shapes"
    ${PSQL} <<-SQL
	CREATE TEMP TABLE temp_shapes (shape_id TEXT, shape_pt_sequence INT, shape_pt_lat DOUBLE PRECISION, shape_pt_lon DOUBLE PRECISION);
	\copy temp_shapes FROM '${GTFS_DIR}/shapes.csv' CSV HEADER;
	INSERT INTO gtfs_staging_shapes (feed_id, shape_id, shape_pt_sequence, shape_pt_lat, shape_pt_lon)
	SELECT '${FEED_ID}', shape_id, shape_pt_sequence, shape_pt_lat, shape_pt_lon FROM temp_shapes;
	DROP TABLE temp_shapes;
SQL
fi

# 6. Trips
if [ -f "${GTFS_DIR}/trips.csv" ]; then
    echo "  - trips.csv → gtfs_staging_trips"
    ${PSQL} <<-SQL
	CREATE TEMP TABLE temp_trips (route_id TEXT, service_id TEXT, trip_headsign TEXT, direction_id INT, shape_id TEXT, trip_id TEXT);
	\copy temp_trips FROM '${GTFS_DIR}/trips.csv' CSV HEADER;
	INSERT INTO gtfs_staging_trips (feed_id, route_id, service_id, trip_headsign, direction_id, shape_id, trip_id)
	SELECT '${FEED_ID}', route_id, service_id, trip_headsign, direction_id, shape_id, trip_id FROM temp_trips;
	DROP TABLE temp_trips;
SQL
fi

# 7. Stop Times
if [ -f "${GTFS_DIR}/stop_times.csv" ]; then
    echo "  - stop_times.csv → gtfs_staging_stop_times"
    ${PSQL} <<-SQL
	CREATE TEMP TABLE temp_stop_times (trip_id TEXT, stop_id TEXT, stop_sequence INT, arrival_time TEXT, departure_time TEXT, timepoint INT);
	\copy temp_stop_times FROM '${GTFS_DIR}/stop_times.csv' CSV HEADER;
	INSERT INTO gtfs_staging_stop_times (feed_id, trip_id, stop_id, stop_sequence, arrival_time, departure_time, timepoint)
	SELECT '${FEED_ID}', trip_id, stop_id, stop_sequence, arrival_time, departure_time, timepoint FROM temp_stop_times;
	DROP TABLE temp_stop_times;
SQL
fi

# 8. Feed Info
if [ -f "${GTFS_DIR}/feed_info.csv" ]; then
    echo "  - feed_info.csv → gtfs_staging_feed_info"
    ${PSQL} <<-SQL
	CREATE TEMP TABLE temp_feed_info (feed_publisher_name TEXT, feed_publisher_url TEXT, feed_contact_url TEXT, feed_start_date TEXT, feed_end_date TEXT, feed_version TEXT, feed_lang TEXT);
	\copy temp_feed_info FROM '${GTFS_DIR}/feed_info.csv' CSV HEADER;
	INSERT INTO gtfs_staging_feed_info (feed_id, feed_publisher_name, feed_publisher_url, feed_contact_url, feed_start_date, feed_end_date, feed_version, feed_lang)
	SELECT '${FEED_ID}', feed_publisher_name, feed_publisher_url, feed_contact_url, feed_start_date, feed_end_date, feed_version, feed_lang FROM temp_feed_info;
	DROP TABLE temp_feed_info;
SQL
fi

echo
echo "GTFS staging import summary:"
${PSQL} <<-SQL
    SELECT * FROM gtfs_staging_stats();
SQL

echo
echo "Data quality validation:"
${PSQL} <<-SQL
    SELECT * FROM gtfs_validate_staging_data();
SQL


# Run ETL if requested
if [ "$RUN_ETL" = "true" ]; then
    echo
    echo "Running ETL transformation to operational schema..."
    if command -v gtfs-etl.sh &> /dev/null; then
        gtfs-etl.sh
    else
        ${PSQL} <<-SQL
		SELECT gtfs_run_etl();
SQL
    fi
fi
