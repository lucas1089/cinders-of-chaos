#!/usr/bin/env bash
# Project Chaos backup: a gzip'd mysqldump of the game database plus, when it changed, an archive of the server's
# config.lua and data/ (without the map .otbm files and logs). Keeps the last N days. Restore: docs/LAUNCH.md, "Backups".
#
# usage: server/tools/backup.sh [--dir DIR] [--keep-days N] [--server-dir DIR] [--db NAME]
#                               [--save-service UNIT | --save-pid PID] [--no-data] [--dry-run]
#
# Settings come from the environment (/etc/chaos/chaos.env, see server/deploy/chaos.env.example), options override them:
#   CHAOS_DB_HOST CHAOS_DB_PORT CHAOS_DB_USER CHAOS_DB_PASS CHAOS_DB_NAME   the database (password never on a command line:
#                                                                           a temporary option file, mode 0600)
#   CHAOS_BACKUP_DIR (default /var/backups/chaos), CHAOS_BACKUP_KEEP_DAYS (default 14), CHAOS_SERVER_DIR
# --save-service UNIT / --save-pid PID: send SIGUSR1 first, so the engine saves every online player and house before the
# dump (the engine answers SIGUSR1 with a full save and keeps running); the script then waits --save-wait seconds (15).
#
# Files: DIR/db/chaos-db-<name>-YYYYmmdd-HHMMSS.sql.gz and DIR/data/chaos-data-YYYYmmdd-HHMMSS.tar.gz (a data archive is
# only written when config.lua or data/ differ from the newest archive, compared by a checksum list). Every dump is
# checked with gzip -t and must end with mysqldump's "Dump completed" line. Exit status != 0 on any failure.
set -euo pipefail
umask 077

DIR=${CHAOS_BACKUP_DIR:-/var/backups/chaos}
KEEP=${CHAOS_BACKUP_KEEP_DAYS:-14}
SERVER=${CHAOS_SERVER_DIR:-}
DB=${CHAOS_DB_NAME:-}
SAVE_SERVICE=""
SAVE_PID=""
SAVE_WAIT=15
DATA=1
DRY=0

die() { echo "backup: $*" >&2; exit 1; }
log() { echo "[$(date '+%F %T')] $*"; }

while [ $# -gt 0 ]; do
	case "$1" in
		--dir) DIR=${2:?}; shift 2 ;;
		--keep-days) KEEP=${2:?}; shift 2 ;;
		--server-dir) SERVER=${2:?}; shift 2 ;;
		--db) DB=${2:?}; shift 2 ;;
		--save-service) SAVE_SERVICE=${2:?}; shift 2 ;;
		--save-pid) SAVE_PID=${2:?}; shift 2 ;;
		--save-wait) SAVE_WAIT=${2:?}; shift 2 ;;
		--no-data) DATA=0; shift ;;
		--dry-run) DRY=1; shift ;;
		-h|--help) sed -n '2,20p' "$0"; exit 0 ;;
		*) die "unknown option $1 (see --help)" ;;
	esac
done

[ -n "$DB" ] || die "no database: set CHAOS_DB_NAME or pass --db"
[[ "$KEEP" =~ ^[0-9]+$ ]] || die "--keep-days must be a number"
[[ "$SAVE_WAIT" =~ ^[0-9]+$ ]] || die "--save-wait must be a number"
command -v mysqldump >/dev/null || die "mysqldump not found"
if [ "$DATA" = 1 ] && [ -n "$SERVER" ]; then
	[ -f "$SERVER/config.lua" ] && [ -d "$SERVER/data" ] || die "$SERVER is not a server folder (config.lua, data/)"
fi

STAMP=$(date '+%Y%m%d-%H%M%S')
DBFILE="$DIR/db/chaos-db-$DB-$STAMP.sql.gz"
if [ "$DRY" = 1 ]; then
	log "dry run: would dump \`$DB\` to $DBFILE, keep $KEEP day(s)${SERVER:+, archive $SERVER when it changed}"
	exit 0
fi

mkdir -p "$DIR/db" "$DIR/data"
exec 9>"$DIR/.lock"
flock -n 9 || die "another backup is running ($DIR/.lock)"

OPT=$(mktemp)
trap 'rm -f "$OPT" "$DBFILE.partial" "${TARTMP:-}"' EXIT
quote() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
{
	echo "[client]"
	if [ -n "${CHAOS_DB_HOST:-}" ]; then echo "host=\"$(quote "$CHAOS_DB_HOST")\""; fi
	if [ -n "${CHAOS_DB_PORT:-}" ]; then echo "port=$CHAOS_DB_PORT"; fi
	if [ -n "${CHAOS_DB_USER:-}" ]; then echo "user=\"$(quote "$CHAOS_DB_USER")\""; fi
	if [ -n "${CHAOS_DB_PASS:-}" ]; then echo "password=\"$(quote "$CHAOS_DB_PASS")\""; fi
} > "$OPT"

# 1. ask the engine to save (players and houses live in the database)
if [ -n "$SAVE_SERVICE" ]; then
	if systemctl is-active --quiet "$SAVE_SERVICE"; then
		systemctl kill -s SIGUSR1 --kill-whom=main "$SAVE_SERVICE" && log "asked $SAVE_SERVICE to save, waiting ${SAVE_WAIT}s"
		sleep "$SAVE_WAIT"
	else
		log "$SAVE_SERVICE is not running, dumping as it is"
	fi
elif [ -n "$SAVE_PID" ]; then
	kill -USR1 "$SAVE_PID" && log "asked pid $SAVE_PID to save, waiting ${SAVE_WAIT}s"
	sleep "$SAVE_WAIT"
fi

# 2. the database: one consistent InnoDB snapshot, without locking the game
mysqldump --defaults-extra-file="$OPT" --single-transaction --quick --routines --triggers --events --hex-blob \
	--default-character-set=utf8mb4 "$DB" | gzip -6 > "$DBFILE.partial"
gzip -t "$DBFILE.partial" || die "the dump is not a valid gzip file"
zcat "$DBFILE.partial" | tail -n 1 | grep -q 'Dump completed' || die "the dump is incomplete (no 'Dump completed' line)"
mv "$DBFILE.partial" "$DBFILE"
log "database \`$DB\`: $DBFILE ($(du -h "$DBFILE" | cut -f1))"

# 3. the server's data, only when it changed since the last archive
if [ "$DATA" = 1 ] && [ -n "$SERVER" ]; then
	SUMS=$(cd "$SERVER" && find config.lua data -type f ! -name '*.otbm' ! -path 'data/logs/*' ! -path 'data/reports/*' \
		-print0 | sort -z | xargs -0 sha1sum | sha1sum | cut -d' ' -f1)
	if [ -f "$DIR/data/.last" ] && [ "$(cat "$DIR/data/.last")" = "$SUMS" ] && ls "$DIR"/data/chaos-data-*.tar.gz >/dev/null 2>&1; then
		log "server data unchanged since the last archive"
	else
		TARTMP="$DIR/data/chaos-data-$STAMP.tar.gz.partial"
		tar -C "$SERVER" --exclude='*.otbm' --exclude='data/logs' --exclude='data/reports' -czf "$TARTMP" config.lua data
		mv "$TARTMP" "$DIR/data/chaos-data-$STAMP.tar.gz"
		echo "$SUMS" > "$DIR/data/.last"
		log "server data: $DIR/data/chaos-data-$STAMP.tar.gz ($(du -h "$DIR/data/chaos-data-$STAMP.tar.gz" | cut -f1))"
	fi
fi

# 4. retention: older than KEEP days goes, but the newest database dump and data archive always stay
prune() {
	local pattern=$1 newest
	newest=$(ls -1t $pattern 2>/dev/null | head -n 1 || true)
	find "$(dirname "$pattern")" -maxdepth 1 -name "$(basename "$pattern")" -type f -mtime +"$KEEP" -print 2>/dev/null |
		while read -r f; do
			[ "$f" = "$newest" ] && continue
			rm -f -- "$f" && log "removed $f (older than $KEEP days)"
		done
}
prune "$DIR/db/chaos-db-*.sql.gz"
prune "$DIR/data/chaos-data-*.tar.gz"
log "done"
