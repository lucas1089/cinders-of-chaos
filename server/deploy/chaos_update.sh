#!/usr/bin/env bash
# Cinders of Chaos: ship a release to the live game server, or roll the last one back.
# The routine and the reasons: docs/LAUNCH.md "Updating the live server". Run it as root on the game server, in tmux or
# screen (--at-save can wait for hours).
#
# usage: chaos_update.sh --ref TAG (--at-save | --now) [options]       install the release TAG
#        chaos_update.sh --ref TAG --check-only [options]                 checks and the install dry run, then put back
#        chaos_update.sh --rollback (--at-save | --now) [options]         back to the commit before the last update
#
#   --repo DIR          the repository checkout on this machine (default /opt/chaos/repo)
#   --server DIR        the server folder (default /opt/chaos/server)
#   --ref TAG           the release: a tag, fetched from --remote first (default remote origin)
#   --untagged          accept a --ref that is not a tag (a branch or a commit; not for releases)
#   --at-save           wait until the engine stops by itself: the daily server save (serverSaveShutdown), or a
#                       "Restart (countdown)" started in the admin panel. Players get the in-game warnings and nobody
#                       loses progress. systemd's Restart=always is held off meanwhile by a runtime drop-in.
#   --now               systemctl stop at once (the engine saves, then stops): an empty or closed server, a hotfix
#   --engine FILE       a new engine binary built from TAG with every server/src-patches/ patch (docs/LAUNCH.md section 1).
#                       Required when server/src-patches/ changed. Installed as SERVER/tfs; the old one is kept in the
#                       state folder for --rollback.
#   --yes               do not ask before installing
#   --no-backup         --rollback only: skip the backup of the broken state (an emergency; the pre-update one stays)
#   --service UNIT      the game server unit (default chaos-server)
#   --env FILE          the settings (default /etc/chaos/chaos.env: CHAOS_DB_*, CHAOS_BACKUP_DIR)
#   --state-dir DIR     where the deployed commit, the backups of each update and the logs are kept
#                       (default /var/lib/chaos/deploy)
#   --log FILE          the engine console log (default /var/log/chaos/server.log)
#   --status-port PORT  the status protocol port (default 7171)
#   --max-wait HOURS    --at-save gives up after this long (default 25)
#   --boot-timeout SEC  how long to wait for the status protocol after the start (default 900: the map load)
#   --dropin-dir DIR    the runtime unit folder (default /run/systemd/system)
#
# What it does (update): refuses a checkout with uncommitted or untracked files; records the deployed commit; fetches
# the tag; lists what kind of update it is; server/tools/backup.sh first (stops if it fails); checks out the tag; shows
# install_all.py --dry-run; asks; waits for the stop (--at-save) or stops (--now); a database dump of the stopped server;
# the new engine when given; install_all.py; chown to the unit's user; start; then the checks of docs/LAUNCH.md section 9:
# the status protocol answers, no new "Lua Script Error" lines, chaos_health.py --dry-run. Until the install starts, a
# failure puts the checkout back and starts nothing new. Exit status: 0 done, 1 failed, 2 installed and started but a
# check after the start failed (read the log; --rollback if it comes from the update).
# Rollback: the recorded previous commit, the old engine when the update replaced it, and the server's config.lua and
# data/ from the pre-update data archive (the maps, logs and reports are carried over; the replaced folder is kept as
# data.before-rollback-<time>). The database is never restored by this script: it prints the dump and the commands.
# No secrets: the database settings come from --env, and backup.sh / install_all.py hand the password to the mysql
# tools through temporary option files.
set -euo pipefail
umask 022

# run from a copy: the checkout this file lives in changes while it runs
if [ -z "${CHAOS_UPDATE_COPY:-}" ]; then
	copy=$(mktemp "${TMPDIR:-/tmp}/chaos_update.XXXXXX")
	cp "$0" "$copy"
	CHAOS_UPDATE_COPY=$copy CHAOS_UPDATE_SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")" exec bash "$copy" "$@"
fi
SELF=${CHAOS_UPDATE_SELF:-$0}
RESTORE_CHECKOUT=""
DROPIN=""
STOPPED_TIMERS=""

REPO=/opt/chaos/repo
SERVER=/opt/chaos/server
REF=""
UNTAGGED=0
MODE=""
ROLLBACK=0
CHECK_ONLY=0
ENGINE=""
YES=0
NO_BACKUP=0
SERVICE=chaos-server
ENV_FILE=/etc/chaos/chaos.env
STATE_DIR=/var/lib/chaos/deploy
SERVER_LOG=/var/log/chaos/server.log
STATUS_PORT=7171
MAX_WAIT_H=25
BOOT_TIMEOUT=900
DROPIN_DIR=/run/systemd/system
REMOTE=origin
TIMERS="chaos-health.timer chaos-watchdog.timer chaos-backup.timer"

die() { echo "chaos_update: $*" >&2; exit 1; }
log() { echo "[$(date '+%F %T')] $*"; }
usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; }
# shellcheck disable=SC2317 # run by the EXIT trap
cleanup() {
	local status=$?
	if [ -n "$DROPIN" ] && [ -f "$DROPIN" ]; then
		rm -f "$DROPIN" && systemctl daemon-reload || true
		log "removed the drop-in $DROPIN (Restart=always again)"
	fi
	if [ -n "$RESTORE_CHECKOUT" ]; then
		g checkout --quiet --detach "$RESTORE_CHECKOUT" && log "checkout put back to $(describe "$RESTORE_CHECKOUT")" || true
	fi
	for t in $STOPPED_TIMERS; do systemctl start "$t" || true; done
	rm -f "$CHAOS_UPDATE_COPY"
	[ -z "$STOPPED_TIMERS" ] || log "timers started again: $STOPPED_TIMERS"
	exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

while [ $# -gt 0 ]; do
	case "$1" in
		--repo) REPO=${2:?}; shift 2 ;;
		--server) SERVER=${2:?}; shift 2 ;;
		--ref) REF=${2:?}; shift 2 ;;
		--remote) REMOTE=${2:?}; shift 2 ;;
		--untagged) UNTAGGED=1; shift ;;
		--at-save) MODE=save; shift ;;
		--now) MODE=now; shift ;;
		--rollback) ROLLBACK=1; shift ;;
		--check-only) CHECK_ONLY=1; shift ;;
		--engine) ENGINE=${2:?}; shift 2 ;;
		--yes) YES=1; shift ;;
		--no-backup) NO_BACKUP=1; shift ;;
		--service) SERVICE=${2:?}; shift 2 ;;
		--env) ENV_FILE=${2:?}; shift 2 ;;
		--state-dir) STATE_DIR=${2:?}; shift 2 ;;
		--log) SERVER_LOG=${2:?}; shift 2 ;;
		--status-port) STATUS_PORT=${2:?}; shift 2 ;;
		--max-wait) MAX_WAIT_H=${2:?}; shift 2 ;;
		--boot-timeout) BOOT_TIMEOUT=${2:?}; shift 2 ;;
		--dropin-dir) DROPIN_DIR=${2:?}; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		*) die "unknown option $1 (see --help)" ;;
	esac
done

# ------------------------------------------------------------------------------------------------ checks
if [ "$ROLLBACK" = 1 ]; then
	[ -z "$REF" ] || die "--rollback takes no --ref: it goes back to the recorded previous commit"
	[ "$CHECK_ONLY" = 0 ] || die "--check-only is for an update"
else
	[ -n "$REF" ] || die "--ref TAG is required (or --rollback; see --help)"
	[ "$NO_BACKUP" = 0 ] || die "--no-backup is for --rollback only: an update always backs up first"
fi
if [ "$CHECK_ONLY" = 0 ]; then
	[ -n "$MODE" ] || die "say when: --at-save (at the daily save or an in-game countdown) or --now (stop at once)"
fi
[[ "$MAX_WAIT_H" =~ ^[0-9]+$ ]] || die "--max-wait must be a whole number of hours"
[[ "$BOOT_TIMEOUT" =~ ^[0-9]+$ ]] || die "--boot-timeout must be a number of seconds"
[[ "$STATUS_PORT" =~ ^[0-9]+$ ]] || die "--status-port must be a number"
REPO=$(cd "$REPO" 2>/dev/null && pwd) || die "no repository checkout at --repo"
SERVER=$(cd "$SERVER" 2>/dev/null && pwd) || die "no server folder at --server"
[ -f "$SERVER/config.lua" ] && [ -d "$SERVER/data" ] || die "$SERVER is not a server folder (config.lua, data/)"
if [ -n "$ENGINE" ]; then
	[ "$ROLLBACK" = 0 ] || die "--engine is for an update (a rollback puts back the engine the update replaced)"
	[ -f "$ENGINE" ] && [ -x "$ENGINE" ] || die "--engine $ENGINE is not an executable file"
	ENGINE=$(cd "$(dirname "$ENGINE")" && pwd)/$(basename "$ENGINE")
fi
for tool in git python3 systemctl flock tar; do
	command -v "$tool" >/dev/null || die "$tool not found"
done

g() { git -C "$REPO" -c safe.directory="$REPO" "$@"; }
g rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "$REPO is not a git checkout"

if [ -r "$ENV_FILE" ]; then
	set -a
	# shellcheck disable=SC1090
	. "$ENV_FILE"
	set +a
else
	log "note: $ENV_FILE not readable; the database settings come from config.lua (install_all.py) and the environment"
fi
BACKUP_DIR=${CHAOS_BACKUP_DIR:-/var/backups/chaos}

mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"
exec 8>"$STATE_DIR/.lock"
flock -n 8 || die "another chaos_update.sh is running ($STATE_DIR/.lock)"
STAMP=$(date '+%Y%m%d-%H%M%S')
RUNLOG="$STATE_DIR/update-$STAMP.log"
exec > >(tee -a "$RUNLOG") 2>&1
log "chaos_update.sh $([ "$ROLLBACK" = 1 ] && echo rollback || echo "update to $REF")${MODE:+ ($MODE)}; this log: $RUNLOG"

STATE="$STATE_DIR/state"
state_get() { [ -f "$STATE" ] && sed -n "s/^$1=//p" "$STATE" | tail -n 1 || true; }
state_write() {
	# key=value pairs; the file is rewritten whole
	local tmp="$STATE.tmp"
	: > "$tmp"
	while [ $# -gt 0 ]; do echo "$1" >> "$tmp"; shift; done
	mv "$tmp" "$STATE"
	echo "$(date '+%F %T') $(tr '\n' ' ' < "$STATE")" >> "$STATE_DIR/history.log"
}
short() { g rev-parse --short "$1" 2>/dev/null || echo "$1"; }
describe() { g describe --tags --always "$1" 2>/dev/null || echo "$1"; }

dirty=$(g status --porcelain --untracked-files=all)
if [ -n "$dirty" ]; then
	echo "$dirty" | head -n 20
	die "the checkout $REPO has uncommitted or untracked files (above). The live server runs a release as it is in git: commit them elsewhere, or remove them (git stash / git clean) after checking what they are"
fi

HEAD=$(g rev-parse HEAD)
DEPLOYED=$(state_get deployed)
if [ -z "$DEPLOYED" ]; then
	DEPLOYED=$HEAD
	log "no deployed commit recorded yet ($STATE): taking the checkout's $(describe "$HEAD") as the one installed"
elif ! g cat-file -e "$DEPLOYED^{commit}" 2>/dev/null; then
	die "the recorded deployed commit $DEPLOYED is not in $REPO (fetch it, or fix $STATE)"
fi
[ "$HEAD" = "$DEPLOYED" ] || log "note: the checkout is at $(describe "$HEAD"), the recorded deployed commit is $(describe "$DEPLOYED")"

ask() {
	[ "$YES" = 1 ] && return 0
	local answer
	printf '%s [type yes] ' "$1"
	read -r answer || answer=""
	[ "$answer" = yes ] || die "stopped: nothing was installed"
}

# ------------------------------------------------------------------------------------------------ the steps both modes use

run_backup() {
	# server/tools/backup.sh of the checkout as it is now: SIGUSR1 save, dump, data archive when it changed
	log "backup: $REPO/server/tools/backup.sh $*"
	"$REPO/server/tools/backup.sh" "$@" || return 1
}
# shellcheck disable=SC2086,SC2012 # $1 is a glob on purpose; the backup names are plain
newest() { ls -1t $1 2>/dev/null | head -n 1 || true; }

stop_timers() {
	local t
	for t in $TIMERS; do
		if systemctl is-active --quiet "$t"; then
			systemctl stop "$t" && STOPPED_TIMERS="$STOPPED_TIMERS $t"
		fi
	done
	[ -z "$STOPPED_TIMERS" ] || log "timers held while the server is down:$STOPPED_TIMERS"
}

start_timers() {
	local t
	for t in $STOPPED_TIMERS; do systemctl start "$t" || true; done
	[ -z "$STOPPED_TIMERS" ] || log "timers started again:$STOPPED_TIMERS"
	STOPPED_TIMERS=""
}

# the engine goes down: at once, or by itself (daily save / admin panel countdown) with systemd's restart held off
stop_server() {
	if ! systemctl is-active --quiet "$SERVICE"; then
		log "$SERVICE is not running"
		return 0
	fi
	if [ "$MODE" = now ]; then
		log "stopping $SERVICE (the engine saves every player first; up to 3 minutes)"
		systemctl stop "$SERVICE"
		return 0
	fi
	DROPIN="$DROPIN_DIR/$SERVICE.service.d/50-chaos-update.conf"
	mkdir -p "$(dirname "$DROPIN")"
	printf '# chaos_update.sh: the next stop is the update; removed when it ends. If the script died, delete this file\n# and run systemctl daemon-reload, or the server stays down after the next daily save.\n[Service]\nRestart=no\n' > "$DROPIN"
	systemctl daemon-reload
	log "waiting for $SERVICE to stop by itself: the daily server save, or start the warning now in game:"
	log "  admin panel (opcode 120) > Server > Restart (countdown), minutes and a reason such as \"update\""
	log "  (gives up after $MAX_WAIT_H h; Ctrl-C puts everything back)"
	local deadline=$(( $(date +%s) + MAX_WAIT_H * 3600 ))
	while systemctl is-active --quiet "$SERVICE"; do
		[ "$(date +%s)" -lt "$deadline" ] || die "$SERVICE did not stop within $MAX_WAIT_H h: nothing installed"
		sleep 10
	done
	local result
	result=$(systemctl show -p Result --value "$SERVICE" 2>/dev/null || echo unknown)
	rm -f "$DROPIN" && systemctl daemon-reload
	DROPIN=""
	if [ "$result" != success ]; then
		systemctl start "$SERVICE" || true
		die "$SERVICE stopped with result '$result' (a crash, not the save): started again on the old release, nothing installed. Read /var/log/chaos/crashes/ first"
	fi
	log "$SERVICE stopped cleanly"
}

# the unit runs the game server as root when it has no User= (systemd's default): the engine warns about it in its log
warn_root_unit() {
	local u
	u=$(systemctl show -p User --value "$SERVICE" 2>/dev/null || true)
	case $u in ''|0|root)
		log "WARNING: the unit $SERVICE runs the game server as root (the engine says so in its log). The update goes on; fix it with the admin app, Comandos > Saúde e espaço > Servidor como usuário chaos > Corrigir (chaos-ctl.sh server-user fix, docs/OWNER_TODO.md)" ;;
	esac
}

own_server() {
	local user group
	user=$(systemctl show -p User --value "$SERVICE" 2>/dev/null || true)
	group=$(systemctl show -p Group --value "$SERVICE" 2>/dev/null || true)
	if [ -n "$user" ]; then
		chown -R "$user:${group:-$user}" "$SERVER"
		log "ownership of $SERVER set to $user:${group:-$user}"
	fi
}

log_size() { stat -c %s "$SERVER_LOG" 2>/dev/null || echo 0; }

# docs/LAUNCH.md section 9, "After every restart and update"
after_start_checks() {
	local from=$1 bad=0 waited=0 errors
	log "waiting for the status protocol on 127.0.0.1:$STATUS_PORT (the map load takes a few minutes; at most ${BOOT_TIMEOUT}s)"
	until python3 -I -B -c 'import sys; sys.path.insert(0, sys.argv[1]); import chaos_watchdog as w
sys.exit(0 if w.ask_status("127.0.0.1", int(sys.argv[2]), 10) else 1)' "$REPO/server/tools" "$STATUS_PORT"; do
		if ! systemctl is-active --quiet "$SERVICE"; then
			log "FAIL: $SERVICE is not running (systemctl status $SERVICE; tail -n 100 $SERVER_LOG)"
			return 1
		fi
		if [ "$waited" -ge "$BOOT_TIMEOUT" ]; then
			log "FAIL: no status answer after ${BOOT_TIMEOUT}s (tail -n 100 $SERVER_LOG)"
			return 1
		fi
		sleep 10
		waited=$((waited + 10))
	done
	log "ok: the status protocol answers"
	if [ -f "$SERVER_LOG" ]; then
		[ "$(log_size)" -ge "$from" ] || from=0 # rotated meanwhile
		errors=$(tail -c +"$((from + 1))" "$SERVER_LOG" | grep -c 'Lua Script Error' || true)
		if [ "$errors" -gt 0 ]; then
			log "WARN: $errors new 'Lua Script Error' line(s) since the start:"
			tail -c +"$((from + 1))" "$SERVER_LOG" | grep -A 3 'Lua Script Error' | head -n 40
			log "compare with the known base server noise of the first-start log; errors from this update: --rollback"
			bad=1
		else
			log "ok: no 'Lua Script Error' since the start"
		fi
	else
		log "note: no $SERVER_LOG to read"
	fi
	if [ -f "$REPO/server/tools/chaos_health.py" ]; then
		log "chaos_health.py --dry-run (the game checks are skipped in the first 5 minutes after a start):"
		python3 -I "$REPO/server/tools/chaos_health.py" --dry-run || bad=1
	fi
	if systemctl is-active --quiet chaos-watchdog.timer 2>/dev/null; then
		log "ok: chaos-watchdog.timer is active"
	else
		log "note: chaos-watchdog.timer is not active (docs/LAUNCH.md section 5)"
	fi
	return "$bad"
}

# ------------------------------------------------------------------------------------------------ rollback
if [ "$ROLLBACK" = 1 ]; then
	PREV=$(state_get previous)
	[ -n "$PREV" ] || die "nothing recorded to roll back to ($STATE has no previous commit; a rollback already ran, or no update was made with this script). By hand: docs/LAUNCH.md \"Incident runbook\""
	g cat-file -e "$PREV^{commit}" 2>/dev/null || die "the previous commit $PREV is not in $REPO"
	TARGET=$(state_get target)
	ARCHIVE=$(state_get data_archive)
	FINAL_DUMP=$(state_get final_dump)
	ENGINE_BACKUP=$(state_get engine_backup)
	log "rollback: from $(describe "${TARGET:-$HEAD}") (status $(state_get status)) to $(describe "$PREV")"
	log "  server data from: ${ARCHIVE:-none recorded (install_all.py of the old release instead)}"
	[ -z "$ENGINE_BACKUP" ] || log "  engine from: $ENGINE_BACKUP"
	if [ -n "$ARCHIVE" ] && [ ! -f "$ARCHIVE" ]; then die "the recorded data archive $ARCHIVE is gone"; fi
	if [ -n "$ENGINE_BACKUP" ] && [ ! -f "$ENGINE_BACKUP" ]; then die "the recorded old engine $ENGINE_BACKUP is gone"; fi
	if [ "$NO_BACKUP" = 0 ]; then
		run_backup --save-service "$SERVICE" --server-dir "$SERVER" || die "backup failed: nothing changed (--no-backup to go on without it)"
	fi
	ask "Roll back to $(describe "$PREV") now?"
	stop_server
	stop_timers
	g checkout --quiet --detach "$PREV"
	log "checkout at $(describe "$PREV")"
	if [ -n "$ENGINE_BACKUP" ]; then
		install -m 0755 "$ENGINE_BACKUP" "$SERVER/tfs"
		log "engine put back from $ENGINE_BACKUP"
	fi
	if [ -n "$ARCHIVE" ]; then
		ASIDE="$SERVER/data.before-rollback-$STAMP"
		mv "$SERVER/data" "$ASIDE"
		cp -p "$SERVER/config.lua" "$SERVER/config.lua.before-rollback-$STAMP"
		if ! tar -C "$SERVER" -xzf "$ARCHIVE" config.lua data; then
			rm -rf "$SERVER/data"
			mv "$ASIDE" "$SERVER/data"
			cp -p "$SERVER/config.lua.before-rollback-$STAMP" "$SERVER/config.lua"
			die "could not unpack $ARCHIVE: the server folder is as it was, the server is down. docs/LAUNCH.md \"Incident runbook\""
		fi
		# the archive leaves out the maps, logs and reports: carry them over from the replaced folder
		(cd "$ASIDE" && find . -name '*.otbm' -type f -print0) | while IFS= read -r -d '' f; do
			mkdir -p "$SERVER/data/$(dirname "$f")"
			mv "$ASIDE/$f" "$SERVER/data/$f"
		done
		for d in logs reports; do
			if [ -d "$ASIDE/$d" ]; then
				rm -rf "${SERVER:?}/data/$d"
				mv "$ASIDE/$d" "$SERVER/data/$d"
			fi
		done
		log "config.lua and data/ restored from $ARCHIVE (maps, logs and reports carried over); the replaced folder: $ASIDE"
	else
		log "no data archive recorded: running install_all.py of $(describe "$PREV") (files the update added stay in data/)"
		python3 -I "$REPO/server/tools/install_all.py" "$SERVER" || die "install_all.py failed: the server is down; fix it and start $SERVICE"
	fi
	own_server
	FROM=$(log_size)
	systemctl start "$SERVICE"
	start_timers
	state_write "deployed=$PREV" "previous=" "target=$TARGET" "status=rolled-back" "time=$(date '+%F %T')"
	log "started $SERVICE on $(describe "$PREV")"
	CHECKS=0
	after_start_checks "$FROM" || CHECKS=2
	cat <<EOF

The database was not touched. Restore it only when the update damaged data (bad saves, a migration of server/sql/ the
old release cannot read); that loses everything played since the dump. The dump of the stopped server right before
the update: ${FINAL_DUMP:-none recorded}
  docs/LAUNCH.md "Incident runbook", "Rollback to the last backup", with DUMP=${FINAL_DUMP:-<the dump>}
Players: say on Discord and in game what was rolled back. Write no patch note for a release that is not live.
EOF
	exit "$CHECKS"
fi

# ------------------------------------------------------------------------------------------------ update
if g remote get-url "$REMOTE" >/dev/null 2>&1; then
	log "fetching tags from $REMOTE"
	g fetch --quiet --tags "$REMOTE" || die "git fetch from $REMOTE failed (a tag that moved upstream is refused on purpose)"
else
	log "note: no remote $REMOTE in $REPO: using the refs already there"
fi
if [ "$UNTAGGED" = 0 ]; then
	g show-ref --verify --quiet "refs/tags/$REF" || die "$REF is not a tag. Releases are tagged commits (--untagged for a test)"
fi
NEW=$(g rev-parse --verify --quiet "$REF^{commit}") || die "$REF is not in $REPO"

if [ "$(state_get status)" = installing ]; then
	die "the last update ($(describe "$(state_get target)")) stopped during the install: go back first ($SELF --rollback --now), or finish it by hand (install_all.py, then start $SERVICE) and fix $STATE"
fi
if [ "$NEW" = "$DEPLOYED" ]; then
	log "$REF ($(short "$NEW")) is already the deployed release: nothing to do"
	[ "$HEAD" = "$NEW" ] || log "note: the checkout is at $(describe "$HEAD"): git -C $REPO checkout --detach $REF"
	exit 0
fi

CHANGED=$(g diff --name-only "$DEPLOYED" "$NEW")
has() { echo "$CHANGED" | grep -q "$1"; }
warn_root_unit
echo
log "update: $(describe "$DEPLOYED") -> $REF ($(short "$NEW")), $(echo "$CHANGED" | grep -c . || true) file(s) changed"
g log --oneline --no-decorate "$DEPLOYED..$NEW" | head -n 30
echo "Kinds of change (docs/LAUNCH.md \"Updating the live server\"):"
has '^server/data/\|^server/tools/' && echo "  - server Lua and data: install_all.py and a restart"
if has '^server/src-patches/'; then
	echo "  - ENGINE: server/src-patches/ changed; the engine must be rebuilt from $REF (--engine)"
	[ -n "$ENGINE" ] || die "server/src-patches/ changed between the deployed commit and $REF: build the engine of $REF (docs/LAUNCH.md section 1) and pass it with --engine FILE"
fi
[ -z "$ENGINE" ] || echo "  - engine binary to install: $ENGINE"
has '^server/sql/' && echo "  - database: server/sql/ changed (the sql step applies it; a rollback does not undo it)"
has '^server/deploy/.*\.\(service\|timer\)$\|^server/deploy/chaos.logrotate$' &&
	echo "  - systemd units or logrotate changed: copy them again after the update (docs/LAUNCH.md section 5)"
has '^client/overlay/' && echo "  - client files: publish a signed client update from your own machine afterwards"
has '^client/base-patches/' && echo "  - client exe: a new Windows package and an update with --min-package"
has '^website/' && echo "  - website: deploy it on its own (docs/LAUNCH.md \"Website\")"
has '^server/data/patchnotes/' && echo "  - a patch note for players is included" ||
	echo "  - no new patch note in server/data/patchnotes/: players see no note for this update"

if [ "$CHECK_ONLY" = 0 ]; then
	run_backup --save-service "$SERVICE" --server-dir "$SERVER" || die "backup failed: nothing changed"
	DB_DUMP=$(newest "$BACKUP_DIR/db/chaos-db-*.sql.gz")
	ARCHIVE=$(newest "$BACKUP_DIR/data/chaos-data-*.tar.gz")
	[ -n "$ARCHIVE" ] || die "no data archive in $BACKUP_DIR/data after the backup: is CHAOS_BACKUP_DIR right?"
	log "pre-update backup: ${DB_DUMP:-?} and $ARCHIVE"
fi

RESTORE_CHECKOUT=$HEAD
g checkout --quiet --detach "$NEW"
log "checkout at $REF ($(short "$NEW"))"
log "install_all.py --dry-run (on a temporary copy; nothing changes):"
python3 -I "$REPO/server/tools/install_all.py" "$SERVER" --dry-run || die "the dry run failed: nothing installed"

if [ "$CHECK_ONLY" = 1 ]; then
	log "check only: the checkout goes back, nothing else changed"
	exit 0
fi

ask "Install $REF on $SERVER ($([ "$MODE" = now ] && echo "stop now" || echo "at the next stop: daily save or admin panel countdown"))?"
# the Rust login-screen services (server/README.md "Rust services (O153)"), only when the owner switched them on
# (chaos-ctl.sh clientservices-impl rust): build the new checkout's version while the game is still up; the old
# binary stays if the build fails
CSDROP="${CHAOS_SYSTEMD_DIR:-/etc/systemd/system}/chaos-clientservices.service.d/10-rust.conf"
if [ -f "$CSDROP" ]; then
	CSBIN="$(dirname "$SERVER")/bin/clientservices-rs"
	log "Rust login-screen services are switched on: building $CSBIN"
	if bash "$REPO/server/services/clientservices-rs/build.sh" "$CSBIN"; then
		systemctl restart chaos-clientservices || log "warning: chaos-clientservices did not restart"
	else
		log "warning: the Rust build failed; the previous binary keeps running (chaos-ctl.sh clientservices-impl python goes back)"
	fi
fi
stop_server
stop_timers
FINAL_DUMP=""
if ! run_backup --no-data; then
	systemctl start "$SERVICE" || true
	die "the dump of the stopped server failed: started again on the old release, nothing installed"
fi
FINAL_DUMP=$(newest "$BACKUP_DIR/db/chaos-db-*.sql.gz")

ENGINE_BACKUP=""
if [ -n "$ENGINE" ] && [ -f "$SERVER/tfs" ]; then
	ENGINE_BACKUP="$STATE_DIR/engine-$(short "$DEPLOYED")-$STAMP"
	cp -p "$SERVER/tfs" "$ENGINE_BACKUP"
fi
state_write "deployed=$DEPLOYED" "previous=$DEPLOYED" "target=$NEW" "status=installing" "data_archive=$ARCHIVE" \
	"db_dump=$DB_DUMP" "final_dump=$FINAL_DUMP" "engine_backup=$ENGINE_BACKUP" "time=$(date '+%F %T')"
RESTORE_CHECKOUT="" # from here on the way back is --rollback
if [ -n "$ENGINE" ]; then
	install -m 0755 "$ENGINE" "$SERVER/tfs"
	log "engine installed from $ENGINE (old one: ${ENGINE_BACKUP:-none})"
fi
log "install_all.py:"
if ! python3 -I "$REPO/server/tools/install_all.py" "$SERVER"; then
	die "install_all.py failed: $SERVICE stays down. Either fix and run install_all.py again, or go back: $SELF --rollback --now"
fi
own_server
FROM=$(log_size)
systemctl start "$SERVICE"
start_timers
state_write "deployed=$NEW" "previous=$DEPLOYED" "target=$NEW" "status=deployed" "data_archive=$ARCHIVE" \
	"db_dump=$DB_DUMP" "final_dump=$FINAL_DUMP" "engine_backup=$ENGINE_BACKUP" "time=$(date '+%F %T')"
log "started $SERVICE on $REF ($(short "$NEW"))"
CHECKS=0
after_start_checks "$FROM" || CHECKS=2
cat <<EOF

Next (docs/LAUNCH.md "Updating the live server"):
- log in with a staff character and try what the update changed;
- a bad update: $SELF --rollback --now (or --at-save), then read what it prints about the database;
- the patch note: only about what is live now (it shows within a minute, or /patchnotes reload);
- client files changed: publish the signed client update from your own machine, never from this server.
EOF
exit "$CHECKS"
