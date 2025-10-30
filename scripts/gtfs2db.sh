#!/usr/bin/env bash
# gtfs2db.sh - Import GTFS data into PostgreSQL staging tables
#
# Usage:
#   ./gtfs2db.sh                    # Load into staging only
#   ./gtfs2db.sh --with-etl         # Load + run ETL transformation
#
# Environment variables:
#   GTFS_DIR (default: /gtfs-data)
#   RUN_ETL (default: false) - Set to 'true' to run ETL after import

# Source common database setup
source /usr/local/bin/common.sh

# Check for --with-etl flag
RUN_ETL_FLAG=false
if [[ "${1:-}" == "--with-etl" ]]; then
    RUN_ETL_FLAG=true
fi

RUN_ETL="${RUN_ETL:-$RUN_ETL_FLAG}"

# Check if GTFS directory exists
if [ ! -d "$GTFS_DIR" ]; then
    echo "GTFS directory not found: $GTFS_DIR"
    echo "Skipping GTFS import."
    exit 0
fi

echo "==== GTFS STAGING import starting ===="
echo "DB: ${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
echo "GTFS dir: ${GTFS_DIR}"
echo "Run ETL after import: ${RUN_ETL}"
echo

echo "Importing GTFS data into staging tables (preserving historical data)..."

# 1. Agency
if [ -f "${GTFS_DIR}/agency.csv" ]; then
    echo "  - agency.csv → gtfs_staging_agency"
    ${PSQL} <<-SQL
	CREATE TEMP TABLE temp_agency (LIKE gtfs_staging_agency INCLUDING DEFAULTS);
	\copy temp_agency(agency_id, agency_name, agency_url, agency_timezone) FROM '${GTFS_DIR}/agency.csv' CSV HEADER;
	
	INSERT INTO gtfs_staging_agency
	SELECT * FROM temp_agency
	ON CONFLICT (agency_id) DO UPDATE SET
	    agency_name = EXCLUDED.agency_name,
	    agency_url = EXCLUDED.agency_url,
	    agency_timezone = EXCLUDED.agency_timezone,
	    imported_at = CURRENT_TIMESTAMP;
	
	DROP TABLE temp_agency;
SQL
fi

# 2. Calendar
if [ -f "${GTFS_DIR}/calendar.csv" ]; then
    echo "  - calendar.csv → gtfs_staging_calendar"
    ${PSQL} <<-SQL
	CREATE TEMP TABLE temp_calendar (LIKE gtfs_staging_calendar INCLUDING DEFAULTS);
	\copy temp_calendar(monday, tuesday, wednesday, thursday, friday, saturday, sunday, start_date, end_date, service_id) FROM '${GTFS_DIR}/calendar.csv' CSV HEADER;
	
	INSERT INTO gtfs_staging_calendar
	SELECT * FROM temp_calendar
	ON CONFLICT (service_id) DO UPDATE SET
	    monday = EXCLUDED.monday,
	    tuesday = EXCLUDED.tuesday,
	    wednesday = EXCLUDED.wednesday,
	    thursday = EXCLUDED.thursday,
	    friday = EXCLUDED.friday,
	    saturday = EXCLUDED.saturday,
	    sunday = EXCLUDED.sunday,
	    start_date = EXCLUDED.start_date,
	    end_date = EXCLUDED.end_date,
	    imported_at = CURRENT_TIMESTAMP;
	
	DROP TABLE temp_calendar;
SQL
fi

# 3. Routes
if [ -f "${GTFS_DIR}/routes.csv" ]; then
    echo "  - routes.csv → gtfs_staging_routes"
    ${PSQL} <<-SQL
	CREATE TEMP TABLE temp_routes (LIKE gtfs_staging_routes INCLUDING DEFAULTS);
	\copy temp_routes(route_id, agency_id, route_long_name, route_short_name, route_type, continuous_pickup, continuous_drop_off) FROM '${GTFS_DIR}/routes.csv' CSV HEADER;
	
	INSERT INTO gtfs_staging_routes
	SELECT * FROM temp_routes
	ON CONFLICT (route_id) DO UPDATE SET
	    agency_id = EXCLUDED.agency_id,
	    route_long_name = EXCLUDED.route_long_name,
	    route_short_name = EXCLUDED.route_short_name,
	    route_type = EXCLUDED.route_type,
	    continuous_pickup = EXCLUDED.continuous_pickup,
	    continuous_drop_off = EXCLUDED.continuous_drop_off,
	    imported_at = CURRENT_TIMESTAMP;
	
	DROP TABLE temp_routes;
SQL
fi

# 4. Stops
if [ -f "${GTFS_DIR}/stops.csv" ]; then
    echo "  - stops.csv → gtfs_staging_stops"
    ${PSQL} <<-SQL
	CREATE TEMP TABLE temp_stops (LIKE gtfs_staging_stops INCLUDING DEFAULTS);
	\copy temp_stops(stop_id, stop_name, stop_lat, stop_lon) FROM '${GTFS_DIR}/stops.csv' CSV HEADER;
	
	INSERT INTO gtfs_staging_stops
	SELECT * FROM temp_stops
	ON CONFLICT (stop_id) DO UPDATE SET
	    stop_name = EXCLUDED.stop_name,
	    stop_lat = EXCLUDED.stop_lat,
	    stop_lon = EXCLUDED.stop_lon,
	    imported_at = CURRENT_TIMESTAMP;
	
	DROP TABLE temp_stops;
SQL
fi

# 5. Shapes
if [ -f "${GTFS_DIR}/shapes.csv" ]; then
    echo "  - shapes.csv → gtfs_staging_shapes"
    ${PSQL} <<-SQL
	CREATE TEMP TABLE temp_shapes (LIKE gtfs_staging_shapes INCLUDING DEFAULTS);
	\copy temp_shapes(shape_id, shape_pt_sequence, shape_pt_lat, shape_pt_lon) FROM '${GTFS_DIR}/shapes.csv' CSV HEADER;
	
	INSERT INTO gtfs_staging_shapes
	SELECT * FROM temp_shapes
	ON CONFLICT (shape_id, shape_pt_sequence) DO UPDATE SET
	    shape_pt_lat = EXCLUDED.shape_pt_lat,
	    shape_pt_lon = EXCLUDED.shape_pt_lon,
	    imported_at = CURRENT_TIMESTAMP;
	
	DROP TABLE temp_shapes;
SQL
fi

# 6. Trips
if [ -f "${GTFS_DIR}/trips.csv" ]; then
    echo "  - trips.csv → gtfs_staging_trips"
    ${PSQL} <<-SQL
	CREATE TEMP TABLE temp_trips (LIKE gtfs_staging_trips INCLUDING DEFAULTS);
	\copy temp_trips(route_id, service_id, trip_headsign, direction_id, shape_id, trip_id) FROM '${GTFS_DIR}/trips.csv' CSV HEADER;
	
	INSERT INTO gtfs_staging_trips
	SELECT * FROM temp_trips
	ON CONFLICT (trip_id) DO UPDATE SET
	    route_id = EXCLUDED.route_id,
	    service_id = EXCLUDED.service_id,
	    trip_headsign = EXCLUDED.trip_headsign,
	    direction_id = EXCLUDED.direction_id,
	    shape_id = EXCLUDED.shape_id,
	    imported_at = CURRENT_TIMESTAMP;
	
	DROP TABLE temp_trips;
SQL
fi

# 7. Stop Times
if [ -f "${GTFS_DIR}/stop_times.csv" ]; then
    echo "  - stop_times.csv → gtfs_staging_stop_times"
    ${PSQL} <<-SQL
	CREATE TEMP TABLE temp_stop_times (LIKE gtfs_staging_stop_times INCLUDING DEFAULTS);
	\copy temp_stop_times(trip_id, stop_id, stop_sequence, arrival_time, departure_time, timepoint) FROM '${GTFS_DIR}/stop_times.csv' CSV HEADER;
	
	INSERT INTO gtfs_staging_stop_times
	SELECT * FROM temp_stop_times
	ON CONFLICT (trip_id, stop_sequence) DO UPDATE SET
	    stop_id = EXCLUDED.stop_id,
	    arrival_time = EXCLUDED.arrival_time,
	    departure_time = EXCLUDED.departure_time,
	    timepoint = EXCLUDED.timepoint,
	    imported_at = CURRENT_TIMESTAMP;
	
	DROP TABLE temp_stop_times;
SQL
fi

# 8. Feed Info
if [ -f "${GTFS_DIR}/feed_info.csv" ]; then
    echo "  - feed_info.csv → gtfs_staging_feed_info"
    ${PSQL} <<-SQL
	CREATE TEMP TABLE temp_feed_info (LIKE gtfs_staging_feed_info INCLUDING DEFAULTS);
	\copy temp_feed_info(feed_publisher_name, feed_publisher_url, feed_contact_url, feed_start_date, feed_end_date, feed_version, feed_lang) FROM '${GTFS_DIR}/feed_info.csv' CSV HEADER;
	
	INSERT INTO gtfs_staging_feed_info
	SELECT * FROM temp_feed_info
	ON CONFLICT (feed_version) DO UPDATE SET
	    feed_publisher_name = EXCLUDED.feed_publisher_name,
	    feed_publisher_url = EXCLUDED.feed_publisher_url,
	    feed_contact_url = EXCLUDED.feed_contact_url,
	    feed_start_date = EXCLUDED.feed_start_date,
	    feed_end_date = EXCLUDED.feed_end_date,
	    feed_lang = EXCLUDED.feed_lang,
	    imported_at = CURRENT_TIMESTAMP;
	
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
