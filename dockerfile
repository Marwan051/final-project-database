FROM postgis/postgis:18-3.4

# Install system dependencies and PostgreSQL extensions
RUN apt-get update && apt-get install -y \
    postgresql-contrib \
    postgis \
    postgresql-18-postgis-3 \
    postgresql-18-pgrouting \
    postgresql-18-contrib \
    build-essential \
    cmake \
    libboost-graph-dev \
    libpqxx-dev \
    postgresql-server-dev-18 \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Download and compile osm2pgrouting
WORKDIR /tmp
COPY osm2pgrouting-2.3.8.tar.gz /tmp/
RUN tar -xzf osm2pgrouting-2.3.8.tar.gz \
    && cd osm2pgrouting-2.3.8 \
    && mkdir build \
    && cd build \
    && cmake .. \
    && make \
    && make install

# Create database directory and set up initialization scripts
RUN mkdir -p /docker-entrypoint-initdb.d

# Copy database files and initialization script
COPY labeled.osm /docker-entrypoint-initdb.d/
COPY test.sql /docker-entrypoint-initdb.d/
COPY init-database.sh /docker-entrypoint-initdb.d/01-init-database.sh

# Make the script executable
RUN chmod +x /docker-entrypoint-initdb.d/01-init-database.sh

# Set environment variables
ENV POSTGRES_DB=transport_db
ENV POSTGRES_USER=postgres
ENV POSTGRES_PASSWORD=postgres

# Expose PostgreSQL port
EXPOSE 5432

# Use the standard PostgreSQL entrypoint
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["postgres"]
