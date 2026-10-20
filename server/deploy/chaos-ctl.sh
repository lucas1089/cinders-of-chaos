#!/usr/bin/env bash
# Cinders of Chaos: one command for the live server, for the admin app (android/) and for you over ssh.
# The routine: docs/ADMIN_APP.md. Layout assumed: docs/LAUNCH.md (systemd unit chaos-server, /opt/chaos, /etc/chaos/chaos.env).
#
# usage: chaos-ctl.sh COMMAND [args]       (as root, or as a user that may sudo it: it asks sudo -n itself)
#
#   status                      key=value lines: service, since, players, load, mem, disk, backup, errors
#   start | stop | save         systemctl start / stop (the engine saves first) / SIGUSR1 (save without stopping)
#   restart [SECONDS]           at once, or after a countdown: players are told, then restart (runs in the background)
#   backup                      server/tools/backup.sh with a save first
#   logs [N]                    the last N (default 60, at most 500) lines of the engine console
#   errors [N]                  the last N lines with "Lua Script Error" / "error"
#   players                     online characters: name, level, vocation id
#   broadcast TEXT              a message to everyone online     (remote.cmd, server/README.md "Remote admin commands")
#   kick NAME | open | close    kick one character / let players log in / close the server for login
#   update TAG now|at-save      chaos_update.sh --ref TAG (--now | --at-save) --yes, in the background (update-log)
#   rollback now|at-save        chaos_update.sh --rollback, in the background
#   update-log [N]              the last N lines of the update log
#   install-admin [--full] KEYFILE|-
#                               creates the user "chaosadmin" with that ssh public key (a file, or - for stdin) and the
#                               right to run this script as root; --full also gives it passwordless sudo for everything
#
# Settings (environment, defaults for the standard layout): CHAOS_UNIT chaos-server, CHAOS_ROOT /opt/chaos,
# CHAOS_SERVER_DIR $CHAOS_ROOT/server, CHAOS_REPO $CHAOS_ROOT/repo, CHAOS_ENV /etc/chaos/chaos.env,
# CHAOS_LOG /var/log/chaos/server.log, CHAOS_UPDATE_LOG /var/log/chaos/update.log, CHAOS_ADMIN_USER chaosadmin.
# shellcheck source=/dev/null
set -uo pipefail

UNIT=${CHAOS_UNIT:-chaos-server}
ROOT=${CHAOS_ROOT:-/opt/chaos}
SERVER=${CHAOS_SERVER_DIR:-$ROOT/server}
REPO=${CHAOS_REPO:-$ROOT/repo}
ENVFILE=${CHAOS_ENV:-/etc/chaos/chaos.env}
LOG=${CHAOS_LOG:-/var/log/chaos/server.log}
ULOG=${CHAOS_UPDATE_LOG:-/var/log/chaos/update.log}
ADMIN=${CHAOS_ADMIN_USER:-chaosadmin}
SELF=$(readlink -f "$0")

die() { echo "chaos-ctl: $*" >&2; exit 1; }

# root is needed for systemctl, the log and the database password; a user in sudoers for this script gets it by sudo -n
if [ "$(id -u)" -ne 0 ] && [ -z "${CHAOS_CTL_NO_SUDO:-}" ]; then
  exec sudo -n "$SELF" "$@"
fi

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
  local file="$SERVER/remote.cmd" line=$1
  [ -d "$SERVER" ] || die "no server folder $SERVER"
  case $line in *$'\n'*|*$'\r'*) die "one line only" ;; esac
  [ "${#line}" -le 300 ] || die "too long"
  printf '%s\n' "$line" >> "$file" || die "cannot write $file"
  chown "$(stat -c %U "$SERVER" 2>/dev/null || echo root)" "$file" 2>/dev/null || true
  chmod 0664 "$file" 2>/dev/null || true
  echo "queued: the server runs it within a few seconds (see: chaos-ctl.sh logs)"
}

# one query against the game database; the password goes through a temporary option file, never a command line
mysql_q() {
  [ -r "$ENVFILE" ] || die "cannot read $ENVFILE"
  local cnf db rc
  cnf=$(mktemp) || die "no temp file"
  chmod 0600 "$cnf"
  db=$( set -a; . "$ENVFILE"; set +a
    printf '[client]\nhost=%s\nport=%s\nuser=%s\npassword="%s"\n' "${CHAOS_DB_HOST:-127.0.0.1}" "${CHAOS_DB_PORT:-3306}" \
      "${CHAOS_DB_USER:-chaos}" "${CHAOS_DB_PASS:-}" > "$cnf"
    echo "${CHAOS_DB_NAME:-chaos}" )
  mysql --defaults-extra-file="$cnf" -N -B "$db" -e "$1"
  rc=$?
  rm -f "$cnf"
  return $rc
}

cmd=${1:-}
[ $# -gt 0 ] && shift
case $cmd in
  status)
    echo "service=$(systemctl is-active "$UNIT" 2>/dev/null || true)"
    echo "since=$(systemctl show "$UNIT" -p ActiveEnterTimestamp --value 2>/dev/null || true)"
    echo "players=$(mysql_q 'SELECT COUNT(*) FROM players_online' 2>/dev/null || echo '?')"
    echo "load=$(cut -d' ' -f1-3 /proc/loadavg)"
    echo "mem=$(free -m | awk '/^Mem:/ {printf "%d/%d MB", $3, $2}')"
    echo "disk=$(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')"
    bdir=$( . "$ENVFILE" 2>/dev/null; echo "${CHAOS_BACKUP_DIR:-/var/backups/chaos}" )
    last=$(find "$bdir/db" -name '*.sql.gz' -printf '%TY-%Tm-%Td %TH:%TM\n' 2>/dev/null | sort | tail -1)
    echo "backup=${last:-none}"
    echo "errors=$(tail -n 2000 "$LOG" 2>/dev/null | grep -c 'Lua Script Error')"
    ;;
  start|stop)
    systemctl "$cmd" "$UNIT" && echo "$cmd: done ($(systemctl is-active "$UNIT" 2>/dev/null))"
    ;;
  save)
    systemctl kill -s SIGUSR1 "$UNIT" && echo "save requested (players are saved in small steps)"
    ;;
  restart)
    secs=${1:-0}
    num "$secs" || die "SECONDS must be a number"
    [ "$secs" -le 900 ] || die "at most 900 seconds"
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
    ( set -a; . "$ENVFILE"; set +a; "$REPO/server/tools/backup.sh" --save-service "$UNIT" 2>&1 | tail -n 30 )
    ;;
  logs)
    tail -n "$(lines_arg "${1:-60}")" "$LOG" 2>&1
    ;;
  errors)
    tail -n 5000 "$LOG" 2>&1 | grep -i -E 'Lua Script Error|error|exception|segfault' | tail -n "$(lines_arg "${1:-40}")"
    ;;
  players)
    mysql_q "SELECT p.name, p.level, p.vocation FROM players p JOIN players_online o ON o.player_id = p.id ORDER BY p.name"
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
  update|rollback)
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
