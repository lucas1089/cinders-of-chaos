#!/usr/bin/env bash
# Cinders of Chaos: one command for the live server, for the admin app (android/) and for you over ssh.
# The routine: docs/ADMIN_APP.md. Layout assumed: docs/LAUNCH.md (systemd unit chaos-server, /opt/chaos, /etc/chaos/chaos.env).
#
# usage: chaos-ctl.sh COMMAND [args]       (as root, or as a user that may sudo it: it asks sudo -n itself)
#
#   status                      key=value lines: unit, unit_state, service, since, pid, players, load, mem, disk,
#                               backup, errors (error lines since the last server start)
#   start | stop | save         systemctl start / stop (the engine saves first) / SIGUSR1 (save without stopping)
#   restart [SECONDS]           at once, or after a countdown: players are told, then restart (runs in the background)
#   backup                      server/tools/backup.sh with a save first
#   logs [N]                    the last N (default 60, at most 500) lines of the engine console
#   errors [N] [all]            error lines since the last server start, identical ones counted once ("56x ...");
#                               a Lua error with its next two lines (script, message). One "@run DATE [current]" line
#                               per server start (DATE "unknown" when the log has none), at most N (40) entries per run.
#                               all: every start in the last 20000 log lines; else "@older K" says how many earlier
#                               starts had errors
#   players                     online characters: name, level, class name (tab separated)
#   vocations                   id=class name, one per line
#   broadcast TEXT              a message to everyone online     (remote.cmd, server/README.md "Remote admin commands")
#   kick NAME | open | close    kick one character / let players log in / close the server for login
#   catalog ACTOR               the admin panel's catalog (all actions and their parameters) for the admin character ACTOR
#   panel ACTOR ACTION JSON     run one admin panel action as ACTOR (an admin character, online or not); prints the answer line (JSON)
#   update TAG now|at-save      chaos_update.sh --ref TAG (--now | --at-save) --yes, in the background (update-log)
#   rollback now|at-save        chaos_update.sh --rollback, in the background
#   update-log [N]              the last N lines of the update log
#   update-check                the Linux kit (CHAOS_KIT_DIR): what an update would bring, key=value lines (commits behind
#                               with their subjects, installed and newest winpkg-N release, client update, downloads, site)
#   update-apply [--no-client] [--no-downloads] [--no-site]
#                               the kit: chaos_kit_update.sh apply in the background (update-log): the branch
#                               CHAOS_UPDATE_BRANCH, the newest release's engine, install_all.py, restart, checks, rollback
#                               on failure; then the client update, the site's download files and the site itself
#   update-status               the kit: running, status, result and time of the last update-apply / update-rollback
#   update-rollback             the kit: chaos_kit_update.sh rollback in the background (update-log)
#   xp-rate [show | set N | reset] [restart]
#                               the XP multiplier of config.lua (experienceStages = the release's stages x N, N 1..100);
#                               set / reset keep a backup and apply at the next restart, or at once with "restart".
#                               update-apply keeps it.
#   backups                     the newest database dumps and data archives (date, size, path)
#   site-install                website/install_site.sh CHAOS_ENV CHAOS_SITE_ENV in the background (site-log)
#   site-log [N]                the last N lines of the site install log
#   health                      key=value lines: the unit, the engine, the database, the web server units, disk,
#                               memory and what "cleanup" would remove
#   cleanup [--yes]             lists (or with --yes removes) leftovers: old work folders of updates and publishes in
#                               CHAOS_WORK_DIR (a day old), srvNN folders there, engine backups tfs.antes-* beyond the
#                               newest 2, config.lua.before-* beyond the newest 5
#   gm-logs [N] [PLAYER]        staff logs: "@staff" (names with a log), "@files" (SERVER/data/logs), "@commands PLAYER"
#                               (the newest N lines of the base server's "<PLAYER> commands.log", newest first) and
#                               "@panel" (the newest N rows of the admin panel's audit table chaos_admin_log, all staff
#                               or PLAYER's)
#   account-create NAME         a game account; the password is read from stdin (one line, 6-64 characters), stored
#                               as a PBKDF2 hash (never on a command line or in a log)
#   account-password NAME       a new password for an account, read from stdin the same way
#   publish-update TAG [--version N] [--min-package N]
#                               publish_client_update.sh TAG in the background (publish-log): the release's client zip
#                               becomes the signed client update on the site (docs/LAUNCH.md "Publishing a client
#                               update"). Release tags only, never a local file.
#   publish-log [N]             the last N lines of the publish log
#   install-admin [--full] KEYFILE|-
#                               creates the user "chaosadmin" with that ssh public key (a file, or - for stdin) and the
#                               right to run this script as root; --full also gives it passwordless sudo for everything
#
# Settings, defaults for the standard layout: CHAOS_UNIT chaos-server, CHAOS_ROOT /opt/chaos,
# CHAOS_SERVER_DIR $CHAOS_ROOT/server, CHAOS_REPO $CHAOS_ROOT/repo, CHAOS_ENV /etc/chaos/chaos.env,
# CHAOS_LOG /var/log/chaos/server.log, CHAOS_UPDATE_LOG /var/log/chaos/update.log, CHAOS_ADMIN_USER chaosadmin,
# CHAOS_PID_FILE $CHAOS_ROOT/run/server.pid (the engine's pid, written by the Linux kit's start-server.sh),
# CHAOS_DB_SOCKET (empty: TCP host/port of the env file), CHAOS_MYSQL (the client: mysql, mariadb or the kit's own),
# CHAOS_BACKUP_DIR (else the env file's, else /var/backups/chaos). For publish-update: CHAOS_PUBLISH_LOG
# /var/log/chaos/publish-update.log and, passed on to publish_client_update.sh (its defaults when unset), CHAOS_SITE_DIR,
# CHAOS_UPDATE_KEY, CHAOS_UPDATE_PUBLIC, CHAOS_UPDATE_REPO, CHAOS_UPDATE_URL, CHAOS_WORK_DIR, and CHAOS_ENV (the update blobs are
# encrypted with its CHAOS_CLIENT_KEY, which publish_client_update.sh reads from there). For the kit's update-*:
# CHAOS_KIT_DIR (else CHAOS_ROOT when it holds start-server.sh), CHAOS_UPDATE_BRANCH main, CHAOS_RELEASE_REPO
# lucas1089/cinders-of-chaos, CHAOS_KIT_STATE /var/lib/chaos/kit-update, CHAOS_BOOT_TIMEOUT 900, CHAOS_DL_DIR
# $CHAOS_SITE_DIR/dl, CHAOS_SITE_ENV /etc/chaos/site.env; CHAOS_SITE_LOG /var/log/chaos/site-install.log.
# They come from /etc/chaos/ctl.conf (server/deploy/ctl.conf.example): simple KEY=VALUE lines, only those keys, read
# only when the file is owned by root (or by the user running the script) and not writable by group or others. It is
# never sourced. The environment wins over the file, but sudo drops the environment, so the app (which runs this through
# sudo -n) only ever sees the file. CHAOS_CTL_CONF names another file, honoured only outside sudo.
# shellcheck source=/dev/null
set -uo pipefail

SELF=$(readlink -f "$0")

die() { echo "chaos-ctl: $*" >&2; exit 1; }

# root is needed for systemctl, the log and the database password; a user in sudoers for this script gets it by sudo -n
if [ "$(id -u)" -ne 0 ] && [ -z "${CHAOS_CTL_NO_SUDO:-}" ]; then
  exec sudo -n "$SELF" "$@"
fi

CONF=/etc/chaos/ctl.conf
[ -z "${SUDO_USER:-}" ] && [ -n "${CHAOS_CTL_CONF:-}" ] && CONF=$CHAOS_CTL_CONF
CONF_KEYS=" CHAOS_UNIT CHAOS_ROOT CHAOS_SERVER_DIR CHAOS_REPO CHAOS_ENV CHAOS_LOG CHAOS_UPDATE_LOG CHAOS_ADMIN_USER \
CHAOS_PID_FILE CHAOS_DB_SOCKET CHAOS_MYSQL CHAOS_BACKUP_DIR CHAOS_PUBLISH_LOG CHAOS_SITE_DIR CHAOS_UPDATE_KEY \
CHAOS_UPDATE_PUBLIC CHAOS_UPDATE_REPO CHAOS_UPDATE_URL CHAOS_WORK_DIR CHAOS_KIT_DIR CHAOS_UPDATE_BRANCH \
CHAOS_RELEASE_REPO CHAOS_KIT_STATE CHAOS_BOOT_TIMEOUT CHAOS_DL_DIR CHAOS_SITE_ENV CHAOS_SITE_LOG "
declare -A CFG=()
# KEY=VALUE, optional "" or '' around the value, # comments; a value is a path or a unit name (no spaces, no $ or `)
read_conf() {
  local f=$1 meta n=0 line key val
  [ -e "$f" ] || return 0
  if [ ! -f "$f" ] || [ -L "$f" ]; then echo "chaos-ctl: warning: $f is not a plain file, ignored" >&2; return 0; fi
  meta=$(stat -c '%u %a' "$f" 2>/dev/null) || return 0
  local owner=${meta% *} mode=${meta#* }
  if [ "$owner" != 0 ] && [ "$owner" != "$(id -u)" ]; then
    echo "chaos-ctl: warning: $f is not owned by root, ignored" >&2; return 0
  fi
  if (( (8#$mode & 8#022) != 0 )); then
    echo "chaos-ctl: warning: $f is writable by group or others (chmod 644), ignored" >&2; return 0
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    line=${line%$'\r'}
    [[ $line =~ ^[[:space:]]*(#.*)?$ ]] && continue
    if [[ $line =~ ^[[:space:]]*([A-Z_]+)=(.*)$ ]]; then
      key=${BASH_REMATCH[1]}
      val=${BASH_REMATCH[2]}
      val=${val%"${val##*[![:space:]]}"}
      if [[ $val =~ ^\"(.*)\"$ ]] || [[ $val =~ ^\'(.*)\'$ ]]; then val=${BASH_REMATCH[1]}; fi
      if [[ $CONF_KEYS == *" $key "* ]] && [[ $val =~ ^[A-Za-z0-9._/@:+-]*$ ]]; then
        CFG[$key]=$val
        continue
      fi
    fi
    echo "chaos-ctl: warning: $f line $n ignored (unknown key or unsafe value)" >&2
  done < "$f"
}
read_conf "$CONF"
# the environment first, then the file, then the default
setting() { local v=${!1:-}; [ -n "$v" ] || v=${CFG[$1]:-}; printf '%s' "${v:-$2}"; }

UNIT=$(setting CHAOS_UNIT chaos-server)
# the Linux kit: CHAOS_KIT_DIR is also the root (server/, chaos.env, logs/, run/) unless those are set themselves
KIT=$(setting CHAOS_KIT_DIR "")
ROOT=$(setting CHAOS_ROOT "${KIT:-/opt/chaos}")
[ -z "$KIT" ] && [ -x "$ROOT/start-server.sh" ] && KIT=$ROOT
SERVER=$(setting CHAOS_SERVER_DIR "$ROOT/server")
REPO=$(setting CHAOS_REPO "$ROOT/repo")
if [ -n "$KIT" ]; then
  ENVFILE=$(setting CHAOS_ENV "$KIT/chaos.env")
  LOG=$(setting CHAOS_LOG "$KIT/logs/server.log")
else
  ENVFILE=$(setting CHAOS_ENV /etc/chaos/chaos.env)
  LOG=$(setting CHAOS_LOG /var/log/chaos/server.log)
fi
ULOG=$(setting CHAOS_UPDATE_LOG /var/log/chaos/update.log)
ADMIN=$(setting CHAOS_ADMIN_USER chaosadmin)
PIDFILE=$(setting CHAOS_PID_FILE "$ROOT/run/server.pid")
DBSOCK=$(setting CHAOS_DB_SOCKET "")
MYSQL=$(setting CHAOS_MYSQL "")
BACKUPDIR=$(setting CHAOS_BACKUP_DIR "")
PLOG=$(setting CHAOS_PUBLISH_LOG /var/log/chaos/publish-update.log)
SITELOG=$(setting CHAOS_SITE_LOG /var/log/chaos/site-install.log)
KSTATE=$(setting CHAOS_KIT_STATE /var/lib/chaos/kit-update)
WORKDIR=$(setting CHAOS_WORK_DIR /var/tmp)
if [ -z "$MYSQL" ]; then
  for c in mysql mariadb "$ROOT/mariadb/bin/mariadb"; do
    command -v "$c" >/dev/null 2>&1 && { MYSQL=$c; break; }
  done
  MYSQL=${MYSQL:-mysql}
fi

# the unit's state as systemd knows it: loaded, not-found (no such unit: CHAOS_UNIT names another one), masked, ...
unit_state() { systemctl show "$UNIT" -p LoadState --value 2>/dev/null || echo unknown; }
need_unit() {
  local st
  st=$(unit_state)
  if [ "$st" = not-found ]; then
    echo "chaos-ctl: unit-not-found: the systemd unit $UNIT does not exist on this machine. Install it" \
      "(server/deploy/chaos-server.service, or chaos-trial-server.service for the Linux kit) or set CHAOS_UNIT in $CONF." >&2
    exit 5
  fi
}
# the engine's pid from CHAOS_PID_FILE, when that process is alive and is the engine (tfs)
engine_pid() {
  local p
  [ -r "$PIDFILE" ] || return 1
  p=$(head -c 20 "$PIDFILE" | tr -dc 0-9)
  [ -n "$p" ] && [ -d "/proc/$p" ] || return 1
  [ "$(cat "/proc/$p/comm" 2>/dev/null)" = tfs ] || return 1
  echo "$p"
}

num() { case ${1:-} in ''|*[!0-9]*) return 1 ;; esac; }
lines_arg() {
  local n=${1:-60}
  num "$n" || die "N must be a number"
  [ "$n" -le 500 ] || n=500
  [ "$n" -ge 1 ] || n=1
  echo "$n"
}

# one remote.cmd line; the text is one line of printable characters (the engine checks it again)
spool() {
  local file="$SERVER/remote.cmd" line=$1 max=${2:-300}
  [ -d "$SERVER" ] || die "no server folder $SERVER"
  case $line in *$'\n'*|*$'\r'*) die "one line only" ;; esac
  [ "${#line}" -le "$max" ] || die "too long"
  printf '%s\n' "$line" >> "$file" || die "cannot write $file"
  chown "$(stat -c %U "$SERVER" 2>/dev/null || echo root)" "$file" 2>/dev/null || true
  chmod 0664 "$file" 2>/dev/null || true
  echo "queued: the server runs it within a few seconds (see: chaos-ctl.sh logs)"
}

# one query against the game database ("-": read from stdin); the password goes through a temporary option
# file, never a command line
mysql_q() {
  [ -r "$ENVFILE" ] || die "cannot read $ENVFILE"
  command -v "$MYSQL" >/dev/null 2>&1 || {
    echo "chaos-ctl: mysql-not-found: no database client $MYSQL (set CHAOS_MYSQL in $CONF)" >&2; exit 127; }
  local cnf db rc
  cnf=$(mktemp) || die "no temp file"
  chmod 0600 "$cnf"
  db=$( set -a; . "$ENVFILE"; set +a
    sock=${DBSOCK:-${CHAOS_DB_SOCKET:-}}
    { echo '[client]'
      if [ -n "$sock" ]; then printf 'socket=%s\n' "$sock"
      else printf 'host=%s\nport=%s\n' "${CHAOS_DB_HOST:-127.0.0.1}" "${CHAOS_DB_PORT:-3306}"; fi
      printf 'user=%s\npassword="%s"\n' "${CHAOS_DB_USER:-chaos}" "${CHAOS_DB_PASS:-}"; } > "$cnf"
    echo "${CHAOS_DB_NAME:-chaos}" )
  if [ "$1" = - ]; then "$MYSQL" --defaults-extra-file="$cnf" -N -B "$db"
  else "$MYSQL" --defaults-extra-file="$cnf" -N -B "$db" -e "$1"; fi
  rc=$?
  rm -f "$cnf"
  return $rc
}

# vocation id -> class name, kept in sync with docs/CLASSES.md and server/data/XML/chaos_vocations*.xml (chaos_ctl_test.py
# checks it). 2, 6 and 9 are retired ids (their characters were migrated).
VOCATIONS=(0:None 1:Mystic 3:Ranger 4:Warrior 5:Elementalist 7:Deadeye 8:Juggernaut 10:Illusionist 11:Thief 12:Ninja
  13:Samurai 14:Berserker 15:Beastmaster 17:Monk 18:Shadowfist "19:Iron Sage" 20:Necromancer 21:Lich "22:Bone Lord"
  23:Templar 24:Inquisitor 25:Sentinel)
voc_case() {
  local v sql="CASE $1"
  for v in "${VOCATIONS[@]}"; do sql+=" WHEN ${v%%:*} THEN '${v#*:}'"; done
  printf '%s' "$sql ELSE CONCAT('vocation ', $1) END"
}

# the error report of "errors": runs split at a server start (the Linux kit's "Starting the game server (DATE)" line,
# else the engine's "Loading config" line), Lua errors joined with their next two lines, identical entries counted
error_report() {  # MODE (current|all) MAX SINCE (the unit's start time, the date of the newest run when its line has none)
  tail -n 20000 "$LOG" 2>/dev/null | awk -v mode="$1" -v max="$2" -v since="$3" '
    function newrun(label) { nr++; lab[nr] = label; n[nr] = 0 }
    function add(e,   st, k) {
      st = ""
      if (match(e, /^\[?[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][ T][0-9][0-9]:[0-9][0-9]:[0-9][0-9][^ ]*\]?[ :-]*/)) {
        st = substr(e, RSTART, RLENGTH); e = substr(e, RSTART + RLENGTH)
        gsub(/^\[|[] :-]+$/, "", st)
      }
      k = nr SUBSEP e
      if (!(k in cnt)) { n[nr]++; ord[nr, n[nr]] = e }
      cnt[k]++
      if (st != "") last[k] = st
    }
    function flush() { if (cur != "") add(cur); cur = ""; join = 0 }
    function iserr(l) { return l ~ /Lua Script Error/ || tolower(l) ~ /error|exception|segfault/ }
    BEGIN { nr = 0; newrun("?"); cur = ""; join = 0; pend = 0 }
    {
      line = $0; sub(/\r$/, "", line)
      if (match(line, /Starting the game server \([0-9][0-9-]* [0-9:]*\)/)) {
        flush(); newrun(substr(line, RSTART + 26, RLENGTH - 27)); pend = 50; next
      }
      if (line ~ /Loading config/) { flush(); if (pend > 0) pend = 0; else newrun("?"); next }
      if (pend > 0) pend--
      if (join > 0) {
        if (line ~ /^[[:space:]]*$/ || iserr(line)) flush()
        else { cur = cur " | " line; join--; if (join == 0) flush(); next }
      }
      if (line ~ /Lua Script Error/) { cur = line; join = 2; next }
      if (iserr(line)) add(line)
    }
    END {
      flush()
      first = (mode == "all") ? 1 : nr
      older = 0
      for (r = 1; r < nr; r++) if (n[r] > 0) older++
      for (r = first; r <= nr; r++) {
        if (r == 1 && nr > 1 && n[1] == 0) continue
        l = lab[r]
        if (r == nr && r > 1 && l == "?" && since != "") l = since
        if (l == "?") l = "unknown"
        printf "@run %s%s\n", l, (r == nr ? " current" : "")
        i = (n[r] > max) ? n[r] - max + 1 : 1
        for (; i <= n[r]; i++) {
          e = ord[r, i]; k = r SUBSEP e
          printf "%dx %s%s\n", cnt[k], e, ((k in last) ? " [" last[k] "]" : "")
        }
      }
      if (mode != "all") printf "@older %d\n", older
    }'
}

cmd=${1:-}
[ $# -gt 0 ] && shift
case $cmd in
  status)
    echo "unit=$UNIT"
    echo "unit_state=$(unit_state)"
    echo "service=$(systemctl is-active "$UNIT" 2>/dev/null || true)"
    echo "since=$(systemctl show "$UNIT" -p ActiveEnterTimestamp --value 2>/dev/null || true)"
    echo "pid=$(engine_pid || true)"
    echo "players=$( (mysql_q 'SELECT COUNT(*) FROM players_online') 2>/dev/null || echo '?')"
    echo "load=$(cut -d' ' -f1-3 /proc/loadavg)"
    echo "mem=$(free -m | awk '/^Mem:/ {printf "%d/%d MB", $3, $2}')"
    echo "disk=$(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')"
    bdir=${BACKUPDIR:-$( . "$ENVFILE" 2>/dev/null; echo "${CHAOS_BACKUP_DIR:-/var/backups/chaos}" )}
    last=$(find "$bdir/db" -name '*.sql.gz' -printf '%TY-%Tm-%Td %TH:%TM\n' 2>/dev/null | sort | tail -1)
    echo "backup=${last:-none}"
    echo "errors=$(error_report current 100000 "" | awk '/^[0-9]+x / { s += $1 } END { print s + 0 }')"
    ;;
  start|stop)
    need_unit
    systemctl "$cmd" "$UNIT" && echo "$cmd: done ($(systemctl is-active "$UNIT" 2>/dev/null))"
    ;;
  save)
    # SIGUSR1 to the engine only: under the kit's unit the main process is start-server.sh, which SIGUSR1 would end
    if p=$(engine_pid); then
      kill -USR1 "$p" && echo "save requested (players are saved in small steps)"
    else
      need_unit
      systemctl kill -s SIGUSR1 --kill-who=main "$UNIT" && echo "save requested (players are saved in small steps)"
    fi
    ;;
  restart)
    secs=${1:-0}
    num "$secs" || die "SECONDS must be a number"
    [ "$secs" -le 900 ] || die "at most 900 seconds"
    need_unit
    if [ "$secs" -eq 0 ]; then
      systemctl restart "$UNIT" && echo "restarted ($(systemctl is-active "$UNIT" 2>/dev/null))"
    else
      CHAOS_CTL_NO_SUDO=1 "$SELF" broadcast "The server restarts in $secs seconds. Please log out." >/dev/null
      # detached, so the connection can close; the restart saves everyone (SIGTERM)
      # shellcheck disable=SC2016
      setsid bash -c 'sleep "$1"; systemctl restart "$2"' _ "$secs" "$UNIT" >/dev/null 2>&1 < /dev/null &
      echo "restart in $secs seconds"
    fi
    ;;
  backup)
    [ -x "$REPO/server/tools/backup.sh" ] || die "no $REPO/server/tools/backup.sh"
    if p=$(engine_pid); then save=(--save-pid "$p"); else save=(--save-service "$UNIT"); fi
    # the kit's own database client and dump tool, when the system has none
    [ -d "$ROOT/mariadb/bin" ] && PATH="$PATH:$ROOT/mariadb/bin"
    ( set -a; . "$ENVFILE"
      # shellcheck disable=SC2030 # for backup.sh in this subshell only
      [ -n "$BACKUPDIR" ] && CHAOS_BACKUP_DIR=$BACKUPDIR
      [ -n "$DBSOCK" ] && CHAOS_DB_SOCKET=$DBSOCK
      set +a; "$REPO/server/tools/backup.sh" "${save[@]}" 2>&1 | tail -n 30 )
    ;;
  logs)
    tail -n "$(lines_arg "${1:-60}")" "$LOG" 2>&1
    ;;
  errors)
    max=40 mode=current
    for a in "$@"; do
      case $a in all) mode=all ;; *) max=$(lines_arg "$a") || exit 1 ;; esac
    done
    [ -r "$LOG" ] || die "cannot read the log $LOG (set CHAOS_LOG in $CONF)"
    since=""
    [ "$(systemctl is-active "$UNIT" 2>/dev/null)" = active ] \
      && since=$(date -d "$(systemctl show "$UNIT" -p ActiveEnterTimestamp --value 2>/dev/null)" '+%F %T' 2>/dev/null)
    error_report "$mode" "$max" "$since"
    ;;
  players)
    mysql_q "SELECT p.name, p.level, $(voc_case p.vocation) FROM players p JOIN players_online o ON o.player_id = p.id ORDER BY p.name"
    ;;
  vocations)
    for v in "${VOCATIONS[@]}"; do echo "${v%%:*}=${v#*:}"; done
    ;;
  broadcast)
    [ $# -ge 1 ] || die "broadcast TEXT"
    spool "broadcast $*"
    ;;
  kick)
    [ $# -ge 1 ] || die "kick NAME"
    spool "kick $*"
    ;;
  open|close)
    spool "$cmd"
    ;;
  catalog|panel)
    actor=${1:-}
    [[ $actor =~ ^[A-Za-z][A-Za-z\ \'-]{2,28}$ ]] || die "$cmd ACTOR: the name of an admin character"
    out="$SERVER/remote.catalog"
    if [ "$cmd" = catalog ]; then
      [ $# -eq 1 ] || die "catalog ACTOR"
      rm -f "$out"
      spool "catalog $actor" >/dev/null
      for _ in $(seq 1 30); do
        [ -s "$out" ] && { cat "$out"; exit 0; }
        sleep 0.5
      done
      die "no answer in 15 s: is $actor an admin character, and is the server running the remote command script?"
    fi
    action=${2:-}
    json=${3:-}
    [[ $action =~ ^[A-Za-z0-9_.]{1,64}$ ]] || die "panel ACTOR ACTION JSON (ACTION like players.kick)"
    [ -n "$json" ] || json='{}'
    [[ $json == "{"*"}" ]] || die "JSON must be one object"
    [ "${#json}" -le 900 ] || die "JSON too long (900 characters at most)"
    rid=$(( (RANDOM * 32768 + RANDOM) % 900000000 + 100000000 ))
    res="$SERVER/remote.result"
    spool "panel $rid $action|$actor|$json" 1400 >/dev/null
    for _ in $(seq 1 30); do
      if [ -r "$res" ]; then
        hit=$(grep -E "\"rid\": ?$rid([^0-9]|$)" "$res" | tail -n 1)
        [ -z "$hit" ] || { echo "$hit"; exit 0; }
      fi
      sleep 0.5
    done
    die "no answer in 15 s: is $actor an admin character, and is the server running the remote command script?"
    ;;
  update|rollback)
    # the Linux kit updates from its branch and the newest release (update-apply); its rollback is update-rollback
    if [ -n "$KIT" ] && [ -x "$REPO/server/deploy/chaos_kit_update.sh" ]; then
      [ "$cmd" = update ] && die "kit-layout: the Linux kit updates with update-check and update-apply, not by tag"
      [ "${1:-}" = now ] || die "kit-layout: rollback now (the kit has no at-save)"
      exec "$SELF" update-rollback
    fi
    if [ "$cmd" = update ]; then
      tag=${1:-}
      mode=${2:-}
      [[ $tag =~ ^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$ ]] || die "update TAG now|at-save (TAG: a release tag)"
      [[ $tag != *..* ]] || die "bad tag"
      args=(--ref "$tag")
    else
      mode=${1:-}
      args=(--rollback)
    fi
    case $mode in now) args+=(--now) ;; at-save) args+=(--at-save) ;; *) die "now or at-save" ;; esac
    [ -x "$REPO/server/deploy/chaos_update.sh" ] || die "no $REPO/server/deploy/chaos_update.sh"
    mkdir -p "$(dirname "$ULOG")"
    : > "$ULOG"
    setsid "$REPO/server/deploy/chaos_update.sh" "${args[@]}" --yes >> "$ULOG" 2>&1 < /dev/null &
    echo "started ($cmd ${args[*]}); follow it with: chaos-ctl.sh update-log"
    ;;
  update-log)
    tail -n "$(lines_arg "${1:-60}")" "$ULOG" 2>&1
    ;;
  publish-update)
    tag=${1:-}
    if ! [[ $tag =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || [[ $tag == *..* ]]; then
      die "publish-update TAG [--version N] [--min-package N] (TAG: a release tag like winpkg-46)"
    fi
    shift
    args=()
    while [ $# -gt 0 ]; do
      case $1 in
        --version|--min-package) { num "${2:-}" && [ "${#2}" -le 9 ]; } || die "$1 N"; args+=("$1" "$2"); shift 2 ;;
        *) die "publish-update TAG [--version N] [--min-package N]" ;;
      esac
    done
    pub="$REPO/server/deploy/publish_client_update.sh"
    [ -x "$pub" ] || die "no $pub"
    penv=()
    for k in CHAOS_SITE_DIR CHAOS_UPDATE_KEY CHAOS_UPDATE_PUBLIC CHAOS_UPDATE_REPO CHAOS_UPDATE_URL CHAOS_WORK_DIR; do
      v=$(setting "$k" "")
      [ -z "$v" ] || penv+=("$k=$v")
    done
    penv+=("CHAOS_ENV=$ENVFILE")  # publish_client_update.sh reads CHAOS_CLIENT_KEY from it (the blob key)
    mkdir -p "$(dirname "$PLOG")"
    : > "$PLOG"
    setsid env "${penv[@]}" "$pub" "${args[@]}" -- "$tag" >> "$PLOG" 2>&1 < /dev/null &
    echo "started (publish-update $tag ${args[*]}); follow it with: chaos-ctl.sh publish-log"
    ;;
  publish-log)
    tail -n "$(lines_arg "${1:-60}")" "$PLOG" 2>&1
    ;;
  update-check|update-apply|update-rollback)
    [ -n "$KIT" ] || die "kit-not-found: update-check / update-apply are for the Linux kit (set CHAOS_KIT_DIR in $CONF)"
    kup="$REPO/server/deploy/chaos_kit_update.sh"
    [ -x "$kup" ] || die "no $kup (CHAOS_REPO)"
    kargs=()
    if [ "$cmd" = update-apply ]; then
      for a in "$@"; do
        case $a in
          --no-client|--no-downloads|--no-site) kargs+=("$a") ;;
          *) die "update-apply [--no-client] [--no-downloads] [--no-site]" ;;
        esac
      done
    else
      [ $# -eq 0 ] || die "$cmd takes no arguments"
    fi
    kenv=("CHAOS_REPO=$REPO" "CHAOS_KIT_DIR=$KIT" "CHAOS_SERVER_DIR=$SERVER" "CHAOS_ENV=$ENVFILE" "CHAOS_UNIT=$UNIT"
      "CHAOS_LOG=$LOG" "CHAOS_MYSQL=$MYSQL" "CHAOS_KIT_STATE=$KSTATE" "CHAOS_WORK_DIR=$WORKDIR")
    for k in CHAOS_UPDATE_BRANCH CHAOS_RELEASE_REPO CHAOS_BOOT_TIMEOUT CHAOS_SITE_DIR CHAOS_DL_DIR CHAOS_SITE_ENV \
      CHAOS_UPDATE_KEY CHAOS_UPDATE_PUBLIC CHAOS_UPDATE_REPO CHAOS_UPDATE_URL; do
      v=$(setting "$k" "")
      [ -z "$v" ] || kenv+=("$k=$v")
    done
    [ -z "$BACKUPDIR" ] || kenv+=("CHAOS_BACKUP_DIR=$BACKUPDIR")
    if [ "$cmd" = update-check ]; then
      env "${kenv[@]}" "$kup" check
      exit $?
    fi
    if [ -f "$KSTATE/.lock" ] && ! flock -n "$KSTATE/.lock" true; then
      die "update-running: an update or rollback is running (chaos-ctl.sh update-log)"
    fi
    mkdir -p "$(dirname "$ULOG")"
    : > "$ULOG"
    sub=apply
    [ "$cmd" = update-rollback ] && sub=rollback
    setsid env "${kenv[@]}" "$kup" "$sub" "${kargs[@]}" >> "$ULOG" 2>&1 < /dev/null &
    echo "started ($cmd ${kargs[*]}); follow it with: chaos-ctl.sh update-log"
    ;;
  update-status)
    st="$KSTATE/state"
    if [ -f "$KSTATE/.lock" ] && ! flock -n "$KSTATE/.lock" true; then echo "running=yes"; else echo "running=no"; fi
    for k in status result time installed_release deployed_commit dl_release; do
      echo "$k=$( [ -f "$st" ] && sed -n "s/^$k=//p" "$st" | tail -n 1)"
    done
    ;;
  xp-rate)
    tool="$REPO/server/deploy/chaos_config_rates.py"
    [ -f "$tool" ] || die "no $tool (CHAOS_REPO)"
    [ -f "$SERVER/config.lua" ] || die "no $SERVER/config.lua (CHAOS_SERVER_DIR)"
    sub=${1:-show}
    again=0
    case $sub in
      show)
        [ $# -le 1 ] || die "xp-rate show"
        python3 -I "$tool" show "$SERVER/config.lua"
        exit $?
        ;;
      set)
        n=${2:-}
        { num "$n" && [ "${#n}" -le 3 ] && [ "$n" -ge 1 ] && [ "$n" -le 100 ]; } || die "xp-rate set N (1..100) [restart]"
        case $#:${3:-} in 2:) ;; 3:restart) again=1 ;; *) die "xp-rate set N [restart]" ;; esac
        python3 -I "$tool" set "$SERVER/config.lua" "$n" || exit 1
        ;;
      reset)
        case $#:${2:-} in 1:) ;; 2:restart) again=1 ;; *) die "xp-rate reset [restart]" ;; esac
        python3 -I "$tool" reset "$SERVER/config.lua" || exit 1
        ;;
      *) die "xp-rate [show | set N | reset] [restart]" ;;
    esac
    if [ "$again" = 1 ]; then
      need_unit
      systemctl restart "$UNIT" && echo "restarted ($(systemctl is-active "$UNIT" 2>/dev/null))"
    else
      echo "applies at the next restart"
    fi
    ;;
  backups)
    [ $# -eq 0 ] || die "backups takes no arguments"
    # shellcheck disable=SC2031 # read in this subshell on purpose (the env file's value)
    bdir=${BACKUPDIR:-$( . "$ENVFILE" 2>/dev/null; echo "${CHAOS_BACKUP_DIR:-/var/backups/chaos}" )}
    echo "dir=$bdir"
    for kind in db data; do
      find "$bdir/$kind" -maxdepth 1 -type f \( -name '*.sql.gz' -o -name '*.tar.gz' \) \
        -printf "$kind\t%TY-%Tm-%Td %TH:%TM\t%s\t%p\n" 2>/dev/null | sort -t$'\t' -k2,2r | head -n 15 || true
    done
    ;;
  site-install)
    [ $# -eq 0 ] || die "site-install takes no arguments"
    inst="$REPO/website/install_site.sh"
    [ -x "$inst" ] || die "no $inst"
    senv=$(setting CHAOS_SITE_ENV /etc/chaos/site.env)
    [ -r "$senv" ] || die "no site settings file $senv (CHAOS_SITE_ENV; website/site.env.example)"
    mkdir -p "$(dirname "$SITELOG")"
    : > "$SITELOG"
    setsid "$inst" "$ENVFILE" "$senv" >> "$SITELOG" 2>&1 < /dev/null &
    echo "started (site-install); follow it with: chaos-ctl.sh site-log"
    ;;
  site-log)
    tail -n "$(lines_arg "${1:-60}")" "$SITELOG" 2>&1
    ;;
  health|cleanup)
    # the leftovers: work folders of updates and publishes (a day old), srvNN folders, old engine and config backups
    leftovers() {
      find "$WORKDIR" -maxdepth 1 -mindepth 1 ! -type l -mtime +0 \( -name 'chaos-kit-update.*' \
        -o -name 'chaos-kit-check.*' -o -name 'chaos-publish.*' \) -print 2>/dev/null
      find "$WORKDIR" -maxdepth 1 -mindepth 1 -type d -regex '.*/srv[0-9]+' -print 2>/dev/null
      # shellcheck disable=SC2012 # plain backup names
      ls -1t "$SERVER"/tfs.antes-* 2>/dev/null | tail -n +3
      # shellcheck disable=SC2012
      ls -1td "$SERVER"/config.lua.before-* 2>/dev/null | tail -n +6
    }
    mapfile -t junk < <(leftovers)
    if [ "$cmd" = health ]; then
      [ $# -eq 0 ] || die "health takes no arguments"
      echo "unit=$UNIT"
      echo "service=$(systemctl is-active "$UNIT" 2>/dev/null || true)"
      echo "engine_pid=$(engine_pid || true)"
      if (mysql_q 'SELECT 1') >/dev/null 2>&1; then echo "database=ok"; else echo "database=down"; fi
      web=""
      fpm=$(systemctl list-units --type=service --all --no-legend 'php*-fpm*' 2>/dev/null | awk '{print $1}' | sed 's/\.service$//')
      for u in nginx apache2 httpd caddy $fpm; do
        [ "$(systemctl show "$u" -p LoadState --value 2>/dev/null)" = loaded ] || continue
        web+="${web:+ }$u:$(systemctl is-active "$u" 2>/dev/null || true)"
      done
      echo "web=${web:-none}"
      echo "disk=$(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')"
      echo "disk_free=$(df -h "$WORKDIR" 2>/dev/null | awk 'NR==2 {print $4}')"
      echo "mem=$(free -m | awk '/^Mem:/ {printf "%d/%d MB", $3, $2}')"
      size=0
      [ "${#junk[@]}" -eq 0 ] || size=$(du -scb "${junk[@]}" 2>/dev/null | tail -n 1 | cut -f1)
      echo "cleanup=${#junk[@]} item(s), $((size / 1048576)) MB"
      exit 0
    fi
    yes=0
    case $#:${1:-} in 0:) ;; 1:--yes) yes=1 ;; *) die "cleanup [--yes]" ;; esac
    [ "${#junk[@]}" -gt 0 ] || { echo "nothing to clean up"; exit 0; }
    total=0
    for j in "${junk[@]}"; do
      sz=$(du -sb "$j" 2>/dev/null | cut -f1)
      total=$((total + ${sz:-0}))
      if [ "$yes" = 1 ]; then
        rm -rf -- "$j" && echo "removed $j ($(( ${sz:-0} / 1048576 )) MB)"
      else
        echo "would remove $j ($(( ${sz:-0} / 1048576 )) MB)"
      fi
    done
    if [ "$yes" = 1 ]; then echo "freed $((total / 1048576)) MB"
    else echo "total $((total / 1048576)) MB (cleanup --yes removes them)"; fi
    ;;
  gm-logs)
    # staff logs: the base server's command logs (data/logs/<name> commands.log) and the admin panel's audit table
    n=60 who=""
    for a in "$@"; do
      if num "$a"; then n=$(lines_arg "$a")
      elif [ -z "$who" ] && [[ $a =~ ^[A-Za-z][A-Za-z\ \'-]{1,28}$ ]]; then who=$a
      else die "gm-logs [N] [PLAYER]"; fi
    done
    gdir="$SERVER/data/logs"
    echo "@staff"
    { find "$gdir" -maxdepth 1 -type f -name '* commands.log' -printf '%f\n' 2>/dev/null | sed 's/ commands\.log$//'
      mysql_q "SELECT DISTINCT player_name FROM chaos_admin_log WHERE player_name <> '' ORDER BY player_name" 2>/dev/null
    } | grep -E "^[A-Za-z][A-Za-z '-]{1,28}$" | sort -u || true
    echo "@files"
    find "$gdir" -maxdepth 1 -type f \( -name '*.log' -o -name '*.txt' \) -printf '%TY-%Tm-%Td %TH:%TM\t%s\t%f\n' 2>/dev/null \
      | sort -r | head -n 40 || true
    if [ -n "$who" ]; then
      f="$gdir/$who commands.log"
      echo "@commands $who"
      if [ -f "$f" ] && [ ! -L "$f" ] && [ "$(dirname "$(readlink -f "$f")")" = "$(readlink -f "$gdir")" ]; then
        tail -n "$n" "$f" | tac
      fi
      where="WHERE player_name = '${who//\'/\'\'}'"
    else
      where=""
    fi
    echo "@panel"
    mysql_q "SELECT FROM_UNIXTIME(created_at, '%Y-%m-%d %H:%i'), player_name, action, target, status, message FROM chaos_admin_log $where ORDER BY id DESC LIMIT $n" \
      2>/dev/null || echo "(the admin panel log could not be read: is the database up?)"
    ;;
  account-create|account-password)
    name=${1:-}
    { [ $# -eq 1 ] && [[ $name =~ ^[A-Za-z0-9]{3,32}$ ]]; } || die "$cmd NAME (3-32 letters or digits; the password on stdin)"
    IFS= read -r -t 30 pass || [ -n "${pass:-}" ] || die "no password on stdin"
    pass=${pass%$'\r'}
    { [ "${#pass}" -ge 6 ] && [ "${#pass}" -le 64 ]; } || die "the password must have 6 to 64 characters"
    if [[ $pass =~ [[:cntrl:]] ]]; then die "the password must be one line of printable characters"; fi
    iters=$(sed -nE 's/^[[:space:]]*passwordHashIterations[[:space:]]*=[[:space:]]*([0-9]{1,7}).*/\1/p' \
      "$SERVER/config.lua" 2>/dev/null | head -n 1)
    { num "${iters:-}" && [ "$iters" -ge 1000 ]; } || iters=120000
    # PBKDF2-SHA256 as the website and the engine write it (server/README.md "Account passwords")
    hash=$(printf '%s' "$pass" | python3 -I -c '
import base64, hashlib, os, sys
pw = sys.stdin.buffer.read(); n = int(sys.argv[1]); salt = os.urandom(16)
key = hashlib.pbkdf2_hmac("sha256", pw, salt, n, 32)
print("pbkdf2-sha256$%d$%s$%s" % (n, base64.b64encode(salt).decode(), base64.b64encode(key).decode()))' "$iters") \
      || die "could not hash the password"
    unset pass
    [[ $hash =~ ^pbkdf2-sha256\$[0-9]+\$[A-Za-z0-9+/=]+\$[A-Za-z0-9+/=]+$ ]] || die "bad hash"
    have=$(mysql_q "SELECT COUNT(*) FROM accounts WHERE name = '$name'") \
      || die "database-down: the database did not answer"
    if [ "$cmd" = account-create ]; then
      [ "$have" = 0 ] || die "account-exists: the account $name exists already"
      sql="INSERT INTO accounts (name, password, type, creation) VALUES ('$name', '$hash', 1, UNIX_TIMESTAMP())"
    else
      [ "$have" = 1 ] || die "account-not-found: no account $name"
      sql="UPDATE accounts SET password = '$hash' WHERE name = '$name'"
    fi
    # the hash reaches the database client on stdin, not on its command line
    mysql_q - <<< "$sql;" || die "the database refused the change"
    if [ "$cmd" = account-create ]; then
      echo "account $name created (its character is made in the client or on the website)"
    else
      echo "password of $name changed"
    fi
    ;;
  install-admin)
    full=0
    if [ "${1:-}" = "--full" ]; then full=1; shift; fi
    keysrc=${1:-}
    [ -n "$keysrc" ] || die "install-admin [--full] KEYFILE|-"
    if [ "$keysrc" = "-" ]; then key=$(head -c 2000); else key=$(head -c 2000 "$keysrc"); fi
    [[ $key =~ ^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256)\ [A-Za-z0-9+/=]+(\ [^[:cntrl:]]*)?$ ]] \
      || die "not one ssh public key line"
    [[ $ADMIN =~ ^[a-z][a-z0-9_-]{1,30}$ ]] || die "bad CHAOS_ADMIN_USER"
    id "$ADMIN" >/dev/null 2>&1 \
      || adduser --disabled-password --gecos "Cinders of Chaos admin" "$ADMIN" >/dev/null || die "adduser failed"
    home=$(getent passwd "$ADMIN" | cut -d: -f6)
    install -d -m 0700 -o "$ADMIN" -g "$ADMIN" "$home/.ssh"
    printf '%s\n' "$key" > "$home/.ssh/authorized_keys"
    chown "$ADMIN:$ADMIN" "$home/.ssh/authorized_keys"
    chmod 0600 "$home/.ssh/authorized_keys"
    tmp=$(mktemp)
    if [ "$full" -eq 1 ]; then
      echo "$ADMIN ALL=(ALL) NOPASSWD: ALL" > "$tmp"
    else
      echo "$ADMIN ALL=(root) NOPASSWD: $SELF" > "$tmp"
    fi
    chmod 0440 "$tmp"
    visudo -cf "$tmp" >/dev/null || { rm -f "$tmp"; die "sudoers check failed"; }
    install -m 0440 "$tmp" /etc/sudoers.d/chaos-admin
    rm -f "$tmp"
    echo "user $ADMIN ready ($([ "$full" -eq 1 ] && echo 'full sudo' || echo 'sudo for chaos-ctl.sh only')); key installed"
    ;;
  ''|help|-h|--help)
    sed -n '2,/^set -uo/p' "$SELF" | sed '$d' | sed 's/^# \{0,1\}//'
    ;;
  *)
    die "unknown command: $cmd (chaos-ctl.sh help)"
    ;;
esac
