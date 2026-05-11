# PostgreSQL Database Migration Guide

## Overview

This guide explains how to safely migrate data from a **source
PostgreSQL database** to a **target PostgreSQL database** without
deleting or modifying the source data.

------------------------------------------------------------------------

## Prerequisites

-   Docker installed
-   Access to PostgreSQL instance
-   Valid credentials for:
    -   Source database user
    -   Target database user (with write permissions)
-   `pg_dump` and `psql` tools (or Docker image)

------------------------------------------------------------------------

## 1. Verify Source Database Has Data

``` bash
docker exec -it <postgres_container> psql "<SOURCE_URI>"
```

Inside psql:

``` sql
\dt
SELECT schemaname, tablename FROM pg_tables WHERE schemaname NOT IN ('pg_catalog', 'information_schema');
```

Check row counts:

``` sql
SELECT relname AS table, n_live_tup AS row_count FROM pg_stat_user_tables;
```

------------------------------------------------------------------------

## 2. Create Target Database

Connect as admin:

``` bash
docker exec -it <postgres_container> psql "<ADMIN_URI>"
```

``` sql
CREATE DATABASE <TARGET_DB>;
```

------------------------------------------------------------------------

## 3. Create Target User (if needed)

``` sql
CREATE USER <TARGET_USER> WITH PASSWORD '<TARGET_PASSWORD>';
GRANT ALL PRIVILEGES ON DATABASE <TARGET_DB> TO <TARGET_USER>;
```

------------------------------------------------------------------------

## 4. Dump Source Database

``` bash
mkdir -p /tmp/pg-backup

docker run --rm \
  --network host \
  -v /tmp/pg-backup:/backup \
  postgres:15 \
  sh -c 'pg_dump "<SOURCE_URI>" > /backup/source.sql'
```

------------------------------------------------------------------------

## 5. Restore to Target Database

``` bash
docker run --rm \
  --network host \
  -v /tmp/pg-backup:/backup \
  postgres:15 \
  sh -c 'psql "<TARGET_URI>" < /backup/source.sql'
```

------------------------------------------------------------------------

## 6. Verify Migration

``` bash
docker exec -it <postgres_container> psql "<TARGET_URI>"
```

``` sql
\dt
SELECT relname AS table, n_live_tup AS row_count FROM pg_stat_user_tables;
```

------------------------------------------------------------------------

## 7. Compare Source and Target

### Source

``` bash
docker exec -it <postgres_container> psql "<SOURCE_URI>" -c "SELECT relname AS table, n_live_tup AS row_count FROM pg_stat_user_tables;"
```

### Target

``` bash
docker exec -it <postgres_container> psql "<TARGET_URI>" -c "SELECT relname AS table, n_live_tup AS row_count FROM pg_stat_user_tables;"
```

------------------------------------------------------------------------

## Important Notes

-   This process **does NOT delete** any data from the source database.
-   Avoid using:
    -   `DROP DATABASE`
    -   `--clean` option in pg_dump
-   Ensure correct permissions before restore.

------------------------------------------------------------------------

## Example URI Format

    postgresql://<USERNAME>:<PASSWORD>@<HOST>:5432/<DATABASE>

------------------------------------------------------------------------

## Summary

  Step   Action
  ------ --------------------
  1      Verify source data
  2      Create target DB
  3      Create target user
  4      Dump source
  5      Restore to target
  6      Verify migration

------------------------------------------------------------------------
