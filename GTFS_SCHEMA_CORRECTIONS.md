# GTFS Schema Corrections

## Issues Found and Fixed

Thank you for catching these data type mismatches! After reviewing your actual CSV files, I've corrected the following issues:

---

## 1. **routes.csv** Corrections

### What was wrong:

```sql
-- OLD (incorrect) schema
CREATE TABLE gtfs_staging_routes (
    route_id TEXT,
    agency_id TEXT,
    route_short_name TEXT,
    route_long_name TEXT,
    route_desc TEXT,           -- ❌ NOT in your CSV
    route_type INTEGER,
    route_url TEXT,            -- ❌ NOT in your CSV
    route_color TEXT,          -- ❌ NOT in your CSV
    route_text_color TEXT,     -- ❌ NOT in your CSV
    continuous_pickup INTEGER,
    continuous_drop_off INTEGER
);
```

### What your CSV actually has:

```csv
route_id,agency_id,route_long_name,route_short_name,route_type,continuous_pickup,continuous_drop_off
```

### Fixed schema:

```sql
-- NEW (correct) schema
CREATE TABLE gtfs_staging_routes (
    route_id TEXT PRIMARY KEY,
    agency_id TEXT,
    route_long_name TEXT,
    route_short_name TEXT,
    route_type INTEGER,
    continuous_pickup INTEGER,
    continuous_drop_off INTEGER
);
```

---

## 2. **stops.csv** Corrections

### What was wrong:

```sql
-- OLD (incorrect) - had 12 columns
CREATE TABLE gtfs_staging_stops (
    stop_id TEXT,
    stop_code TEXT,           -- ❌ NOT in your CSV
    stop_name TEXT,
    stop_desc TEXT,           -- ❌ NOT in your CSV
    stop_lat DOUBLE PRECISION,
    stop_lon DOUBLE PRECISION,
    zone_id TEXT,             -- ❌ NOT in your CSV
    stop_url TEXT,            -- ❌ NOT in your CSV
    location_type INTEGER,    -- ❌ NOT in your CSV
    parent_station TEXT,      -- ❌ NOT in your CSV
    stop_timezone TEXT,       -- ❌ NOT in your CSV
    wheelchair_boarding INTEGER -- ❌ NOT in your CSV
);
```

### What your CSV actually has:

```csv
stop_id,stop_name,stop_lat,stop_lon
```

### Fixed schema:

```sql
-- NEW (correct) - only 4 columns
CREATE TABLE gtfs_staging_stops (
    stop_id TEXT PRIMARY KEY,
    stop_name TEXT,
    stop_lat DOUBLE PRECISION,
    stop_lon DOUBLE PRECISION
);
```

---

## 3. **trips.csv** Corrections

### What was wrong:

```sql
-- OLD (incorrect) - 10 columns
CREATE TABLE gtfs_staging_trips (
    trip_id TEXT,
    route_id TEXT,
    service_id TEXT,
    trip_headsign TEXT,
    trip_short_name TEXT,        -- ❌ NOT in your CSV
    direction_id INTEGER,
    block_id TEXT,               -- ❌ NOT in your CSV
    shape_id TEXT,
    wheelchair_accessible INTEGER, -- ❌ NOT in your CSV
    bikes_allowed INTEGER        -- ❌ NOT in your CSV
);
```

### What your CSV actually has:

```csv
route_id,service_id,trip_headsign,direction_id,shape_id,trip_id
```

### Fixed schema:

```sql
-- NEW (correct) - 6 columns in correct order
CREATE TABLE gtfs_staging_trips (
    route_id TEXT,
    service_id TEXT,
    trip_headsign TEXT,
    direction_id INTEGER,
    shape_id TEXT,
    trip_id TEXT PRIMARY KEY
);
```

---

## 4. **stop_times.csv** Corrections

### What was wrong:

```sql
-- OLD (incorrect) - 9 columns in wrong order
CREATE TABLE gtfs_staging_stop_times (
    trip_id TEXT,
    arrival_time TEXT,
    departure_time TEXT,
    stop_id TEXT,
    stop_sequence INTEGER,
    stop_headsign TEXT,      -- ❌ NOT in your CSV
    pickup_type INTEGER,     -- ❌ NOT in your CSV
    drop_off_type INTEGER,   -- ❌ NOT in your CSV
    shape_dist_traveled DOUBLE PRECISION, -- ❌ NOT in your CSV
    timepoint INTEGER
);
```

### What your CSV actually has:

```csv
trip_id,stop_id,stop_sequence,arrival_time,departure_time,timepoint
```

### Fixed schema:

```sql
-- NEW (correct) - 6 columns in CSV order
CREATE TABLE gtfs_staging_stop_times (
    trip_id TEXT,
    stop_id TEXT,
    stop_sequence INTEGER,
    arrival_time TEXT,
    departure_time TEXT,
    timepoint INTEGER,
    PRIMARY KEY (trip_id, stop_sequence)
);
```

---

## 5. **shapes.csv** Corrections

### What was wrong:

```sql
-- OLD (incorrect) - missing 4th column
CREATE TABLE gtfs_staging_shapes (
    shape_id TEXT,
    shape_pt_sequence INTEGER,
    shape_pt_lat DOUBLE PRECISION,
    shape_pt_lon DOUBLE PRECISION
);
```

### What your CSV actually has:

```csv
shape_id,shape_pt_sequence,shape_pt_lat,shape_pt_lon,
```

_Note: There's a 4th column (unnamed header) containing concatenated identifiers like `OvxARhItfijPV-_xuvfnZ_Shape131.25624429.993791`_

### Fixed schema:

```sql
-- NEW (correct) - includes 4th column
CREATE TABLE gtfs_staging_shapes (
    shape_id TEXT,
    shape_pt_sequence INTEGER,
    shape_pt_lat DOUBLE PRECISION,
    shape_pt_lon DOUBLE PRECISION,
    shape_dist_traveled TEXT,  -- Extra column (concatenated identifier)
    PRIMARY KEY (shape_id, shape_pt_sequence)
);
```

---

## 6. **calendar.csv** Corrections

### What was wrong:

```sql
-- OLD (incorrect) - wrong order, wrong types, MISSING PRIMARY KEY
CREATE TABLE gtfs_staging_calendar (
    start_date DATE,           -- ❌ Should be TEXT (format: '20250101')
    end_date DATE,             -- ❌ Should be TEXT
    monday BOOLEAN,            -- ❌ Should be INTEGER (0 or 1)
    tuesday BOOLEAN,           -- ❌ Should be INTEGER
    wednesday BOOLEAN,         -- ❌ Should be INTEGER
    thursday BOOLEAN,          -- ❌ Should be INTEGER
    friday BOOLEAN,            -- ❌ Should be INTEGER
    saturday BOOLEAN,          -- ❌ Should be INTEGER
    sunday BOOLEAN             -- ❌ Should be INTEGER
);
```

### What your CSV actually has:

```csv
monday,tuesday,wednesday,thursday,friday,saturday,sunday,start_date,end_date,service_id
1,1,1,1,1,1,1,20250101,20261230,Ground_Daily
```

### Fixed schema:

```sql
-- NEW (correct) - CSV column order, INTEGER days, TEXT dates, PRIMARY KEY
CREATE TABLE gtfs_staging_calendar (
    monday INTEGER,      -- 0 or 1
    tuesday INTEGER,
    wednesday INTEGER,
    thursday INTEGER,
    friday INTEGER,
    saturday INTEGER,
    sunday INTEGER,
    start_date TEXT,     -- Format: YYYYMMDD (e.g., '20250101')
    end_date TEXT,       -- Format: YYYYMMDD
    service_id TEXT PRIMARY KEY
);
```

---

## 7. **feed_info.csv** Corrections

### What was wrong:

```sql
-- OLD (incorrect) - wrong order, missing column
CREATE TABLE gtfs_staging_feed_info (
    feed_publisher_name TEXT,
    feed_publisher_url TEXT,
    feed_lang TEXT,
    feed_start_date DATE,     -- ❌ Should be TEXT
    feed_end_date DATE,       -- ❌ Should be TEXT
    feed_version TEXT
    -- ❌ MISSING: feed_contact_url
);
```

### What your CSV actually has:

```csv
feed_publisher_name,feed_publisher_url,feed_contact_url,feed_start_date,feed_end_date,feed_version,feed_lang
```

### Fixed schema:

```sql
-- NEW (correct) - CSV column order, TEXT dates
CREATE TABLE gtfs_staging_feed_info (
    feed_publisher_name TEXT,
    feed_publisher_url TEXT,
    feed_contact_url TEXT,
    feed_start_date TEXT,  -- Format: YYYYMMDD
    feed_end_date TEXT,
    feed_version TEXT,
    feed_lang TEXT
);
```

---

## 8. **File Extension Corrections**

### What was wrong:

All import scripts were looking for `.txt` files:

```bash
if [ -f "${GTFS_DIR}/agency.txt" ]; then
```

### Fixed:

Changed to `.csv` extensions:

```bash
if [ -f "${GTFS_DIR}/agency.csv" ]; then
```

---

## Summary of Changes

| File                      | Issues Found                               | Status   |
| ------------------------- | ------------------------------------------ | -------- |
| `gtfs-staging-schema.sql` | 7 tables with wrong columns/types          | ✅ Fixed |
| `gtfs2db.sh`              | Wrong file extensions (.txt vs .csv)       | ✅ Fixed |
| `gtfs2db.sh`              | Wrong column orders in COPY commands       | ✅ Fixed |
| `gtfs2db.sh`              | Wrong column lists (extra/missing columns) | ✅ Fixed |

---

## Key Lessons

1. **Always check actual CSV headers** before creating schemas
2. **Column order matters** for PostgreSQL `\copy` commands
3. **GTFS spec is flexible** - not all implementations include all optional fields
4. **Data types matter**:
   - Dates in GTFS can be TEXT (`YYYYMMDD` format) or DATE
   - Boolean flags are often INTEGER (0/1) not actual BOOLEAN
   - Times can be TEXT (allows values > 24:00:00 for next-day trips)
5. **Your GTFS data is minimal** - only core required fields, which is actually better for performance!

---

## What's Correct Now

✅ All 8 staging tables match your CSV structure exactly  
✅ All `\copy` commands use correct column order from CSVs  
✅ All file extensions changed from `.txt` to `.csv`  
✅ All data types match actual CSV content  
✅ Primary keys added where appropriate

Your GTFS import should now work perfectly! 🚀
