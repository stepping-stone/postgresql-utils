#!/usr/bin/env bash
################################################################################
# postgresql-backup.sh - Dump all postgres databases including the global objects
################################################################################
#
# Copyright (C) 2025 stepping stone AG
#                    Bern, Switzerland
#                    http://www.stepping-stone.ch
#                    support@stepping-stone.ch
#
# Authors:
#   Christian Affolter <christian.affolter@stepping-stone.ch>
#   Tiziano Müller <tiziano.mueller@stepping-stone.ch>
#   Yannick Denzer <yannick.denzer@stepping-stone.ch>
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

set -o errexit
umask 0027

# Options: default values.
opt_xtrace=false
opt_quiet=false
opt_dry_run=false
opt_prune=true
opt_global=true
opt_create=true
opt_clean=false
opt_no_owner=false
opt_no_privileges=false
opt_no_acl=false
opt_column_inserts=false
opt_oids=''
opt_config_file=/etc/postgres-backup.conf
opt_retention=14d
opt_date_format=%Y%m%d
opt_filter=''
opt_db_dump_dir=/var/backup/postgres/dump/database
opt_global_dump_dir=/var/backup/postgres/dump/global
opt_postgres_user=postgres-backup
opt_filename_template='{database}-{date}.gz'
opt_compressor='gzip --rsyncable --stdout'
opt_databases=''

help_manual=$(cat <<EOF
USAGE

	$(basename "$0") [OPTIONS] [RETENTION_IN_DAYS] [FILTER]

DEPRECATION NOTICE

	The positional arguments RETENTION_IN_DAYS and FILTER are deprecated.
	Please use the options --retention DURATION and --filter FILTER instead.

OPTIONS

	-h, --help			Show this help manual.

	-x, --xtrace			Enable Bash xtrace (set -o xtrace).

	-q, --quiet			Do not output any informational messages. Error messages will still
					be printed.

	-n, --dry-run			Perform a trial run without doing any dumps.

	--no-prune			Do not prune old dumps.

	--no-global			Do not create the global objects dump.

	--no-create			Do not use --create with pg_dump.

	--clean				Add --clean to pg_dump.

	--no-owner			Add --no-owner to pg_dump.

	--no-privileges			Add --no-privileges to pg_dump.

	--no-acl			Add --no-acl to pg_dump.

	--column-inserts		Add --column-inserts to pg_dump.

	--oids				Append --oids to pg_dump when dumping databases.

	--no-oids			Do not append --oids to pg_dump when dumping databases.
					If neither option --no-oids nor --oids is passed to the script,
					the pg_dump option --oids is automatically appended if the PostgreSQL
					version is 11 or older.

	--config-file FILE_PATH		Path pointing to the configuration file. Default: "$opt_config_file".

	--databases DATABASES		Databases to dump. Default: all databases.
					DATABASES is a list of database names, separated by comma.

	--retention DURATION		Duration to retain the created dumps. Default: "$opt_retention".
					DURATION is a non-zero, possibly signed sequence of decimal numbers
					followed by a unit suffix. Valid units are "m" for minutes,
					"h" for hours, and "d" for days.

	--date-format FORMAT		Date format to use in dump file names. Default: "$opt_date_format".
					FORMAT corresponds to the format used by the GNU date utility.

	--filter FILTER			SQL filter to apply when searching for databases to dump.
					Default: "$opt_filter".

	--db-dump-dir PATH		Path pointing to the directory where database dumps will be
					stored. Default: "$opt_db_dump_dir".

	--global-dump-dir PATH		Path pointing to the directory where the global objects dump
					will be stored. Default: "$opt_global_dump_dir".

	--postgres-user USER		PostgreSQL user to use to create the dumps. Default: "$opt_postgres_user".

	--filename-template TEMPLATE	Template for dump file names. Default: "$opt_filename_template".
					TEMPLATE may contain the following strings, which will be replaced
					accordingly:

					{database}	The database name. For the global objects, this
							yields to "globals".
					{date}		The current date, formatted according to the specified
							date format.

					TEMPLATE may also contain slashes (/). The following template places
					each dump file in a directory named after the corresponding database:

					{database}/{database}-{date}.gz

	--compressor COMMAND		The command to use to compress dump files. Default: "$opt_compressor".
					You may want to change the file name extention via --filename-template
					if you specify a custom compressor.

CONFIGURATION FILE

	You may use a configuration file (default location "$opt_config_file") to configure the PostgreSQL
	backup script. The configuration file is sourced, so it is essentialy a Bash script. The PostgreSQL
	backup script can be configured with the following variables:

$(
	printf '%8s%-22s %-35s %s\n\n' '' VARIABLE 'DEFAULT VALUE' 'COMMAND LINE EQUIVALENT'
	for var in \
		opt_xtrace \
		opt_quiet \
		opt_dry_run \
		opt_prune \
		opt_global \
		opt_create \
		opt_clean \
		opt_no_owner \
		opt_no_privileges \
		opt_no_acl \
		opt_column_inserts \
		opt_oids \
		opt_config_file \
		opt_retention \
		opt_date_format \
		opt_filter \
		opt_db_dump_dir \
		opt_global_dump_dir \
		opt_postgres_user \
		opt_filename_template \
		opt_compressor \
		opt_databases
	do
		value=${!var}
		value=${value:-\'\'}
		option=${var#opt_}
		option=--${option//_/-}
		printf '%8s%-22s %-35s %s\n' '' "$var" "$value" "$option"
	done
)
EOF
)

help() {
	local exit_code=0

	if [[ -n "$1" ]]
	then
		printf '\033[1;31mERROR: %s\033[0m\n\n' "$1" >&2
		exit_code=1
	fi

	echo "$help_manual" >&2
	echo >&2
	exit "$exit_code"
}

# Look for the option "--config-file" first, as command line options must
# override configuration file options.
args=("$@")
config_file=''

while [[ $# -gt 0 ]]
do
	case "$1" in
	-h|--help|-x|--xtrace|-q|--quiet|-n|--dry-run|--no-prune|--no-global|--no-create|--clean|--no-owner|--no-privileges|--no-acl|--column-inserts|--no-oids|--oids)
		shift
		;;
	--databases|--retention|--date-format|--filter|--db-dump-dir|--global-dump-dir|--postgres-user|--filename-template|--compressor)
		shift 2
		;;
	--config-file)
		[[ $# -lt 2 ]] && help '--config-file requires an argument.'
		config_file="$2"
		shift 2
		;;
	*)
		shift
		;;
	esac
done

if [[ -n "$config_file" ]]
then
	# Configuration file supplied via command line.
	source "$config_file"
elif [[ -f "$opt_config_file" ]]
then
	# Load default configuration file, as it exists.
	source "$opt_config_file"
fi

# Restore command line arguments.
set -- "${args[@]}"

# Variable to keep track of positional arguments.
posarg=0

while [[ $# -gt 0 ]]
do
	case "$1" in
	-h|--help)
		help
		;;
	-x|--xtrace)
		opt_xtrace=true
		shift
		;;
	-q|--quiet)
		opt_quiet=true
		shift
		;;
	-n|--dry-run)
		opt_dry_run=true
		shift
		;;
	--no-prune)
		opt_prune=false
		shift
		;;
	--no-global)
		opt_global=false
		shift
		;;
	--no-create)
		opt_create=false
		shift
		;;
	--clean)
		opt_clean=true
		shift
		;;
	--no-owner)
		opt_no_owner=true
		shift
		;;
	--no-privileges)
		opt_no_privileges=true
		shift
		;;
	--no-acl)
		opt_no_acl=true
		shift
		;;
	--column-inserts)
		opt_column_inserts=true
		shift
		;;
	--no-oids)
		opt_oids=false
		shift
		;;
	--oids)
		opt_oids=true
		shift
		;;
	--config-file)
		# Skip this option, as we have loaded its value before.
		shift 2
		;;
	--databases)
		[[ $# -lt 2 ]] && help '--databases requires an argument.'
		opt_databases="$2"
		shift 2
		;;
	--retention)
		[[ $# -lt 2 ]] && help '--retention requires an argument.'
		opt_retention="$2"
		shift 2
		;;
	--date-format)
		[[ $# -lt 2 ]] && help '--date-format requires an argument.'
		opt_date_format="$2"
		shift 2
		;;
	--filter)
		[[ $# -lt 2 ]] && help '--filter requires an argument.'
		opt_filter="AND ($2)"
		shift 2
		;;
	--db-dump-dir)
		[[ $# -lt 2 ]] && help '--db-dump-dir requires an argument.'
		opt_db_dump_dir="$2"
		shift 2
		;;
	--global-dump-dir)
		[[ $# -lt 2 ]] && help '--global-dump-dir requires an argument.'
		opt_global_dump_dir="$2"
		shift 2
		;;
	--postgres-user)
		[[ $# -lt 2 ]] && help '--postgres-user requires an argument.'
		opt_postgres_user="$2"
		shift 2
		;;
	--filename-template)
		[[ $# -lt 2 ]] && help '--filename-template requires an argument.'
		opt_filename_template="$2"
		shift 2
		;;
	--compressor)
		[[ $# -lt 2 ]] && help '--compressor requires an argument.'
		opt_compressor="$2"
		shift 2
		;;
	-*)
		help "Invalid option: $1"
		;;
	*)
		let posarg++

		case "$posarg" in
		1) opt_retention="$1"d ;;
		2) opt_filter="AND ($1)" ;;
		*) help "Exceeding positional argument: $1" ;;
		esac

		shift
		;;
	esac
done

grep --quiet '^[1-9][0-9]*[mhd]$' <<< "$opt_retention" || help "Invalid retention duration: $opt_retention"

case "$opt_retention" in
*m) let opt_retention="${opt_retention::-1}" ;;
*h) let opt_retention="${opt_retention::-1}*60" ;;
*d) let opt_retention="${opt_retention::-1}*60*24" ;;
esac

apply_template() {
	local s="$1"
	s="${s//\{database\}/$2}"
	s="${s//\{date\}/$3}"
	echo "$s"
}

$opt_xtrace && set -o xtrace

current_date="$(date +"$opt_date_format")"

if [[ -z "$opt_oids" ]]
then
	opt_oids=false
	pg_version="$(psql --version | sed 's/.* //; s/\..*//')"

	if grep --quiet --extended-regexp '^[0-9]+$' <<< "$pg_version"
	then
		[[ "$pg_version" -le 11 ]] && opt_oids=true
	else
		echo "WARNING: invalid PostgreSQL version: $pg_version"
	fi
fi

if $opt_global
then
	destination="$opt_global_dump_dir"/"$(apply_template "$opt_filename_template" global "$current_date")"
	$opt_quiet || echo "Dumping global objects to $destination"

	if ! $opt_dry_run
	then
		mkdir --parents "$(dirname "$destination")"
		pg_dumpall \
			--globals-only \
			--username "$opt_postgres_user" \
			| eval "$opt_compressor" > "$destination"
	fi
fi

if [[ -n "$opt_databases" ]]
then
	databases=${opt_databases//,/ }
else
	databases=$(
		psql \
			--quiet \
			--no-align \
			--tuples-only \
			--username "$opt_postgres_user" \
			--command "SELECT datname FROM pg_database WHERE datname != 'template0' $opt_filter ORDER BY datname;" \
			postgres
	)
fi

for database in $databases
do
	destination="$opt_db_dump_dir"/"$(apply_template "$opt_filename_template" "$database" "$current_date")"
	$opt_quiet || echo "Dumping database $database to $destination"

	if ! $opt_dry_run
	then
		mkdir --parents "$(dirname "$destination")"
		pg_dump \
			$($opt_create && echo --create) \
			$($opt_clean && echo --clean) \
			$($opt_no_owner && echo --no-owner) \
			$($opt_no_privileges && echo --no-privileges) \
			$($opt_no_acl && echo --no-acl) \
			$($opt_column_inserts && echo --column-inserts) \
			--blobs \
			$($opt_oids && echo --oids) \
			--username "$opt_postgres_user" \
			"$database" \
			| eval "$opt_compressor" > "$destination"
	fi
done

if $opt_prune
then
	prune() {
		find \
			"$opt_db_dump_dir" \
			"$opt_global_dump_dir" \
			-type f \
			-mmin +"$opt_retention" \
			$($opt_dry_run || echo -delete) \
			"$@"
	}

	if $opt_quiet
	then
		prune -printf ''
	else
		echo 'Removing old dump files'
		prune -printf 'Removing %p\n'
	fi
fi
