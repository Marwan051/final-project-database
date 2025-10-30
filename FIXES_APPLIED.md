# Fixes Applied - Review Session

## Date: 2025-10-28

### Issues Found and Fixed

#### 1. Calendar CSV Column Order Mismatch

**Problem**: The `calendar.csv` file has columns in this order:

```
monday,tuesday,wednesday,thursday,friday,saturday,sunday,start_date,end_date,service_id
```

But the `gtfs2db.sh` import script was expecting `service_id` first.

**Fix**: Updated `gtfs2db.sh` line 115 to use the correct column order matching the CSV:

```bash
\copy temp_calendar(monday, tuesday, wednesday, thursday, friday, saturday, sunday, start_date, end_date, service_id) FROM '${GTFS_DIR}/calendar.csv' CSV HEADER;
```

#### 2. Over-Restrictive Route-Stop Constraint

**Problem**: The `route_stop` table had two UNIQUE constraints:

```sql
UNIQUE (route_id, stop_sequence),  -- OK: prevents duplicate positions
UNIQUE (route_id, stop_id)         -- PROBLEM: prevents circular routes
```

The second constraint `UNIQUE (route_id, stop_id)` prevents a route from visiting the same stop multiple times. This is incorrect for:

- Circular routes that start and end at the same stop
- Routes that pass through major transit hubs multiple times

**Fix**: Removed the `UNIQUE (route_id, stop_id)` constraint from `schema.sql` line 144. Now only `UNIQUE (route_id, stop_sequence)` remains, which correctly ensures each sequence position has exactly one stop.

### Verification Checklist

All CSV files verified to match import scripts:

- ✅ **agency.csv**: `agency_id,agency_name,agency_url,agency_timezone` → matches gtfs2db.sh
- ✅ **calendar.csv**: `monday,tuesday,wednesday,thursday,friday,saturday,sunday,start_date,end_date,service_id` → NOW matches after fix
- ✅ **routes.csv**: `route_id,agency_id,route_long_name,route_short_name,route_type,continuous_pickup,continuous_drop_off` → matches gtfs2db.sh
- ✅ **stops.csv**: `stop_id,stop_name,stop_lat,stop_lon` → matches gtfs2db.sh
- ✅ **trips.csv**: `route_id,service_id,trip_headsign,direction_id,shape_id,trip_id` → matches gtfs2db.sh
- ✅ **stop_times.csv**: `trip_id,stop_id,stop_sequence,arrival_time,departure_time,timepoint` → matches gtfs2db.sh
- ✅ **shapes.csv**: `shape_id,shape_pt_sequence,shape_pt_lat,shape_pt_lon` → matches gtfs2db.sh (4 columns, not 5)
- ✅ **feed_info.csv**: `feed_publisher_name,feed_publisher_url,feed_contact_url,feed_start_date,feed_end_date,feed_version,feed_lang` → matches gtfs2db.sh

### ETL Verification

The ETL function `gtfs_etl_to_operational()` in `gtfs-etl-transform.sql`:

- ✅ Uses `DISTINCT ON (r.route_id, st.stop_sequence)` which matches the UNIQUE constraint
- ✅ Maps GTFS stops → operational `stop` table with UPSERT on `code`
- ✅ Maps GTFS routes → operational `route` table with UPSERT on `code`
- ✅ Maps GTFS shapes → operational `route_geometry` table
- ✅ Maps GTFS stop_times → operational `route_stop` table with UPSERT on `(route_id, stop_sequence)`
- ✅ Preserves vehicle types from `route_short_name` (Microbus, Tomnaya) instead of using generic GTFS route_type

### Files Modified

1. `gtfs2db.sh` - Fixed calendar column order
2. `schema.sql` - Removed over-restrictive UNIQUE constraint

### Ready for Deployment

All alignment issues between CSV files, staging schema, import scripts, ETL functions, and operational schema have been resolved. The system should now:

1. Import all 8 GTFS CSV files correctly to staging tables
2. Preserve historical data with UPSERT pattern (no truncation)
3. Transform staging data to operational schema via ETL
4. Support circular routes and routes visiting same stop multiple times
5. Maintain vehicle type information (Microbus, Tomnaya, etc.)
