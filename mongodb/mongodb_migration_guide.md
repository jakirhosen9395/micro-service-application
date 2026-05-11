# MongoDB Database Migration Guide

## Overview

This guide explains how to safely migrate data from a **source MongoDB
database** to a **target MongoDB database** without deleting or
modifying the source data.

------------------------------------------------------------------------

## Prerequisites

-   Docker installed
-   Access to MongoDB container
-   Valid credentials for:
    -   Source database user
    -   Target database user (with write permissions)

------------------------------------------------------------------------

## 1. Verify Source Database Has Data

``` bash
docker exec -it <mongodb_container> mongosh "<SOURCE_URI>"
```

Inside shell:

``` javascript
show collections
db.getCollectionNames()
db.getCollectionNames().forEach(c => print(c + " => " + db.getCollection(c).countDocuments()))
```

------------------------------------------------------------------------

## 2. Create Target Database User (if not exists)

``` bash
docker exec -it <mongodb_container> mongosh "<ADMIN_URI>"
```

``` javascript
use admin
db.createUser({
  user: "<TARGET_USER>",
  pwd: "<TARGET_PASSWORD>",
  roles: [
    { role: "readWrite", db: "<TARGET_DB>" },
    { role: "dbAdmin", db: "<TARGET_DB>" }
  ]
})
```

------------------------------------------------------------------------

## 3. Initialize Target Database

``` bash
docker exec -it <mongodb_container> mongosh "<TARGET_URI>"
```

``` javascript
use <TARGET_DB>
db.init_check.insertOne({ created: true, at: new Date() })
```

(Optional cleanup)

``` bash
db.init_check.drop()
```

------------------------------------------------------------------------

## 4. Dump Source Database

``` bash
mkdir -p /tmp/mongo-backup

docker run --rm \
  --network host \
  -v /tmp/mongo-backup:/backup \
  mongo:8.0 \
  sh -c 'mongodump --uri="<SOURCE_URI>" --out=/backup'
```

------------------------------------------------------------------------

## 5. Restore to Target Database

``` bash
docker run --rm \
  --network host \
  -v /tmp/mongo-backup:/backup \
  mongo:8.0 \
  sh -c 'mongorestore --uri="<TARGET_URI>" --nsFrom="<SOURCE_DB>.*" --nsTo="<TARGET_DB>.*" /backup/<SOURCE_DB>'
```

------------------------------------------------------------------------

## 6. Verify Migration

``` bash
docker exec -it <mongodb_container> mongosh "<TARGET_URI>"
```

``` javascript
show collections
db.getCollectionNames()
db.getCollectionNames().forEach(c => print(c + " => " + db.getCollection(c).countDocuments()))
```

------------------------------------------------------------------------

## 7. Compare Source and Target

### Source

``` bash
docker exec -it <mongodb_container> mongosh "<SOURCE_URI>" --eval 'db.getCollectionNames().forEach(c => print(c + " => " + db.getCollection(c).countDocuments()))'
```

### Target

``` bash
docker exec -it <mongodb_container> mongosh "<TARGET_URI>" --eval 'db.getCollectionNames().forEach(c => print(c + " => " + db.getCollection(c).countDocuments()))'
```

------------------------------------------------------------------------

## Important Notes

-   This process **does NOT delete** any data from the source database.
-   Avoid using:
    -   `--drop`
    -   `db.dropDatabase()`
-   Ensure correct credentials and permissions before running restore.

------------------------------------------------------------------------

## Example URI Format

    mongodb://<USERNAME>:<PASSWORD>@<HOST>:27017/<DATABASE>?authSource=admin

------------------------------------------------------------------------

## Summary

  Step   Action
  ------ ----------------------
  1      Verify source data
  2      Create target user
  3      Initialize target DB
  4      Dump source
  5      Restore to target
  6      Verify migration

------------------------------------------------------------------------
