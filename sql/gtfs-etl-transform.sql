CREATE OR REPLACE FUNCTION gtfs_etl_to_operational(p_clear_staging BOOLEAN DEFAULT true) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_stops_inserted INT := 0;
v_routes_inserted INT := 0;
v_route_geom_inserted INT := 0;
v_route_stops_inserted INT := 0;
BEGIN -- 1. operational "stop" table
RAISE NOTICE 'ETL Step 1: Transforming stops...';
WITH inserted AS (
    INSERT INTO "stop" (feed_id, gtfs_stop_id, name, geom_4326, attrs)
    SELECT s.feed_id,
        s.stop_id AS gtfs_stop_id,
        s.stop_name AS name,
        ST_SetSRID(ST_MakePoint(s.stop_lon, s.stop_lat), 4326) AS geom_4326,
        jsonb_build_object('source', 'gtfs') AS attrs
    FROM gtfs_staging_stops s
    WHERE s.stop_id IS NOT NULL
        AND s.stop_lat IS NOT NULL
        AND s.stop_lon IS NOT NULL ON CONFLICT (feed_id, gtfs_stop_id) DO
    UPDATE
    SET name = EXCLUDED.name,
        geom_4326 = EXCLUDED.geom_4326,
        attrs = "stop".attrs || EXCLUDED.attrs
    RETURNING 1
)
SELECT COUNT(*) INTO v_stops_inserted
FROM inserted;
RAISE NOTICE 'Inserted/Updated % stops',
v_stops_inserted;
-- 2. operational "route" table
RAISE NOTICE 'ETL Step 2: Transforming routes...';
WITH inserted AS (
    INSERT INTO "route" (
            feed_id,
            gtfs_route_id,
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
        r.route_id AS gtfs_route_id,
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
        false AS one_way,
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
    WHERE r.route_id IS NOT NULL ON CONFLICT (feed_id, gtfs_route_id) DO
    UPDATE
    SET name = EXCLUDED.name,
        continuous_pickup = EXCLUDED.continuous_pickup,
        continuous_drop_off = EXCLUDED.continuous_drop_off,
        mode = EXCLUDED.mode,
        operator = EXCLUDED.operator,
        attrs = "route".attrs || EXCLUDED.attrs
    RETURNING 1
)
SELECT COUNT(*) INTO v_routes_inserted
FROM inserted;
RAISE NOTICE 'Inserted/Updated % routes',
v_routes_inserted;
-- 3. operational route_geometry table
RAISE NOTICE 'ETL Step 3: Transforming route geometries...';
WITH shape_lines AS (
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
    HAVING COUNT(*) >= 2
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
        JOIN "route" r ON r.gtfs_route_id = t.route_id
        AND r.feed_id = t.feed_id
    WHERE sl.geom IS NOT NULL ON CONFLICT DO NOTHING
    RETURNING 1
)
SELECT COUNT(*) INTO v_route_geom_inserted
FROM inserted;
RAISE NOTICE 'Inserted % route geometries',
v_route_geom_inserted;
-- 4. operational route_stop table
RAISE NOTICE 'ETL Step 4: Transforming route stops...';
WITH trip_stops AS (
    SELECT DISTINCT ON (r.route_id, st.stop_sequence) r.route_id,
        s.stop_id,
        st.stop_sequence,
        st.arrival_time,
        st.departure_time
    FROM gtfs_staging_stop_times st
        JOIN gtfs_staging_trips t ON st.trip_id = t.trip_id
        AND st.feed_id = t.feed_id
        JOIN "route" r ON r.gtfs_route_id = t.route_id
        AND r.feed_id = t.feed_id
        JOIN "stop" s ON s.gtfs_stop_id = st.stop_id
        AND s.feed_id = st.feed_id
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
        CASE
            WHEN ts.arrival_time ~ '^\d{1,2}:\d{2}:\d{2}$' THEN ts.arrival_time::TIME
            ELSE NULL
        END,
        CASE
            WHEN ts.departure_time ~ '^\d{1,2}:\d{2}:\d{2}$' THEN ts.departure_time::TIME
            ELSE NULL
        END,
        jsonb_build_object('source', 'gtfs') AS attrs
    FROM trip_stops ts ON CONFLICT (route_id, stop_sequence) DO
    UPDATE
    SET arrival_time = EXCLUDED.arrival_time,
        departure_time = EXCLUDED.departure_time
    RETURNING 1
)
SELECT COUNT(*) INTO v_route_stops_inserted
FROM inserted;
RAISE NOTICE 'Inserted/Updated % route stops',
v_route_stops_inserted;
-- Analyze tables for optimal queries
RAISE NOTICE 'Analyzing tables for query optimization...';
ANALYZE "route";
ANALYZE "stop";
ANALYZE route_geometry;
ANALYZE route_stop;
-- clear staging tables
IF p_clear_staging THEN RAISE NOTICE 'Clearing staging tables...';
TRUNCATE gtfs_staging_stop_times,
gtfs_staging_trips,
gtfs_staging_shapes,
gtfs_staging_stops,
gtfs_staging_routes,
gtfs_staging_agency,
gtfs_staging_calendar,
gtfs_staging_feed_info;
END IF;
RAISE NOTICE 'ETL completed: % stops, % routes, % geometries, % route_stops',
v_stops_inserted,
v_routes_inserted,
v_route_geom_inserted,
v_route_stops_inserted;
END;
$$;