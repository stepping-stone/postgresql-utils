#!/usr/bin/env bash
################################################################################
# postgres-wal-archive.sh - Archive PostgreSQL server WAL files
################################################################################
#
# Copyright (C) 2013 - 2015 stepping stone GmbH
#                           Bern, Switzerland
#                           http://www.stepping-stone.ch
#                           support@stepping-stone.ch
#
# Authors:
#   Christian Affolter <christian.affolter@stepping-stone.ch>
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
# The script copies the source WAL path to the destination archive
# directory, adds a date prefix to the file name and compresses it afterwards.
#
# Input parameters:
#
# $1 - source WAL path
# $2 - source WAL file name
################################################################################

today=`date +%Y%m%d`
source_wal_path="$1"
source_wal_name="$2"
archive_dir="/var/backup/postgres/wal"
destination_wal_path="$archive_dir/$today-$source_wal_name"
compressor="/bin/bzip2 --small --best"

if test ! -d "$archive_dir" || test ! -w "$archive_dir"; then
    echo "Archive directory doesn't exists or isn't writable: $archive_dir" >&2
    exit 1
fi

if test ! -r "$source_wal_path"; then
    echo "Source WAL file doesn't exists or isn't readable: $source_wal_path" >&2
    exit 2
fi

if test -f $destination_wal_path; then
    echo "Destination WAL file already present: $destination_wal_path" \
         "won't overwrite!" >&2
    exit 3
fi

if ! cp -a "$source_wal_path" "$destination_wal_path"; then
    echo "Unable to copy the WAL file to the archive" >&2
    exit 4
fi

if ! $compressor "$destination_wal_path"; then
    echo "Unable to compress WAL file" >&2
    rm "$destination_wal_path"
    exit 5
fi

echo "successfully archived WAL file $destination_wal_path"
exit 0
