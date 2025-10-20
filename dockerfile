FROM postgis/postgis:18-3.6

# Install system dependencies and PostgreSQL extensions
RUN apt-get update && apt-get install -y \
    postgresql-contrib \
    postgis \
    postgresql-18-postgis-3 \
    postgresql-18-pgrouting \
    build-essential \
    libboost-graph-dev \
    cmake \
    wget \
    expat \
    libexpat1-dev \
    libboost-dev \
    libboost-program-options-dev \
    libpqxx-dev \
    postgresql-server-dev-18 \
    && rm -rf /var/lib/apt/lists/*


# Download and compile osm2pgrouting
WORKDIR /tmp
COPY osm2pgrouting-2.3.8.tar.gz /tmp/
RUN tar -xzf osm2pgrouting-2.3.8.tar.gz \
    && cd osm2pgrouting-2.3.8 \
    && cmake -H. -Bbuild \
    && cd build \
    && make \
    && make install

# Create database directory and set up initialization scripts
RUN mkdir -p /docker-entrypoint-initdb.d

# Copy and extract compressed OSM file
COPY labeled.osm.tar.gz /tmp/
RUN tar -xzf /tmp/labeled.osm.tar.gz -C /docker-entrypoint-initdb.d/ \
    && rm /tmp/labeled.osm.tar.gz

# Copy other database files and initialization scripts
COPY schema.sql /docker-entrypoint-initdb.d/02-schema.sql
COPY init-database.sh /docker-entrypoint-initdb.d/01-init-database.sh

# Copy CSV import script (serves dual purpose: init script + manual tool)
COPY csv2db.sh /docker-entrypoint-initdb.d/03-csv2db.sh
COPY csv2db.sh /usr/local/bin/csv2db.sh

# Copy CSV directory
COPY csvs /csvs

# Make the scripts executable
RUN chmod +x /docker-entrypoint-initdb.d/01-init-database.sh \
    && chmod +x /docker-entrypoint-initdb.d/03-csv2db.sh \
    && chmod +x /usr/local/bin/csv2db.sh

# Set environment variables
ENV POSTGRES_DB=transport_db
ENV POSTGRES_USER=postgres
ENV POSTGRES_PASSWORD=postgres

# Expose PostgreSQL port
EXPOSE 5432

# Use the standard PostgreSQL entrypoint
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["postgres"]
