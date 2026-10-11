#!/usr/bin/env bash
# Cinders of Chaos off-site backup copy: sends the newest database dump (and the newest server data archive) that
# server/tools/backup.sh wrote to another machine, encrypted when a key is set, and prunes old copies there.
# chaos-backup.service runs it right after backup.sh. Owner setup: docs/LAUNCH.md "Off-site copy".
#
# usage: server/tools/backup_offsite.sh [--dir DIR] [--dry-run]
#
# Settings (/etc/chaos/chaos.env, see server/deploy/chaos.env.example). With neither target set it notes that once and
# exits 0.
#   CHAOS_BACKUP_DIR              local backups (default /var/backups/chaos)
#   CHAOS_BACKUP_REMOTE           an rclone remote and folder, e.g. b2:chaos-backups or gdrive:chaos (any rclone backend)
#   CHAOS_RCLONE_CONFIG           rclone's config file (default /etc/chaos/rclone.conf)
#   CHAOS_BACKUP_RSYNC            an rsync / scp target [user@]host:/path (the folder must exist) or a local mounted path
#   CHAOS_BACKUP_RSYNC_TOOL       rsync (default) or scp, for a target without rsync
#   CHAOS_BACKUP_SSH_KEY          the ssh key for CHAOS_BACKUP_RSYNC (default: root's ssh setup)
#   CHAOS_BACKUP_REMOTE_KEEP      days to keep copies on the target (default 30; 0 keeps everything)
#   CHAOS_BACKUP_AGE_RECIPIENT    encrypt with age to this public key (age1...) or recipients file
#   CHAOS_BACKUP_GPG_RECIPIENT    encrypt with gpg to this key id (imported into CHAOS_BACKUP_GPG_HOME, default
#                                 /etc/chaos/gnupg)
#   CHAOS_BACKUP_PASSPHRASE_FILE  encrypt with gpg, symmetric AES256, with the passphrase in this file (mode 0600)
# The first key set wins, in that order. Without one the files go as they are (the dump has password hashes: encrypt
# unless the target is your own machine).
#
# On success it writes DIR/.offsite_last (chaos_health.py alerts when it is older than 26 h) and adds the names it sent
# to DIR/.offsite_sent, so a file goes once. Exit status != 0 when a copy fails.
set -euo pipefail
umask 077

DIR=${CHAOS_BACKUP_DIR:-/var/backups/chaos}
REMOTE=${CHAOS_BACKUP_REMOTE:-}
RCONF=${CHAOS_RCLONE_CONFIG:-/etc/chaos/rclone.conf}
RSYNC_TARGET=${CHAOS_BACKUP_RSYNC:-}
RSYNC_TOOL=${CHAOS_BACKUP_RSYNC_TOOL:-rsync}
SSH_KEY=${CHAOS_BACKUP_SSH_KEY:-}
KEEP=${CHAOS_BACKUP_REMOTE_KEEP:-30}
AGE_RCPT=${CHAOS_BACKUP_AGE_RECIPIENT:-}
GPG_RCPT=${CHAOS_BACKUP_GPG_RECIPIENT:-}
GPG_HOME=${CHAOS_BACKUP_GPG_HOME:-/etc/chaos/gnupg}
PASSFILE=${CHAOS_BACKUP_PASSPHRASE_FILE:-}
DRY=0

die() { echo "[$(date '+%F %T')] offsite: $*" >&2; exit 1; }
log() { echo "[$(date '+%F %T')] offsite: $*"; }

while [ $# -gt 0 ]; do
	case "$1" in
		--dir) DIR=${2:?}; shift 2 ;;
		--dry-run) DRY=1; shift ;;
		-h|--help) sed -n '2,27p' "$0"; exit 0 ;;
		*) die "unknown option $1 (see --help)" ;;
	esac
done

if [ -z "$REMOTE" ] && [ -z "$RSYNC_TARGET" ]; then
	log "not configured (CHAOS_BACKUP_REMOTE and CHAOS_BACKUP_RSYNC are empty): no off-site copy"
	exit 0
fi
[[ "$KEEP" =~ ^[0-9]+$ ]] || die "CHAOS_BACKUP_REMOTE_KEEP must be a number of days"
[ -d "$DIR/db" ] || die "no $DIR/db: run backup.sh first"

# encryption
ENC=none SUFFIX=""
if [ -n "$AGE_RCPT" ]; then
	command -v age >/dev/null || die "CHAOS_BACKUP_AGE_RECIPIENT is set but age is not installed"
	ENC=age SUFFIX=.age
elif [ -n "$GPG_RCPT" ]; then
	command -v gpg >/dev/null || die "CHAOS_BACKUP_GPG_RECIPIENT is set but gpg is not installed"
	ENC=gpg-key SUFFIX=.gpg
elif [ -n "$PASSFILE" ]; then
	command -v gpg >/dev/null || die "CHAOS_BACKUP_PASSPHRASE_FILE is set but gpg is not installed"
	[ -s "$PASSFILE" ] || die "the passphrase file $PASSFILE is missing or empty"
	ENC=gpg-pass SUFFIX=.gpg
fi
if [ -n "$REMOTE" ]; then
	command -v rclone >/dev/null || die "CHAOS_BACKUP_REMOTE is set but rclone is not installed"
	[ -f "$RCONF" ] || die "no rclone config at $RCONF (rclone config --config $RCONF)"
fi
if [ -n "$RSYNC_TARGET" ]; then
	case "$RSYNC_TOOL" in rsync|scp) ;; *) die "CHAOS_BACKUP_RSYNC_TOOL must be rsync or scp" ;; esac
	command -v "$RSYNC_TOOL" >/dev/null || die "$RSYNC_TOOL is not installed"
fi

newest() { ls -1t $1 2>/dev/null | head -n 1 || true; }
FILES=()
f=$(newest "$DIR/db/chaos-db-*.sql.gz"); [ -n "$f" ] && FILES+=("$f")
f=$(newest "$DIR/data/chaos-data-*.tar.gz"); [ -n "$f" ] && FILES+=("$f")
[ ${#FILES[@]} -gt 0 ] || die "no dump in $DIR/db"
SENT="$DIR/.offsite_sent"
touch "$SENT"

TODO=()
for f in "${FILES[@]}"; do
	grep -qxF "$(basename "$f")$SUFFIX" "$SENT" || TODO+=("$f")
done

if [ "$DRY" = 1 ]; then
	log "dry run: encryption $ENC; would send ${TODO[*]:-nothing new}${REMOTE:+ to rclone $REMOTE}${RSYNC_TARGET:+ to $RSYNC_TOOL $RSYNC_TARGET}; keep $KEEP day(s) there"
	exit 0
fi

exec 8>"$DIR/.offsite.lock"
flock -n 8 || die "another off-site copy is running ($DIR/.offsite.lock)"

WORK=$(mktemp -d "$DIR/.offsite-tmp.XXXXXX")
GPGTMP=""
cleanup() {
	if [ -n "$GPGTMP" ]; then gpgconf --homedir "$GPGTMP" --kill gpg-agent >/dev/null 2>&1 || true; rm -rf "$GPGTMP"; fi
	rm -rf "$WORK"
}
trap cleanup EXIT
if [ "$ENC" = gpg-pass ]; then
	# a throwaway keyring for the symmetric mode; a short path, because gpg-agent's socket path has a length limit
	GPGTMP=$(mktemp -d /tmp/chaos-gpg.XXXXXX)
fi

encrypt() {   # encrypt SRC DEST
	case "$ENC" in
		age)
			if [ -f "$AGE_RCPT" ]; then age -R "$AGE_RCPT" -o "$2" "$1"; else age -r "$AGE_RCPT" -o "$2" "$1"; fi ;;
		gpg-key)
			gpg --homedir "$GPG_HOME" --batch --yes --trust-model always -r "$GPG_RCPT" -o "$2" --encrypt "$1" ;;
		gpg-pass)
			gpg --homedir "$GPGTMP" --batch --yes --pinentry-mode loopback --passphrase-file "$PASSFILE" --symmetric --cipher-algo AES256 \
				-o "$2" "$1" ;;
	esac
}

ssh_cmd() {
	local c="ssh -o BatchMode=yes -o ConnectTimeout=20"
	[ -n "$SSH_KEY" ] && c="$c -i $SSH_KEY"
	echo "$c"
}

send() {   # send FILE (already encrypted when it should be); the name on the target is the file's basename
	local f=$1
	if [ -n "$REMOTE" ]; then
		rclone --config "$RCONF" copyto --retries 3 "$f" "$REMOTE/$(basename "$f")"
		log "rclone: $(basename "$f") -> $REMOTE"
	fi
	if [ -n "$RSYNC_TARGET" ]; then
		if [ "$RSYNC_TOOL" = rsync ]; then
			rsync -t --partial --timeout=600 -e "$(ssh_cmd)" "$f" "$RSYNC_TARGET/"
		else
			scp -B -p -o ConnectTimeout=20 ${SSH_KEY:+-i "$SSH_KEY"} "$f" "$RSYNC_TARGET/"
		fi
		log "$RSYNC_TOOL: $(basename "$f") -> $RSYNC_TARGET"
	fi
}

for f in "${TODO[@]}"; do
	out="$f"
	if [ "$ENC" != none ]; then
		out="$WORK/$(basename "$f")$SUFFIX"
		encrypt "$f" "$out" || die "encrypting $f failed"
	fi
	send "$out" || die "sending $(basename "$out") failed"
	basename "$out" >> "$SENT"
done
# the list only needs the recent names
tail -n 200 "$SENT" > "$WORK/sent" && cat "$WORK/sent" > "$SENT"

# retention on the target: chaos-* files older than KEEP days (0: keep everything)
if [ "$KEEP" -gt 0 ]; then
	if [ -n "$REMOTE" ]; then
		rclone --config "$RCONF" delete --min-age "${KEEP}d" --include 'chaos-*' "$REMOTE" \
			|| log "warning: pruning $REMOTE failed"
	fi
	if [ -n "$RSYNC_TARGET" ]; then
		case "$RSYNC_TARGET" in
			*:*)
				host=${RSYNC_TARGET%%:*} path=${RSYNC_TARGET#*:}
				[ -n "$path" ] || path=.
				# shellcheck disable=SC2029
				$(ssh_cmd) "$host" "find '$path' -maxdepth 1 -type f -name 'chaos-*' -mtime +$KEEP -delete" \
					|| log "warning: pruning $RSYNC_TARGET failed (the target needs find; or prune there yourself)" ;;
			*)
				find "$RSYNC_TARGET" -maxdepth 1 -type f -name 'chaos-*' -mtime +"$KEEP" -delete ;;
		esac
	fi
fi

{
	date -Is
	echo "encryption=$ENC remote=${REMOTE:-} rsync=${RSYNC_TARGET:-}"
	for f in "${FILES[@]}"; do basename "$f"; done
} > "$DIR/.offsite_last"
log "done (${#TODO[@]} file(s) sent, encryption $ENC)"
