#!/bin/bash

wal_dir=/var/backup/postgres/wal

# delete old WAL files which were last modified 48h ago
/usr/bin/find $wal_dir -mtime +2 -delete
