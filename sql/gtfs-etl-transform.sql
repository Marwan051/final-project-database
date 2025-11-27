-- ============================================================================
-- GTFS ETL: Transform staging data into operational schema (schema.sql)
-- ============================================================================
-- This script transforms GTFS staging data into your operational transport schema
-- It maps GTFS concepts to your route, stop, route_geometry, and route_stop tables
CREATE OR REPLACE FUNCTION gtfs_etl_to_operational(
        p_etl_type TEXT DEFAULT 'incremental',
        -- 'full_load' or 'incremental'
        p_clear_staging BOOLEAN DEFAULT false
    ) RETURNS BIGINT -- Returns ETL ID
    LANGUAGE plpgsql AS $$
DECLARE v_etl_id BIGINT;
v_stops_inserted INT := 0;
v_routes_inserted INT := 0;
v_route_geom_inserted INT := 0;
v_route_stops_inserted INT := 0;
v_error_msg TEXT;
BEGIN -- Start ETL log
INSERT INTO gtfs_etl_log (etl_type, status)
VALUES (p_etl_type, 'running')
RETURNING etl_id INTO v_etl_id;
BEGIN -- ========================================================================
-- 1. TRANSFORM GTFS STOPS → operational "stop" table
-- ========================================================================
RAISE NOTICE 'ETL Step 1: Transforming stops...';
WITH inserted AS (
    INSERT INTO "stop" (code, name, geom_4326, attrs)
    SELECT s.feed_id || ':' || s.stop_id AS code,
        s.stop_name AS name,
        ST_SetSRID(ST_MakePoint(s.stop_lon, s.stop_lat), 4326) AS geom_4326,
        jsonb_build_object(
            'source',
            'gtfs',
            'feed_id',
            s.feed_id,
            'gtfs_stop_id',
            s.stop_id
        ) AS attrs
    FROM gtfs_staging_stops s
    WHERE s.stop_id IS NOT NULL
        AND s.stop_lat IS NOT NULL
        AND s.stop_lon IS NOT NULL ON CONFLICT (code) DO
    UPDATE
    SET name = EXCLUDED.name,
        geom_4326 = EXCLUDED.geom_4326,
        attrs = "stop".attrs || EXCLUDED.attrs,
        updated_at = now()
    RETURNING 1
)
SELECT COUNT(*) INTO v_stops_inserted
FROM inserted;
RAISE NOTICE 'Inserted/Updated % stops',
v_stops_inserted;
-- ========================================================================
-- 2. TRANSFORM GTFS ROUTES → operational "routes" table
-- ========================================================================
RAISE NOTICE 'ETL Step 2: Transforming routes...';
WITH inserted AS (
    INSERT INTO "routes" (
            feed_id,
            code,
            name,
            continuous_pickup,
            continuous_drop_off,
            mode,
            cost,
            one_way,
            operator,
            attrs
        )
    SELECT r.feed_id,
        r.route_id AS code,
        COALESCE(
            r.route_long_name,
            r.route_short_name,
            r.route_id
        ) AS name,
        CASE
            WHEN r.continuous_pickup = 0 THEN true
            ELSE false
        END AS continuous_pickup,
        CASE
            WHEN r.continuous_drop_off = 0 THEN true
            ELSE false
        END AS continuous_drop_off,
        -- Use route_short_name if it's a vehicle type, otherwise use standard GTFS type
        COALESCE(
            NULLIF(LOWER(TRIM(r.route_short_name)), ''),
            CASE
                r.route_type
                WHEN 0 THEN 'tram'
                WHEN 1 THEN 'metro'
                WHEN 2 THEN 'rail'
                WHEN 3 THEN 'bus'
                WHEN 4 THEN 'ferry'
                WHEN 5 THEN 'cable_tram'
                WHEN 6 THEN 'aerial_lift'
                WHEN 7 THEN 'funicular'
                WHEN 11 THEN 'trolleybus'
                WHEN 12 THEN 'monorail'
                ELSE 'bus'
            END
        ) AS mode,
        0 AS cost,
        -- Default cost, can be updated later
        false AS one_way,
        -- GTFS doesn't specify, default to false
        COALESCE(a.agency_name, 'Unknown') AS operator,
        jsonb_build_object(
            'source',
            'gtfs',
            'feed_id',
            r.feed_id,
            'gtfs_route_id',
            r.route_id,
            'route_type',
            r.route_type,
            'route_short_name',
            r.route_short_name,
            'agency_id',
            r.agency_id
        ) AS attrs
    FROM gtfs_staging_routes r
        LEFT JOIN gtfs_staging_agency a ON r.agency_id = a.agency_id
        AND r.feed_id = a.feed_id
    WHERE r.route_id IS NOT NULL ON CONFLICT (feed_id, code) DO
    UPDATE
    SET name = EXCLUDED.name,
        continuous_pickup = EXCLUDED.continuous_pickup,
        continuous_drop_off = EXCLUDED.continuous_drop_off,
        mode = EXCLUDED.mode,
        operator = EXCLUDED.operator,
        attrs = "routes".attrs || EXCLUDED.attrs,
        updated_at = now()
    RETURNING 1
)
SELECT COUNT(*) INTO v_routes_inserted
FROM inserted;
RAISE NOTICE 'Inserted/Updated % routes',
v_routes_inserted;
-- ========================================================================
-- 3. TRANSFORM GTFS SHAPES → operational route_geometry table
-- ========================================================================
RAISE NOTICE 'ETL Step 3: Transforming route geometries...';
WITH shape_lines AS (
    -- Aggregate shape points into LineStrings
    SELECT s.shape_id,
        ST_MakeLine(
            ST_SetSRID(
                ST_MakePoint(s.shape_pt_lon, s.shape_pt_lat),
                4326
            )
            ORDER BY s.shape_pt_sequence
        ) AS geom
    FROM gtfs_staging_shapes s
    WHERE s.shape_pt_lat IS NOT NULL
        AND s.shape_pt_lon IS NOT NULL
    GROUP BY s.shape_id
    HAVING COUNT(*) >= 2 -- Need at least 2 points for a line
),
inserted AS (
    INSERT INTO route_geometry (route_id, geom_4326, attrs)
    SELECT DISTINCT ON (r.route_id, sl.shape_id) r.route_id,
        sl.geom AS geom_4326,
        jsonb_build_object(
            'source',
            'gtfs',
            'shape_id',
            sl.shape_id,
            'trip_count',
            COUNT(t.trip_id) OVER (PARTITION BY sl.shape_id)
        ) AS attrs
    FROM shape_lines sl
        JOIN gtfs_staging_trips t ON sl.shape_id = t.shape_id
        JOIN "routes" r ON r.code = t.route_id
    WHERE sl.geom IS NOT NULL ON CONFLICT DO NOTHING -- Avoid duplicates
    RETURNING 1
)
SELECT COUNT(*) INTO v_route_geom_inserted
FROM inserted;
RAISE NOTICE 'Inserted % route geometries',
v_route_geom_inserted;
-- ========================================================================
-- 4. TRANSFORM GTFS STOP_TIMES → operational route_stop table
-- ========================================================================
RAISE NOTICE 'ETL Step 4: Transforming route stops...';
WITH trip_stops AS (
    -- Get unique route-stop-sequence combinations
    SELECT DISTINCT ON (r.route_id, st.stop_sequence) r.route_id,
        s.stop_id,
        st.stop_sequence,
        st.arrival_time,
        st.departure_time
    FROM gtfs_staging_stop_times st
        JOIN gtfs_staging_trips t ON st.trip_id = t.trip_id
        AND st.feed_id = t.feed_id
        JOIN "routes" r ON r.code = t.route_id
        AND r.feed_id = t.feed_id
        JOIN "stop" s ON s.code = t.feed_id || ':' || st.stop_id
    WHERE st.arrival_time IS NOT NULL
    ORDER BY r.route_id,
        st.stop_sequence,
        st.arrival_time
),
inserted AS (
    INSERT INTO route_stop (
            route_id,
            stop_id,
            stop_sequence,
            arrival_time,
            departure_time,
            attrs
        )
    SELECT ts.route_id,
        ts.stop_id,
        ts.stop_sequence,
        -- Convert GTFS time format (HH:MM:SS, can be >24h) to TIME
        CASE
            WHEN ts.arrival_time ~ '^\d{1,2}:\d{2}:\d{2}$' THEN ts.arrival_time::TIME
            ELSE NULL
        END AS arrival_time,
        CASE
            WHEN ts.departure_time ~ '^\d{1,2}:\d{2}:\d{2}$' THEN ts.departure_time::TIME
            ELSE NULL
        END AS departure_time,
        jsonb_build_object(
            'source',
            'gtfs'
        ) AS attrs
    FROM trip_stops ts ON CONFLICT (route_id, stop_sequence) DO
    UPDATE
    SET arrival_time = EXCLUDED.arrival_time,
        departure_time = EXCLUDED.departure_time,
        updated_at = now()
    RETURNING 1
)
SELECT COUNT(*) INTO v_route_stops_inserted
FROM inserted;
RAISE NOTICE 'Inserted/Updated % route stops',
v_route_stops_inserted;
-- ========================================================================
-- 5. Update ETL log with success
-- ========================================================================
UPDATE gtfs_etl_log
SET completed_at = now(),
    status = 'completed',
    records_processed = jsonb_build_object(
        'stops',
        v_stops_inserted,
        'routes',
        v_routes_inserted,
        'route_geometries',
        v_route_geom_inserted,
        'route_stops',
        v_route_stops_inserted
    )
WHERE etl_id = v_etl_id;
-- Update last run time in config
UPDATE gtfs_etl_config
SET config_value = now()::TEXT,
    updated_at = now()
WHERE config_key = 'last_etl_run';
-- Optionally clear staging tables
IF p_clear_staging THEN RAISE NOTICE 'Clearing staging tables...';
TRUNCATE gtfs_staging_stop_times;
TRUNCATE gtfs_staging_trips;
TRUNCATE gtfs_staging_shapes;
TRUNCATE gtfs_staging_stops;
TRUNCATE gtfs_staging_routes;
TRUNCATE gtfs_staging_agency;
TRUNCATE gtfs_staging_calendar;
TRUNCATE gtfs_staging_feed_info;
END IF;
RAISE NOTICE 'ETL completed successfully!';
RETURN v_etl_id;
EXCEPTION
WHEN OTHERS THEN -- Log error
GET STACKED DIAGNOSTICS v_error_msg = MESSAGE_TEXT;
UPDATE gtfs_etl_log
SET completed_at = now(),
    status = 'failed',
    error_message = v_error_msg
WHERE etl_id = v_etl_id;
RAISE NOTICE 'ETL failed: %',
v_error_msg;
RAISE;
END;
END;
$$;
-- ============================================================================
-- Helper function to run ETL manually
-- ============================================================================
CREATE OR REPLACE FUNCTION gtfs_run_etl() RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE v_etl_id BIGINT;
v_result TEXT;
BEGIN v_etl_id := gtfs_etl_to_operational('manual', false);
SELECT INTO v_result format(
        'ETL completed! ETL ID: %s, Records: %s',
        etl_id,
        records_processed::TEXT
    )
FROM gtfs_etl_log
WHERE etl_id = v_etl_id;
RETURN v_result;
END;
$$;