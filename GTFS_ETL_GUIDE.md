# GTFS Staging & ETL Architecture

## Overview

This database uses a **two-tier architecture** for GTFS data:

1. **Staging Layer** (`gtfs_staging_*` tables) - Raw GTFS data import
2. **Operational Layer** (`route`, `stop`, `route_geometry`, `route_stop`) - Transformed, normalized data

This allows you to:

- Import new GTFS data without disrupting operations
- Validate data before it goes live
- Run transformations on demand or on schedule
- Maintain data lineage and audit trails

## Architecture Diagram

```
GTFS Files (.txt)
      ↓
   gtfs2db.sh
      ↓
┌─────────────────────┐
│  STAGING TABLES     │
│  (Raw Import)       │
├─────────────────────┤
│ gtfs_staging_agency │
│ gtfs_staging_routes │
│ gtfs_staging_stops  │
│ gtfs_staging_trips  │
│ gtfs_staging_shapes │
│ gtfs_staging_...    │
└─────────────────────┘
      ↓
  gtfs-etl.sh
  (Transform & Load)
      ↓
┌─────────────────────┐
│  OPERATIONAL SCHEMA │
│  (schema.sql)       │
├─────────────────────┤
│ route               │
│ stop                │
│ route_geometry      │
│ route_stop          │
└─────────────────────┘
```

## Database Tables

### Staging Tables

- `gtfs_staging_agency` - Transit operators (raw)
- `gtfs_staging_routes` - Routes (raw)
- `gtfs_staging_stops` - Stops with lat/lon (raw)
- `gtfs_staging_trips` - Trip definitions (raw)
- `gtfs_staging_stop_times` - Timetables (raw)
- `gtfs_staging_shapes` - Shape points (raw)
- `gtfs_staging_calendar` - Service schedules (raw)
- `gtfs_staging_feed_info` - Feed metadata (raw)

### Control & Logging Tables

- `gtfs_etl_log` - Tracks all ETL runs
- `gtfs_etl_config` - ETL configuration (intervals, auto-run, etc.)

### Operational Tables

- `route` - Your transport routes
- `stop` - Your transport stops
- `route_geometry` - Route shapes/geometries
- `route_stop` - Route-stop relationships with schedules

## Tools & Scripts

### 1. `gtfs2db.sh` - Import GTFS to Staging

```bash
# Import GTFS files into staging tables
docker exec transport-db gtfs2db.sh

# Import and automatically run ETL
docker exec transport-db gtfs2db.sh --with-etl
```

### 2. `gtfs-etl.sh` - Transform Staging → Operational

```bash
# Run ETL transformation (keep staging data)
docker exec transport-db gtfs-etl.sh

# Run ETL and clear staging tables
docker exec transport-db gtfs-etl.sh --clear-staging
```

### 3. `gtfs-auto-etl.sh` - Automated ETL Monitoring

```bash
# Run once and exit
docker exec transport-db gtfs-auto-etl.sh --once

# Run as daemon (checks every 60 minutes)
docker exec -d transport-db gtfs-auto-etl.sh --daemon

# Custom interval (every 30 minutes)
docker exec -d transport-db gtfs-auto-etl.sh --daemon --interval 30
```

## Workflows

### Initial Setup (Automatic)

On first container start:

```
1. Create staging tables
2. Create ETL functions
3. Import GTFS files → staging
4. Run ETL → operational schema
5. Database ready!
```

### Adding New GTFS Data

#### Option 1: Manual Process (Full Control)

```bash
# 1. Copy new GTFS files to container
docker cp ./new-gtfs-data/. transport-db:/gtfs-data/

# 2. Import to staging
docker exec transport-db gtfs2db.sh

# 3. Validate data quality
docker exec transport-db psql -U postgres -d transport_db -c "
  SELECT * FROM gtfs_validate_staging_data();
"

# 4. Check staging stats
docker exec transport-db psql -U postgres -d transport_db -c "
  SELECT * FROM gtfs_staging_stats();
"

# 5. Run ETL when ready
docker exec transport-db gtfs-etl.sh
```

#### Option 2: Quick Update

```bash
# Copy and run everything in one command
docker cp ./new-gtfs-data/. transport-db:/gtfs-data/
docker exec transport-db gtfs2db.sh --with-etl
```

#### Option 3: Automated Monitoring

```bash
# Enable auto-ETL
docker exec transport-db psql -U postgres -d transport_db -c "
  UPDATE gtfs_etl_config
  SET config_value = 'true'
  WHERE config_key = 'auto_etl_enabled';
"

# Start monitoring daemon (runs every 60 minutes)
docker exec -d transport-db gtfs-auto-etl.sh --daemon
```

## SQL Functions & Queries

### Validate Staging Data

```sql
SELECT * FROM gtfs_validate_staging_data();
```

Returns data quality issues like:

- Missing required fields
- Invalid coordinates
- Orphaned records

### View Staging Statistics

```sql
SELECT * FROM gtfs_staging_stats();
```

### Run ETL Manually

```sql
-- Run incremental ETL (merge new data)
SELECT gtfs_etl_to_operational('incremental', false);

-- Run full load ETL and clear staging
SELECT gtfs_etl_to_operational('full_load', true);

-- Quick run
SELECT gtfs_run_etl();
```

### View ETL History

```sql
SELECT
    etl_id,
    etl_type,
    started_at,
    completed_at,
    status,
    records_processed
FROM gtfs_etl_log
ORDER BY etl_id DESC
LIMIT 10;
```

### Check ETL Configuration

```sql
SELECT * FROM gtfs_etl_config;
```

### Update ETL Configuration

```sql
-- Enable automatic ETL
UPDATE gtfs_etl_config
SET config_value = 'true'
WHERE config_key = 'auto_etl_enabled';

-- Set interval to 30 minutes
UPDATE gtfs_etl_config
SET config_value = '30'
WHERE config_key = 'etl_interval_minutes';
```

## Data Transformation Logic

### GTFS Stops → Operational `stop`

```sql
- stop_id → code
- stop_name → name
- lat/lon → PostGIS Point geometry
- All metadata → attrs JSONB
```

### GTFS Routes → Operational `route`

```sql
- route_id → code
- route_long_name → name
- route_type → mode (bus, tram, metro, etc.)
- continuous pickup/dropoff → kind (continuous/fixed)
- agency_name → operator
```

### GTFS Shapes → Operational `route_geometry`

```sql
- Aggregate shape points → LineString geometry
- Link to route via trips
- Store shape_id in attrs
```

### GTFS Stop Times → Operational `route_stop`

```sql
- Group by route + stop + sequence
- Extract arrival/departure times
- Maintain stop ordering
```

## Merge Strategy

The ETL uses **UPSERT** strategy:

- New records are inserted
- Existing records (matched by code) are updated
- Attributes are merged (new values added to JSONB)
- Timestamps are updated

## Troubleshooting

### Check if staging has data

```sql
SELECT * FROM gtfs_staging_stats();
```

### View last ETL results

```sql
SELECT * FROM gtfs_etl_log ORDER BY etl_id DESC LIMIT 1;
```

### Check for data quality issues

```sql
SELECT * FROM gtfs_validate_staging_data();
```

### Manual cleanup

```sql
-- Clear staging tables
TRUNCATE gtfs_staging_stop_times;
TRUNCATE gtfs_staging_trips;
TRUNCATE gtfs_staging_shapes;
TRUNCATE gtfs_staging_stops;
TRUNCATE gtfs_staging_routes;
TRUNCATE gtfs_staging_agency;
TRUNCATE gtfs_staging_calendar;
```

### View operational data counts

```sql
SELECT 'routes' AS table, COUNT(*) FROM "route"
UNION ALL
SELECT 'stops', COUNT(*) FROM "stop"
UNION ALL
SELECT 'route_geometries', COUNT(*) FROM route_geometry
UNION ALL
SELECT 'route_stops', COUNT(*) FROM route_stop;
```

## Best Practices

1. **Always validate** staging data before ETL
2. **Review ETL logs** after transformation
3. **Test with small datasets** first
4. **Keep staging data** until verified in operational schema
5. **Monitor ETL performance** for large datasets
6. **Use incremental mode** for regular updates
7. **Use full_load mode** for complete replacements

## Performance Tips

- **Indexes**: All staging tables have indexes on key fields
- **Batch processing**: ETL uses bulk INSERT operations
- **Geometry creation**: Spatial operations are optimized
- **ANALYZE**: Tables are analyzed after ETL for query optimization

## Scheduled ETL Options

### Option 1: Docker-based Cron

```bash
# In docker-compose.yml, add a cron service
services:
  gtfs-cron:
    image: transport-db
    command: gtfs-auto-etl.sh --daemon --interval 60
    depends_on:
      - transport-db
```

### Option 2: Host Cron

```bash
# Add to host crontab
0 * * * * docker exec transport-db gtfs-etl.sh
```

### Option 3: PostgreSQL pg_cron Extension

```sql
CREATE EXTENSION pg_cron;

SELECT cron.schedule(
    'gtfs-hourly-etl',
    '0 * * * *',  -- Every hour
    $$SELECT gtfs_run_etl()$$
);
```

## Migration from Old GTFS Schema

If you have old `gtfs_*` operational tables:

```sql
-- Backup old data
CREATE TABLE gtfs_routes_backup AS SELECT * FROM gtfs_routes;

-- Drop old tables
DROP TABLE IF EXISTS gtfs_stop_times CASCADE;
DROP TABLE IF EXISTS gtfs_trips CASCADE;
DROP TABLE IF EXISTS gtfs_routes CASCADE;
DROP TABLE IF EXISTS gtfs_stops CASCADE;

-- New staging tables will be created automatically
```

## Summary

**Staging → ETL → Operational** architecture gives you:

- ✅ Data validation before going live
- ✅ Rollback capability
- ✅ Audit trail of all changes
- ✅ Flexible update schedules
- ✅ Zero downtime for data updates
- ✅ Integration with your existing schema
