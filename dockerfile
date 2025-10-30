FROM postgis/postgis:18-3.6

# Install system dependencies and PostgreSQL extensions
RUN apt-get update && apt-get install -y \
    postgresql-contrib \
    postgis \
    postgresql-18-postgis-3 \
    postgresql-18-pgrouting \
    && rm -rf /var/lib/apt/lists/*

# Create database directory and set up initialization scripts
RUN mkdir -p /docker-entrypoint-initdb.d

# Copy other database files and initialization scripts
COPY schema.sql /docker-entrypoint-initdb.d/02-schema.sql
COPY init-database.sh /docker-entrypoint-initdb.d/01-init-database.sh

# Copy GTFS staging schema, ETL scripts, and initialization
COPY gtfs-staging-schema.sql /docker-entrypoint-initdb.d/03-gtfs-staging-schema.sql
COPY gtfs-etl-transform.sql /docker-entrypoint-initdb.d/04-gtfs-etl-transform.sql
COPY init-gtfs.sh /docker-entrypoint-initdb.d/05-init-gtfs.sh

# Copy GTFS tools to /usr/local/bin
COPY gtfs2db.sh /usr/local/bin/gtfs2db.sh
COPY gtfs-etl.sh /usr/local/bin/gtfs-etl.sh
COPY gtfs-auto-etl.sh /usr/local/bin/gtfs-auto-etl.sh

# Copy GTFS data directory
COPY gtfs-data /gtfs-data

# Copy CSV import script as manual tool only (optional, not part of init)
COPY csv2db.sh /usr/local/bin/csv2db.sh

# Make the scripts executable
RUN chmod +x /docker-entrypoint-initdb.d/01-init-database.sh \
    && chmod +x /docker-entrypoint-initdb.d/05-init-gtfs.sh \
    && chmod +x /usr/local/bin/csv2db.sh \
    && chmod +x /usr/local/bin/gtfs2db.sh \
    && chmod +x /usr/local/bin/gtfs-etl.sh \
    && chmod +x /usr/local/bin/gtfs-auto-etl.sh

# Set environment variables
ENV POSTGRES_DB=transport_db
ENV POSTGRES_USER=postgres
ENV POSTGRES_PASSWORD=postgres

# Expose PostgreSQL port
EXPOSE 5432

# Use the standard PostgreSQL entrypoint
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["postgres"]
