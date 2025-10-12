#!/bin/bash
set -e

echo "Setting up database with PostGIS and pgRouting..."

# Wait for PostgreSQL to be ready
until pg_isready -h localhost -p 5432 -U "$POSTGRES_USER"; do
    echo "Waiting for PostgreSQL to be ready..."
    sleep 2
done

# Create database if it doesn't exist and enable extensions
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Enable required extensions
    CREATE EXTENSION IF NOT EXISTS postgis;
    CREATE EXTENSION IF NOT EXISTS pg_trgm;
    CREATE EXTENSION IF NOT EXISTS btree_gin;
    CREATE EXTENSION IF NOT EXISTS pgrouting;
EOSQL

echo "Extensions installed successfully."

# Process OSM data with osm2pgrouting
echo "Processing OSM data with osm2pgrouting..."
osm2pgrouting \
    --f /docker-entrypoint-initdb.d/labeled.osm \
    --conf /usr/local/share/osm2pgrouting/mapconfig.xml \
    --dbname "$POSTGRES_DB" \
    --username "$POSTGRES_USER" \
    --host localhost \
    --port 5432 \
    --clean

echo "OSM data processing completed."

# Apply custom schema
echo "Applying custom schema from test.sql..."
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f /docker-entrypoint-initdb.d/test.sql

echo "Database initialization completed successfully."