FROM postgis/postgis:15-3.4
# Copy ALL init SQL into the official entrypoint dir.
# These run automatically the FIRST time the data directory is created.
COPY init/ /docker-entrypoint-initdb.d/
