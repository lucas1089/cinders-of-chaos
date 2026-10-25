#!/usr/bin/env bash
# Cinders of Chaos backup: a gzip'd mysqldump of the game database plus, when it changed, an archive of the server's
# config.lua and data/ (without the map .otbm files and logs). Keeps the last N days. Restore: docs/LAUNCH.md, "Backups".
#
# usage: server/tools/backup.sh [--dir DIR] [--keep-days N] [--server-dir DIR] [--db NAME]
#                               [--save-service UNIT | --save-pid PID] [--save-log FILE] [--no-data] [--dry-run]
#
# Settings come from the environment (/etc/chaos/chaos.env, see server/deploy/chaos.env.example), options override them:
#   CHAOS_DB_HOST CHAOS_DB_PORT CHAOS_DB_USER CHAOS_DB_PASS CHAOS_DB_NAME   the database (password never on a command line:
#                                                                           a temporary option file, mode 0600)
#   CHAOS_DB_SOCKET: a Unix socket instead of host and port. mariadb-dump is used when there is no mysqldump.
#   CHAOS_BACKUP_DIR (default /var/backups/chaos), CHAOS_BACKUP_KEEP_DAYS (default 14), CHAOS_SERVER_DIR
# --save-service UNIT / --save-pid PID: send SIGUSR1 first, so the engine saves every online player and every changed
# house before the dump; the script then waits --save-wait seconds (15). With engine src-patch 0026 the engine answers
# SIGUSR1 with the autosave in steps (a few players per tick, no freeze; about 3.5 s at 200 online, 7-8 s at 400) and keeps
# running; a dump that starts before the pass ends still holds every character as of its last save (each save is one
# transaction per character). server/README.md "Autosave in steps".
# --save-log FILE (the engine's console log): the wait ends as soon as the engine prints "> Saved in steps:" after the
# signal (polled twice a second), --save-wait stays the longest wait; without the option, or with an engine that does not
# print the line, the wait is the whole --save-wait.
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
SAVE_LOG=""
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
		--save-log) SAVE_LOG=${2:?}; shift 2 ;;
		--no-data) DATA=0; shift ;;
		--dry-run) DRY=1; shift ;;
		-h|--help) sed -n '2,20p' "$0"; exit 0 ;;
		*) die "unknown option $1 (see --help)" ;;
	esac
done

[ -n "$DB" ] || die "no database: set CHAOS_DB_NAME or pass --db"
[[ "$KEEP" =~ ^[0-9]+$ ]] || die "--keep-days must be a number"
[[ "$SAVE_WAIT" =~ ^[0-9]+$ ]] || die "--save-wait must be a number"
DUMP=mysqldump
command -v mysqldump >/dev/null || DUMP=mariadb-dump
command -v "$DUMP" >/dev/null || die "mysqldump (or mariadb-dump) not found"
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
	if [ -n "${CHAOS_DB_SOCKET:-}" ]; then
		echo "socket=\"$(quote "$CHAOS_DB_SOCKET")\""
	else
		if [ -n "${CHAOS_DB_HOST:-}" ]; then echo "host=\"$(quote "$CHAOS_DB_HOST")\""; fi
		if [ -n "${CHAOS_DB_PORT:-}" ]; then echo "port=$CHAOS_DB_PORT"; fi
	fi
	if [ -n "${CHAOS_DB_USER:-}" ]; then echo "user=\"$(quote "$CHAOS_DB_USER")\""; fi
	if [ -n "${CHAOS_DB_PASS:-}" ]; then echo "password=\"$(quote "$CHAOS_DB_PASS")\""; fi
} > "$OPT"

# wait_saved FROM: until the engine log, after byte FROM, has the "Saved in steps" line (the end of the save pass), at most
# SAVE_WAIT seconds; the whole SAVE_WAIT without a readable log
wait_saved() {
	local from=$1 i n=$((SAVE_WAIT * 2))
	if [ -z "$SAVE_LOG" ] || [ ! -r "$SAVE_LOG" ]; then sleep "$SAVE_WAIT"; return 0; fi
	for ((i = 0; i < n; i++)); do
		if tail -c +"$((from + 1))" "$SAVE_LOG" 2>/dev/null | grep -q '> Saved in steps:'; then
			log "the engine finished the save after about $((i / 2)) s"
			return 0
		fi
		sleep 0.5
	done
	log "no 'Saved in steps' line in ${SAVE_WAIT}s: dumping as it is"
}
log_end() { if [ -n "$SAVE_LOG" ]; then stat -c %s "$SAVE_LOG" 2>/dev/null || echo 0; else echo 0; fi; }

# 1. ask the engine to save (players and houses live in the database)
if [ -n "$SAVE_SERVICE" ]; then
	if systemctl is-active --quiet "$SAVE_SERVICE"; then
		from=$(log_end)
		systemctl kill -s SIGUSR1 --kill-whom=main "$SAVE_SERVICE" && log "asked $SAVE_SERVICE to save, waiting up to ${SAVE_WAIT}s"
		wait_saved "$from"
	else
		log "$SAVE_SERVICE is not running, dumping as it is"
	fi
elif [ -n "$SAVE_PID" ]; then
	from=$(log_end)
	kill -USR1 "$SAVE_PID" && log "asked pid $SAVE_PID to save, waiting up to ${SAVE_WAIT}s"
	wait_saved "$from"
fi

# 2. the database: one consistent InnoDB snapshot, without locking the game
"$DUMP" --defaults-extra-file="$OPT" --single-transaction --quick --routines --triggers --events --hex-blob \
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
		# The server is up: a file it writes (or a folder it adds a file to) can change while tar reads it. GNU tar then
		# exits 1 with a whole, readable archive; 2 is a real error. Three tries 2 s apart, then the last archive stays
		# with a warning (the changed file is a runtime one, the scripts under data/ do not change while the server runs).
		try=1
		while :; do
			rc=0
			tar -C "$SERVER" --exclude='*.otbm' --exclude='data/logs' --exclude='data/reports' -czf "$TARTMP" config.lua data || rc=$?
			[ "$rc" = 0 ] && break
			[ "$rc" = 1 ] || die "tar failed (status $rc)"
			gzip -t "$TARTMP" || die "the data archive is not a valid gzip file"
			if [ "$try" -ge 3 ]; then
				log "warning: files under data/ changed while they were archived (3 tries); the archive is kept"
				break
			fi
			log "files under data/ changed while they were archived; try $((try + 1)) of 3 in 2 s"
			try=$((try + 1))
			sleep 2
		done
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
