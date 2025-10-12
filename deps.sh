# Update package list
sudo apt update

# Install PostgreSQL and PostGIS
sudo apt install postgresql postgresql-contrib postgis postgresql-17-postgis-3

# Install pgRouting
sudo apt install postgresql-17-pgrouting

# Install additional extensions (usually included with postgresql-contrib)
sudo apt install postgresql-17-contrib
