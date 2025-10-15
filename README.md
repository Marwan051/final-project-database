# To build just the image wit no pgadmin in docker use:
```bash
docker build -t transport-db .
```
# and run it with :
```bash
docker run -d \
--name transport-db \
-p 5432:5432 \
-e POSTGRES_PASSWORD=password \
transport-db
```
---
# or run the following to build and run it with internal pgadmin routing:
```bash
docker compose up -d
```
