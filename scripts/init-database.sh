#!/bin/bash
set -e

echo "Setting up database with PostGIS and pgRouting..."

# Set PostgreSQL connection environment variables for Unix socket
export PGHOST=/var/run/postgresql
export PGPORT=5432
export PGUSER="$POSTGRES_USER"
export PGDATABASE="$POSTGRES_DB"

# Connect to the transport_db database and set up extensions
psql -v ON_ERROR_STOP=1 <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS postgis;
    CREATE EXTENSION IF NOT EXISTS pgrouting;
    CREATE EXTENSION IF NOT EXISTS pg_trgm;
    CREATE EXTENSION IF NOT EXISTS btree_gin;
EOSQL

echo "Extensions created successfully"

# Apply custom schema
echo "Applying custom schema..."
psql -v ON_ERROR_STOP=1 -f /docker-entrypoint-initdb.d/02-schema.sql

echo "Database setup complete!"