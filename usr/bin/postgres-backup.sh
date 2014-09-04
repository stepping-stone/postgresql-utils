#!/bin/bash
################################################################################
# postgresql-backup.sh - Dump all postgres databases including the global objects
################################################################################
#
# Copyright (C) 2014 stepping stone GmbH
#                    Bern, Switzerland
#                    http://www.stepping-stone.ch
#                    support@stepping-stone.ch
#
# Authors:
#   Christian Affolter <christian.affolter@stepping-stone.ch>
#   Tiziano Müller <tiziano.mueller@stepping-stone.ch>
#
# Licensed under the EUPL, Version 1.1.
#
# You may not use this work except in compliance with the
# Licence.
# You may obtain a copy of the Licence at:
#
# http://www.osor.eu/eupl
#
# Unless required by applicable law or agreed to in
# writing, software distributed under the Licence is
# distributed on an "AS IS" basis,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
# express or implied.
# See the Licence for the specific language governing
# permissions and limitations under the Licence.
#
# Include this script in a daily cronjob.
#
################################################################################

umask 077

# default: keep dump files 14 days long before deleting them
keep_days=${1:-14}
[ -n "$2" ] && filter="AND ($2)"

psql='/usr/bin/psql'
pg_dump='/usr/bin/pg_dump --create --blobs --oids'
pg_dumpall='/usr/bin/pg_dumpall'
compressor='/bin/bzip2 --stdout --small --best'
compressor_suffix='bz2'
current_date=`/bin/date +%Y%m%d`
find_cmd='/usr/bin/find'

backup_dir='/var/backup/postgres/dump'
db_dump_dir="$backup_dir/database"
global_dump_dir="$backup_dir/global"

postgres_user="postgres-backup"

echo "dumping global objects"
$pg_dumpall -U $postgres_user --globals-only | \
    $compressor > $global_dump_dir/global.$current_date.$compressor_suffix
 
$psql -U $postgres_user -A -q -t -c "SELECT datname FROM pg_database WHERE (datname != 'template0') ${filter} ORDER BY datname;" postgres | \
while read line; do
    database=${line}
    echo "dumping database: $database";
    $pg_dump -U $postgres_user "$database" | \
        $compressor > $db_dump_dir/$database.$current_date.$compressor_suffix
done

# delete old dumps which are older than $keep_days
$find_cmd $db_dump_dir     -type f -name \*.${compressor_suffix} -mtime +$keep_days -delete
$find_cmd $global_dump_dir -type f -name \*.${compressor_suffix} -mtime +$keep_days -delete
