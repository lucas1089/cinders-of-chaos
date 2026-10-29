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
#                               starts had errors. Only lines after the newest "errors clear" count
#   errors clear                the error list starts empty from now on: a marker line goes into the log (nothing in
#                               the log is deleted; logs and the update log still show everything)
#   players                     online characters: name, level, class name (tab separated)
#   vocations                   id=class name, one per line
#   metrics [--json]            anonymous progress counters (server/README.md "Progress metrics (O253)"), read-only: churn by level
#                               band, the 10 areas and monsters with the most deaths, first session length, median time to
#                               level 10 / 25 / 50 / 100 / 200. Reads the aggregate table chaos_progress_metrics (no names,
#                               accounts or IPs) through server/tools/progress_metrics.py; text, or one JSON line with --json
#                               ({"ok": false, "error": "no-table" | "database"} and exit 1 when it cannot be read)
#   broadcast TEXT              a message to everyone online     (remote.cmd, server/README.md "Remote admin commands")
#   kick NAME | open | close    kick one character / let players log in / close the server for login
#   catalog ACTOR               the admin panel's catalog (all actions and their parameters) for the admin character ACTOR
#   panel ACTOR ACTION JSON     run one admin panel action as ACTOR (an admin character, online or not); prints the answer line (JSON)
#   spectate NAME               the app's live view of a character (server/README.md "Live spectator"): queues "spectate
#                               NAME" (again after 5 s; the engine keeps a watch 20 s and writes remote.spectate every
#                               second), waits up to 8 s for a fresh snapshot of NAME and prints the one JSON line of
#                               server/tools/spectate_render.py (the 15 x 11 view drawn with the client pair as a base64
#                               PNG, name, level, health, mana, position; or ok false and an error). One at a time
#                               (busy: exit 75), at most one view every 0.8 s, the drawing stopped after 25 s
#   cast NAME                   the app's live view in real time (server/README.md "Live spectator", phase 2): queues
#                               "cast NAME" (the engine's cast port, src-patch 0064, mirrors that player), then runs
#                               server/tools/cast_relay.py in the foreground: JSON lines on stdout until stdin closes
#                               (the app's channel), stdout breaks or 30 minutes pass; "caststop" is queued at the end.
#                               One at a time (busy: exit 75). Needs castPort in config.lua (install_all.py step
#                               castport) or CHAOS_CAST_PORT, and the client pair of spectate
#   spectate-pair [status | fetch | fetch-now | log [N]]
#                               the client pair spectate draws with (CHAOS_SPECTATE_PAIR, default CHAOS_ROOT/pair, the same
#                               folder as the site's CHAOS_SPRITE_PAIR): status key=value lines; fetch takes the pair
#                               archive of CHAOS_PAIR_BRANCH (windows-assets: things/things-1098.tar.xz.part*, checked
#                               against SHA256SUMS.parts) in the background (fetch-now: in the foreground), unpacks only
#                               Tibia.dat and Tibia.spr into a new folder and swaps it in; log: the fetch log
#   update TAG now|at-save      chaos_update.sh --ref TAG (--now | --at-save) --yes, in the background (update-log)
#   rollback now|at-save        chaos_update.sh --rollback, in the background
#   update-log [N]              the last N lines of the update log
#   update-check                the Linux kit (CHAOS_KIT_DIR): what an update would bring, key=value lines (commits behind
#                               with their subjects, installed and newest winpkg-N release, client update, downloads, site)
#   update-apply [--no-client] [--no-downloads] [--no-site] [--no-map]
#                               the kit: chaos_kit_update.sh apply in the background (update-log): the branch
#                               CHAOS_UPDATE_BRANCH, the newest release's engine, the newest map master (CHAOS_MAP_BRANCH,
#                               server/README.md "Map master"), install_all.py, restart, checks, rollback on failure; then
#                               the client update, the site's download files and the site itself
#   update-downloads [--force]  the kit: only the site's client downloads (CHAOS_DL_DIR) from the newest release, in the
#                               background (update-log): no restart, no code change (chaos_kit_update.sh downloads).
#                               For a site whose download link still serves an older package than the published client
#                               update; nothing changes when the downloads are the newest release's (--force replaces)
#   update-status               the kit: running, status, result and time of the last update-apply / update-rollback
#   update-rollback             the kit: chaos_kit_update.sh rollback in the background (update-log)
#   xp-rate [show | set N | reset] [restart]
#                               the XP multiplier of config.lua (experienceStages = the release's stages x N, N 1..100);
#                               set / reset keep a backup and apply at the next restart, or at once with "restart".
#                               update-apply keeps it.
#   client-pair [show | set N] the client sprite pair the SHIPPED client is on (config.lua chaosClientPair, server/README.md
#                               "Client pair guard"): install_all.py installs the items of a newer pair (pickups: 55; fist
#                               weapons and the weapons above level 800: 56) only once this is N or more. set N after the
#                               client update with pair N is published, then update-apply (or install_all.py) installs them;
#                               a lower N is refused. Applies at the next install, no restart. show prints chaosClientPair=N|missing
#   beta-mode [status | on | off] [restart]
#                               beta test mode (server/README.md "Beta test mode"): the `enabled = ...` line of
#                               SERVER/data/scripts/chaos/beta_mode_config.lua (sed --follow-symlinks, backup .before-beta,
#                               checked afterwards). It lifts the weekly / daily gameplay limits (raid and guild boss
#                               lockouts, kill tasks, Candlemarks and faction weekly offers, honor and community caps,
#                               the dungeon cooldown); the store's weekly limits (real money) stay. Read at the start of the
#                               scripts: applies at the next restart, or at once with "restart"; "/reload scripts" as a god
#                               also works. update-apply keeps the switch. status prints beta_mode=on|off
#   clientservices-impl [status | rust | python]
#                               which program serves the login-screen services (chaos-clientservices, port 8090;
#                               server/README.md "Rust services (O153)"). python (default): server/tools/clientservices.py.
#                               rust: builds server/services/clientservices-rs with cargo (--locked, a temporary target
#                               folder) into CHAOS_ROOT/bin/clientservices-rs, adds the systemd drop-in 10-rust.conf and
#                               restarts the unit; a failed build changes nothing, a unit that does not stay up is put
#                               back on python. python: removes the drop-in and restarts. update-apply / chaos_update.sh
#                               rebuild the binary while the switch is on. status prints clientservices_impl=rust|python,
#                               binary=present|missing, unit=ACTIVE
#   backups                     the newest database dumps and data archives (date, size, path)
#   site-install                website/install_site.sh CHAOS_ENV CHAOS_SITE_ENV in the background (site-log)
#   areas-publish [--pictures] [--rotate]
#                               the map inbox (docs/MAP_GUIDE.md "Map inbox"): builds the editor files (.otbm, spawn xml,
#                               manifest) of every pending and approved entry of server/tools/areaplan/inbox/ with
#                               server/tools/area_inbox.py into CHAOS_DL_DIR/areas-TOKEN/ (list.txt and one folder per
#                               area) and prints url=... for the Windows fetch-areas.bat. TOKEN is 32 random hex digits
#                               kept in CHAOS_AREAS_STATE (mode 600): the folder is only reachable by that address (the
#                               site has no login for static files; map pieces hold no secret). --pictures adds the
#                               previews (needs numpy, Pillow and the sprite pair). --rotate makes a new TOKEN and
#                               deletes the old folder. The repo (CHAOS_REPO) must hold the entries: update-apply first
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
#   testers start [N] [MINUTES] [--restart SECONDS] [--keystones] [--checks]
#                               tester bots (server/README.md "Tester bots"): N characters "Tester Xxx" (default 100, at
#                               most 150) play for MINUTES (default 60, at most 1440), then stop by themselves. Copies the
#                               TEST ONLY helper into data/scripts; it loads at a server start, so without one since the
#                               copy the start is refused unless --restart SECONDS (restart with that countdown; the bots
#                               start 30 s after it). Never with clientGuardAllowDevKey = true; the client key comes only
#                               from CHAOS_TESTER_KEY (/etc/chaos/tester-client-key, root only, 0600). --keystones: every bot
#                               first tests the passive tree keystones and masteries of its class (O249: allocates them as
#                               a player does, checks the effect shows, says "not observable" where a client cannot see it,
#                               resets the tree; the per-node result is a section of testers report)
#                               --checks: every bot then runs the system checks of its class once (O110: summons and pets,
#                               party, rift, waystone atlas, reward and cursed chest, Auto setup list; a failure is a BUG
#                               line in testers report)
#   testers stop                ends the bots (they log out) and removes the helper from data/scripts
#   testers status              key=value lines: running, pid, started, bots, minutes, online (bots in game now),
#                               online_peak, logins, deaths, online_server (the helper's last console count), helper,
#                               helper_loaded
#   testers report              the bug report of the last run (server log since the run started, what the bots saw)
#   testers log [N]             the last N lines (default 200, at most 5000) of the newest run's activity log: every action
#                               of every tester, its outcome and every error, one line each ($TSTATE/runs/run-*.log;
#                               the run also writes its report next to it, run-*-report.txt; the 20 newest runs are kept)
#   testers cleanup [--yes]     lists (or with --yes deletes) the tester accounts, characters and every row of them;
#                               stops the bots first and waits 2 minutes after a stop (a character in a fight stays in game)
#   discord-set CHANNEL         a Discord webhook URL of CHANNEL (records, bosses, players, announce, status, bazaar, drops,
#                               default) into /etc/chaos/discord.env (CHAOS_DISCORD_ENV; mode 600, owner www-data). The URL
#                               is read from stdin (one line), never from the command line, checked against
#                               https://discord.com/api/webhooks/ID/TOKEN (also discordapp.com, canary., ptb.) and never
#                               printed (only the last 4 digits of the id). Empty input removes the channel. Adds
#                               CHAOS_SITE_URL from CHAOS_SITE_ENV when the file has none
#   discord-enable | discord-disable
#                               installs chaos-discord.service / .timer (and the logrotate file) from the repo when they
#                               are missing or differ, daemon-reload, enable --now (disable --now) chaos-discord.timer
#   discord-test [CHANNEL|all]  posts "Cinders of Chaos: teste do webhook CHANNEL" to each saved webhook (curl, the URL on
#                               its stdin) and prints CHANNEL=HTTP-code ok|fail (204 = ok); exit 1 when one fails
#   discord-status              key=value lines: channel_NAME=yes id_end=NNNN | no (never the URL), off_kinds, site_url,
#                               env_file (mode owner), timer_installed / _enabled / _active; "@log" the last worker log
#                               lines, "@queue" the last 10 rows of chaos_discord_queue (id kind status attempts error)
#   feedback [--days N] [--all] [--category C] [--names]
#                               the players' bug reports and suggestions (chaos_reports, reason bug) as plain text to paste
#                               into a chat, newest first (max 200): "#id | date UTC | category | open | pos x,y,z | lvl N
#                               class", the text indented below. Default: open ones of the last 30 days (--days 1 to 3650);
#                               --all adds closed ones (with the staff note); --category map|typo|technical|other|
#                               suggestion|all. Never prints account ids, IPs or e-mails; the character name only with
#                               --names. Control characters stripped, text capped (server/tools/feedback_format.py)
#   feedback-close ID [NOTE]    marks the open report ID closed with a staff note (200 characters; the note reaches the SQL
#                               as a hex literal); exit 1 "feedback-not-found" when it is not open
#   vps [info]                  key=value lines: host, os, kernel, uptime, load, cpus, mem_total_mb, mem_used_mb,
#                               disk_total_gb, disk_used_gb, disk_free_gb (of /), upgrades (packages, -1 unknown),
#                               php_upgrades (of them php*), php (the php*-fpm or libapache2-mod-php* package and its version),
#                               reboot_required, reboot_at (a planned reboot, empty when none)
#   vps upgrade                 apt-get update and upgrade in the background (config files kept),
#                               log CHAOS_VPS_LOG /var/log/chaos/vps-upgrade.log
#   vps upgrade-log [N]         the last N lines (default 60, at most 500) of that log
#   vps reboot MINUTES          reboots the machine in MINUTES (1 to 60): players are warned and the game is saved first
#   vps reboot-cancel           cancels a planned reboot
#   server-user [status]        key=value lines: the user the engine runs as (the unit's User= and the live process),
#                               runs_as_root, whether the chaos user, the folder owners and the database admin are ready,
#                               needs_fix, restart_needed. Changes nothing
#   server-user fix [--restart SECONDS]
#                               runs the game server as the system user chaos instead of root (the engine warns "executed
#                               as root user"): creates the user when missing, chowns only the writable server folders
#                               (kit: server/, database/, run/, logs/, crashes/ and chaos.env; repo layout: the server
#                               folder; never the repo checkout, which must stay root-owned), gives the kit's database
#                               its socket admin chaos, installs the unit of the layout the installed one has (the old unit is
#                               kept in CHAOS_SERVER_USER_STATE), systemd-analyze verify, daemon-reload, and puts the old unit
#                               back when a step fails. The engine keeps running as root until the unit restarts: --restart
#                               SECONDS (30 to 900) warns the players, stops, chowns again, starts and checks the new user
#                               (the old unit is back if it fails); without it, restart yourself (restart SECONDS)
#   server-user rollback        puts the newest kept unit back and daemon-reload (no restart)
#   server-user log [N]         the last N lines (default 60, at most 500) of the log of fix --restart
#   services                    every chaos-* unit, one per line: NAME ACTIVE ENABLED (timers too)
#   service NAME start|stop|restart
#                               a chaos-* unit (NAME like chaos-helpai or chaos-backup.timer); the game server too
#   service-log NAME [N]        the last N lines (default 60, at most 500) of that unit's log file (its
#                               StandardOutput=append: file) or of the journal
#
# Settings, defaults for the standard layout: CHAOS_UNIT chaos-server, CHAOS_ROOT /opt/chaos,
# CHAOS_SERVER_DIR $CHAOS_ROOT/server, CHAOS_REPO $CHAOS_ROOT/repo, CHAOS_ENV /etc/chaos/chaos.env,
# CHAOS_LOG /var/log/chaos/server.log, CHAOS_UPDATE_LOG /var/log/chaos/update.log, CHAOS_ADMIN_USER chaosadmin,
# CHAOS_PID_FILE $CHAOS_ROOT/run/server.pid (the engine's pid, written by the Linux kit's start-server.sh),
# CHAOS_DB_SOCKET (empty: TCP host/port of the env file), CHAOS_MYSQL (the client: mysql, mariadb or the kit's own),
# CHAOS_BACKUP_DIR (else the env file's, else /var/backups/chaos). For server-user: CHAOS_SERVER_USER_STATE
# /var/lib/chaos/server-user (the kept units), CHAOS_SERVER_USER_LOG /var/log/chaos/server-user.log. For publish-update: CHAOS_PUBLISH_LOG
# /var/log/chaos/publish-update.log and, passed on to publish_client_update.sh (its defaults when unset), CHAOS_SITE_DIR,
# CHAOS_UPDATE_KEY, CHAOS_UPDATE_PUBLIC, CHAOS_UPDATE_REPO, CHAOS_UPDATE_URL, CHAOS_WORK_DIR, and CHAOS_ENV (the update blobs are
# encrypted with its CHAOS_CLIENT_KEY, which publish_client_update.sh reads from there). For the kit's update-*:
# CHAOS_KIT_DIR (else CHAOS_ROOT when it holds start-server.sh), CHAOS_UPDATE_BRANCH main, CHAOS_RELEASE_REPO
# lucas1089/cinders-of-chaos, CHAOS_KIT_STATE /var/lib/chaos/kit-update, CHAOS_BOOT_TIMEOUT 900, CHAOS_STAGING 1 (0: the
# update installs with the server stopped), CHAOS_CACHE_DIR $CHAOS_KIT_STATE/cache (install_all.py's plan compile cache), CHAOS_DL_DIR
# $CHAOS_SITE_DIR/dl, CHAOS_SITE_ENV /etc/chaos/site.env; CHAOS_SITE_LOG /var/log/chaos/site-install.log. For areas-publish:
# CHAOS_AREAS_STATE /var/lib/chaos/areas (the token file), CHAOS_DL_DIR, CHAOS_SITE_ENV (CHAOS_SITE_URL). For testers:
# CHAOS_TESTER_KEY /etc/chaos/tester-client-key, CHAOS_TESTER_STATE /var/lib/chaos/testers, CHAOS_TESTER_LOG
# /var/log/chaos/testers.log. For vps: CHAOS_VPS_LOG /var/log/chaos/vps-upgrade.log. For spectate: CHAOS_SPECTATE_PAIR
# $CHAOS_ROOT/pair, CHAOS_SPECTATE_STATE /var/lib/chaos/spectate (lock, renewal time, the dat index), CHAOS_PAIR_BRANCH
# windows-assets, CHAOS_SPECTATE_LOG /var/log/chaos/spectate-pair.log. For cast: CHAOS_CAST_PORT (else castPort of
# the server's config.lua). For clientservices-impl: CHAOS_SYSTEMD_DIR /etc/systemd/system.
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
CHAOS_RELEASE_REPO CHAOS_KIT_STATE CHAOS_BOOT_TIMEOUT CHAOS_DL_DIR CHAOS_SITE_ENV CHAOS_SITE_LOG CHAOS_TESTER_KEY \
CHAOS_TESTER_STATE CHAOS_TESTER_LOG CHAOS_VPS_LOG CHAOS_SPECTATE_PAIR CHAOS_SPECTATE_STATE CHAOS_PAIR_BRANCH \
CHAOS_SPECTATE_LOG CHAOS_CAST_PORT CHAOS_SYSTEMD_DIR CHAOS_AREAS_STATE CHAOS_STAGING CHAOS_CACHE_DIR \
CHAOS_DISCORD_ENV CHAOS_DISCORD_LOG CHAOS_DISCORD_USER CHAOS_DISCORD_GROUP CHAOS_LOGROTATE_FILE \
CHAOS_SERVER_USER_STATE CHAOS_SERVER_USER_LOG "
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
TKEY=$(setting CHAOS_TESTER_KEY /etc/chaos/tester-client-key)
TSTATE=$(setting CHAOS_TESTER_STATE /var/lib/chaos/testers)
TLOG=$(setting CHAOS_TESTER_LOG /var/log/chaos/testers.log)
VLOG=$(setting CHAOS_VPS_LOG /var/log/chaos/vps-upgrade.log)
SPPAIR=$(setting CHAOS_SPECTATE_PAIR "$ROOT/pair")
SPSTATE=$(setting CHAOS_SPECTATE_STATE /var/lib/chaos/spectate)
SPBRANCH=$(setting CHAOS_PAIR_BRANCH windows-assets)
SPLOG=$(setting CHAOS_SPECTATE_LOG /var/log/chaos/spectate-pair.log)
SYSD=$(setting CHAOS_SYSTEMD_DIR /etc/systemd/system)
SUSTATE=$(setting CHAOS_SERVER_USER_STATE /var/lib/chaos/server-user)
SULOG=$(setting CHAOS_SERVER_USER_LOG /var/log/chaos/server-user.log)
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

# ---- server-user: the game server runs as the system user chaos, not root (the engine warns about root)
# the environment may name another user (tests); sudo drops it, so the app always gets chaos
SUSER=${CHAOS_SERVER_USER:-chaos}
if ! [[ $SUSER =~ ^[a-z_][a-z0-9_-]{0,30}$ ]] || [ "$SUSER" = root ]; then die "bad CHAOS_SERVER_USER"; fi
unit_prop() { systemctl show "$UNIT" -p "$1" --value 2>/dev/null || true; }
# systemd runs a unit without User= as root; a numeric 0 is root as well
unit_user() { local u; u=$(unit_prop User); case $u in ''|0) u=root ;; esac; printf '%s' "$u"; }
proc_user() { ps -o user:32= -p "$1" 2>/dev/null | tr -d ' ' || true; }
# the engine's pid, else the unit's main process
run_pid() {
  local p
  if p=$(engine_pid); then echo "$p"; return 0; fi
  p=$(unit_prop MainPID)
  num "$p" && [ "$p" != 0 ] && [ -d "/proc/$p" ] || return 1
  echo "$p"
}
sulog() { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }
# the unit file as installed; the layout it belongs to (kit: starts start-server.sh; repo: starts tfs itself)
su_layout_of() { if grep -q 'start-server\.sh' "$1" 2>/dev/null; then echo kit; else echo repo; fi; }
# the unit of the repository for this layout with User= and Group= set to chaos (and the kit folder if not /opt/chaos-trial)
su_render() {
  local src
  if [ -n "$KIT" ]; then src="$REPO/server/deploy/chaos-trial-server.service"; else src="$REPO/server/deploy/chaos-server.service"; fi
  [ -f "$src" ] || return 1
  if [ -n "$KIT" ]; then
    sed -e "s|/opt/chaos-trial|${KIT%/}|g" -e "s|^User=.*|User=$SUSER|" -e "s|^Group=.*|Group=$SUSER|" "$src"
  else
    sed -e "s|^User=.*|User=$SUSER|" -e "s|^Group=.*|Group=$SUSER|" "$src"
  fi
}
# the folders the service writes: everything else (the checkout, the binaries) stays root-owned
su_targets() {
  local d
  [ -d "$SERVER" ] && echo "$SERVER"
  if [ -n "$KIT" ]; then
    for d in database run logs crashes; do [ -d "${KIT%/}/$d" ] && echo "${KIT%/}/$d"; done
  fi
  return 0
}
su_envfile() { if [ -n "$KIT" ] && [ -f "$ENVFILE" ] && [ "$(dirname -- "$ENVFILE")" = "${KIT%/}" ]; then echo "$ENVFILE"; fi; return 0; }
# the checkout must stay root-owned: not owned by chaos, no write for group or others (the ExecStopPost guard of chaos-server.service)
su_repo_ok() {
  local p u g m
  for p in "$REPO" "$REPO/server" "$REPO/server/tools" "$REPO/server/deploy"; do
    [ -d "$p" ] || return 1
    read -r u g m < <(stat -L -c '%U %G %a' "$p") || return 1
    [ "$u" != "$SUSER" ] && [ "$g" != "$SUSER" ] && (( (8#$m & 8#022) == 0 )) || return 1
  done
  return 0
}
# 0 when the checkout and one of the folders to chown contain each other
su_overlap() {
  local r t
  r=$(readlink -f -- "$REPO")
  while IFS= read -r t; do
    t=$(readlink -f -- "$t")
    case "$r/" in "$t"/*) return 0 ;; esac
    case "$t/" in "$r"/*) return 0 ;; esac
  done
  return 1
}
su_foreign() {  # number of entries of the writable folders not owned by chaos (-1: the user does not exist yet)
  local t n=0 c
  getent passwd "$SUSER" >/dev/null 2>&1 || { echo -1; return 0; }
  while IFS= read -r t; do
    c=$(find "$t" -printf '%u\n' 2>/dev/null | grep -v -x -c -- "$SUSER" || true)
    n=$((n + c))
  done < <(su_targets)
  echo "$n"
}
su_chown() {
  local t f
  while IFS= read -r t; do
    chown -R -h "$SUSER:$SUSER" -- "$t" || return 1
  done < <(su_targets)
  f=$(su_envfile)
  [ -z "$f" ] || chown -h "$SUSER" -- "$f" || return 1
  return 0
}
su_db_sock() {
  local s=""
  [ -r "$KIT/run/socket.txt" ] && s=$(head -n 1 "$KIT/run/socket.txt" | tr -d '\r')
  printf '%s' "${s:-$KIT/run/mariadb.sock}"
}
# the database admin is the system user that first started the kit (the owner of database/, root for a root unit), over the
# socket (unix_socket authentication): run as that user
su_db_q() {
  local o
  o=$(stat -c %U "$KIT/database" 2>/dev/null) || return 1
  if [ "$o" = root ]; then
    "$MYSQL" --no-defaults --socket="$(su_db_sock)" -u root -N -B -e "$1"
  else
    runuser -u "$o" -- "$MYSQL" --no-defaults --socket="$(su_db_sock)" -u "$o" -N -B -e "$1"
  fi
}
# kit only: yes, no, unknown (database down) or n/a. The kit's start-server.sh is its own database admin over the socket.
su_db_admin() {
  local n
  [ -n "$KIT" ] || { echo n/a; return 0; }
  [ "$(stat -c %U "$KIT/database" 2>/dev/null)" = "$SUSER" ] && { echo yes; return 0; }
  n=$(su_db_q "SELECT COUNT(*) FROM mysql.user WHERE user='$SUSER' AND host='localhost' AND plugin='unix_socket'" 2>/dev/null) \
    || { echo unknown; return 0; }
  [ "$n" = 0 ] && echo no || echo yes
}
su_backups() { find "$SUSTATE" -maxdepth 1 -name "$UNIT.service.before-*" 2>/dev/null | sort; }
su_status() {
  local uuser ugroup p euser who ufile layout unitcur foreign owner repo db needs restart user_ok backup
  ufile="$SYSD/$UNIT.service"
  uuser=$(unit_user)
  ugroup=$(unit_prop Group)
  p=$(run_pid) || p=""
  euser=""
  [ -z "$p" ] || euser=$(proc_user "$p")
  who=${euser:-$uuser}
  layout=repo; [ -n "$KIT" ] && layout=kit
  unitcur=unknown
  if [ -f "$ufile" ] && su_render >/dev/null 2>&1; then
    if cmp -s "$ufile" <(su_render); then unitcur=yes; else unitcur=no; fi
  fi
  getent passwd "$SUSER" >/dev/null 2>&1 && user_ok=yes || user_ok=no
  foreign=$(su_foreign)
  owner=$(stat -c %U "$SERVER" 2>/dev/null || echo "")
  su_repo_ok && repo=yes || repo=no
  db=$(su_db_admin)
  backup=no; [ -n "$(su_backups)" ] && backup=yes
  needs=no
  { [ "$uuser" != "$SUSER" ] || [ "$user_ok" = no ] || [ "$foreign" != 0 ] || [ "$db" = no ]; } && needs=yes
  restart=no
  [ -n "$p" ] && [ "$euser" != "$SUSER" ] && restart=yes
  echo "unit=$UNIT"
  echo "layout=$layout"
  echo "unit_file=$ufile"
  echo "unit_user=$uuser"
  echo "unit_group=${ugroup:-root}"
  echo "unit_current=$unitcur"
  echo "engine_pid=$p"
  echo "engine_user=$euser"
  echo "runs_as_root=$([ "$who" = root ] && echo yes || echo no)"
  echo "target_user=$SUSER"
  echo "user_exists=$user_ok"
  echo "server_dir=$SERVER"
  echo "server_owner=$owner"
  echo "foreign_files=$foreign"
  echo "repo_root_owned=$repo"
  echo "db_admin=$db"
  echo "unit_backup=$backup"
  echo "needs_fix=$needs"
  echo "restart_needed=$restart"
}
# put the newest kept unit back (or the one named); the caller reloads
su_restore() {
  local ufile="$SYSD/$UNIT.service" b=${1:-}
  [ -n "$b" ] || b=$(su_backups | tail -n 1)
  [ -n "$b" ] && [ -f "$b" ] || return 1
  cp -p -- "$b" "$ufile.restore.$$" && mv -f -- "$ufile.restore.$$" "$ufile"
}
# fix --restart: the detached part. Warn, stop (the engine saves), chown again (files the root engine wrote meanwhile), start,
# check the new user; the old unit goes back if the engine does not come up as chaos.
su_restart_impl() {
  local secs=$1 b ok=0 p
  b=$(cat "$SUSTATE/pending-backup" 2>/dev/null || true)
  sulog "restart as $SUSER in $secs s (old unit kept as ${b:-none})"
  if [ "$secs" -gt 60 ]; then
    CHAOS_CTL_NO_SUDO=1 "$SELF" broadcast "The server restarts in $secs seconds. Please log out." >/dev/null 2>&1 || true
    sleep $((secs - 30))
    CHAOS_CTL_NO_SUDO=1 "$SELF" broadcast "The server restarts in 30 seconds. Please log out." >/dev/null 2>&1 || true
    sleep 30
  else
    CHAOS_CTL_NO_SUDO=1 "$SELF" broadcast "The server restarts in $secs seconds. Please log out." >/dev/null 2>&1 || true
    sleep "$secs"
  fi
  systemctl stop "$UNIT" || sulog "stop returned an error"
  if ! su_chown; then
    sulog "FAIL: chown after the stop failed; starting the old unit"
    su_restore "$b" && systemctl daemon-reload
    systemctl start "$UNIT"
    sulog "RESULT rolled-back: chown failed"
    return 1
  fi
  systemctl start "$UNIT" || sulog "start returned an error"
  for _ in $(seq 1 60); do
    if systemctl is-active --quiet "$UNIT" && p=$(run_pid) && [ "$(proc_user "$p")" = "$SUSER" ]; then ok=1; break; fi
    sleep 5
  done
  if [ "$ok" = 1 ]; then
    sulog "the server runs as $SUSER (pid $p)"
    sulog "RESULT ok: the server runs as $SUSER"
    return 0
  fi
  sulog "FAIL: the server did not come up as $SUSER in 300 s (systemctl status $UNIT; journalctl -u $UNIT -n 50)"
  if su_restore "$b"; then
    systemctl daemon-reload
    systemctl restart "$UNIT"
    sulog "RESULT rolled-back: the old unit is back and started (the server runs as root again)"
  else
    sulog "RESULT failed: no kept unit to put back"
  fi
  return 1
}
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
# the line "errors clear" appends to the log; the error list counts only what comes after it (no word the error
# filters match)
CLEAR_MARK="[chaos-ctl] list cleared by the owner"
error_report() {  # MODE (current|all) MAX SINCE (the unit's start time, the date of the newest run when its line has none)
  tail -n 20000 "$LOG" 2>/dev/null | awk -v mode="$1" -v max="$2" -v since="$3" -v MARK="$CLEAR_MARK" '
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
    function clear(   i, k) {
      for (i = 1; i <= n[nr]; i++) { k = nr SUBSEP ord[nr, i]; delete cnt[k]; delete last[k] }
      n[nr] = 0; clr = nr
    }
    function iserr(l) { return l ~ /Lua Script Error/ || tolower(l) ~ /error|exception|segfault/ }
    BEGIN { nr = 0; newrun("?"); cur = ""; join = 0; pend = 0; clr = 1 }
    {
      line = $0; sub(/\r$/, "", line)
      if (index(line, MARK) == 1) { flush(); clear(); next }
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
      first = (mode == "all") ? clr : nr
      older = 0
      for (r = clr; r < nr; r++) if (n[r] > 0) older++
      for (r = first; r <= nr; r++) {
        if (r == first && r < nr && n[r] == 0) continue
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

# a chaos-* unit name, as the owner may name it (chaos-helpai, chaos-backup.timer); the configured game unit too
# the chaos-* units, the game unit, and the web server units (restart after a PHP update)
WEB_UNITS='apache2 nginx'
unit_ok() {
  [[ $1 =~ ^chaos-[a-z0-9-]{1,40}(\.service|\.timer)?$ ]] || [ "$1" = "$UNIT" ] \
    || [[ $1 =~ ^(apache2|nginx|php[0-9.]{1,6}-fpm)(\.service)?$ ]]
}

# ---- Discord announcements (discord-* commands): CHAOS_DISCORD_WEBHOOK_<CHANNEL> lines of $DENV, mode 600
DENV=$(setting CHAOS_DISCORD_ENV /etc/chaos/discord.env)
DLOG=$(setting CHAOS_DISCORD_LOG /var/log/chaos/discord.log)
DUSER=$(setting CHAOS_DISCORD_USER www-data)
DGROUP=$(setting CHAOS_DISCORD_GROUP "$DUSER")
DLROT=$(setting CHAOS_LOGROTATE_FILE /etc/logrotate.d/chaos)
DISCORD_CHANNELS="records bosses players announce status bazaar drops default"
DISCORD_RE='^https://(discord\.com|discordapp\.com|canary\.discord\.com|ptb\.discord\.com)/api/webhooks/[0-9]{5,25}/[A-Za-z0-9_-]{20,100}$'
discord_channel_ok() { local c; for c in $DISCORD_CHANNELS; do [ "$c" = "$1" ] && return 0; done; return 1; }
# the URL of one channel from $DENV, only when it passes the same check as discord-set; else nothing
discord_url() {
  local up u
  up=$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')
  u=$(sed -n "s/^CHAOS_DISCORD_WEBHOOK_$up=//p" "$DENV" 2>/dev/null | head -n 1)
  u=${u%$'\r'}
  [[ $u =~ $DISCORD_RE ]] && printf '%s' "$u"
  return 0
}
discord_configured() { local c; for c in $DISCORD_CHANNELS; do [ -z "$(discord_url "$c")" ] || echo "$c"; done; }
# a webhook URL in a line of output shows its id only: the token is masked
discord_redact() { sed -E 's#(/api/webhooks/[0-9]+/)[A-Za-z0-9_-]+#\1***#g'; }
# $DENV exists (mode 600, owner www-data) and has CHAOS_SITE_URL (from the site's own setting) when it can
discord_prepare_env() {
  local real site senv
  real=$(readlink -m -- "$DENV") || return 1
  if [ ! -e "$real" ]; then
    install -d -m 0755 "$(dirname "$real")" || return 1
    install -m 600 -o "$DUSER" -g "$DGROUP" /dev/null "$real" || return 1
  fi
  chmod 0600 "$real" 2>/dev/null || true
  if ! grep -q '^CHAOS_SITE_URL=' "$real" 2>/dev/null; then
    senv=$(setting CHAOS_SITE_ENV /etc/chaos/site.env)
    site=$(sed -n 's/^CHAOS_SITE_URL=\([^ #]*\).*/\1/p' "$senv" 2>/dev/null | head -n 1)
    site=${site%/}
    if [[ $site =~ ^https?://[A-Za-z0-9.-]+(:[0-9]{1,5})?$ ]]; then
      # a hand-edited file may end without a newline: never glue the line onto the last webhook
      if [ -s "$real" ] && [ -n "$(tail -c 1 "$real")" ]; then echo >> "$real" || return 1; fi
      printf 'CHAOS_SITE_URL=%s\n' "$site" >> "$real" || return 1
    fi
  fi
  return 0
}

# ---- tester bots (server/README.md "Tester bots")
HELPER_FILES=(zz_tester_helper.lua zz_tester_helper_core.lua)
testers_pid() {
  local p
  [ -r "$TSTATE/run.pid" ] || return 1
  p=$(head -c 20 "$TSTATE/run.pid" | tr -dc 0-9)
  [ -n "$p" ] && kill -0 "$p" 2>/dev/null || return 1
  echo "$p"
}
# the version of the helper file in the repo (HELPER_VERSION in tester_helper.lua)
helper_version() {
  sed -n 's/^HELPER_VERSION = \([0-9][0-9]*\).*/\1/p' "$REPO/server/tools/tester_helper.lua" 2>/dev/null | head -n 1
}
# the helper of the repo's version printed "[tester-helper] running vN" after the newest server start in the log
# (an older copy prints no version, so a server that still runs it counts as not loaded)
helper_loaded() {
  local want
  want=$(helper_version)
  tail -n 50000 "$LOG" 2>/dev/null | awk -v want="$want" '
    /Starting the game server \(|Loading config/ { start = NR }
    index($0, "[tester-helper] running v" want " ") { run = NR }
    END { exit !(run > start) }'
}
dev_key_on() {
  [ -r "$SERVER/config.lua" ] && sed 's/--.*//' "$SERVER/config.lua" \
    | grep -Eqi '^[[:space:]]*clientGuardAllowDevKey[[:space:]]*=[[:space:]]*true'
}
# the client key file: a plain file of root (or the user running this), no rights for group or others
key_file_ok() {
  local meta
  if [ ! -f "$TKEY" ] || [ -L "$TKEY" ]; then
    # shellcheck disable=SC2016
    die "no client key file $TKEY. Create it as root (server/README.md \"Tester bots\"):" \
      'sudo bash -c '"'"'umask 077; read -rsp "client key: " K; echo; printf "%s\n" "$K" > '"$TKEY'"
  fi
  meta=$(stat -c '%u %a' "$TKEY") || die "cannot read $TKEY"
  [ "${meta% *}" = 0 ] || [ "${meta% *}" = "$(id -u)" ] || die "$TKEY is not owned by root"
  (( (8#${meta#* } & 8#077) == 0 )) || die "$TKEY is readable by group or others (chmod 600 $TKEY)"
}
remove_helper() {
  local f
  for f in "${HELPER_FILES[@]}"; do rm -f "$SERVER/data/scripts/$f"; done
}
# testers.py with the database settings of the env file (never on a command line)
testers_py() {
  local py="$REPO/server/tools/testers.py"
  [ -r "$py" ] || die "no $py"
  ( set -a; . "$ENVFILE"
    [ -n "$DBSOCK" ] && CHAOS_DB_SOCKET=$DBSOCK
    CHAOS_MYSQL=$MYSQL
    set +a; exec python3 -I "$py" "$@" )
}

# ---- live spectator (server/README.md "Live spectator")
SPTOOL="$REPO/server/tools/spectate_render.py"
# one JSON answer line for the app, then exit
sp_fail() { printf '{"ok":false,"error":"%s","message":"%s"}\n' "$1" "$2"; exit "${3:-1}"; }
sp_log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }
spg() { git -C "$REPO" -c safe.directory="$REPO" "$@"; }
# the state folder (lock, renewal time, the dat index), root only
sp_state() { { mkdir -p "$SPSTATE" && chmod 0700 "$SPSTATE"; } || die "cannot create $SPSTATE"; }
# the cast port: CHAOS_CAST_PORT, else the last castPort line of the server's config.lua (digits only)
cast_port() {
  local p
  p=$(setting CHAOS_CAST_PORT "")
  if [ -z "$p" ] && [ -r "$SERVER/config.lua" ]; then
    p=$(sed -n 's/^[[:space:]]*castPort[[:space:]]*=[[:space:]]*\([0-9]\{1,5\}\)[[:space:]]*\(--.*\)\{0,1\}$/\1/p' \
      "$SERVER/config.lua" | tail -n 1)
  fi
  printf '%s' "$p"
}
# the pair archive of SPBRANCH into SPPAIR (fetch-now; the background fetch runs this too)
pair_fetch() {
  local work p parts=()
  { [[ $SPBRANCH =~ ^[A-Za-z0-9][A-Za-z0-9._/-]{0,99}$ ]] && [[ $SPBRANCH != *..* ]]; } || die "bad CHAOS_PAIR_BRANCH"
  [ -r "$SPTOOL" ] || die "no $SPTOOL (CHAOS_REPO)"
  spg rev-parse --git-dir >/dev/null 2>&1 || die "no git checkout at $REPO (CHAOS_REPO)"
  sp_state
  exec 8> "$SPSTATE/fetch.lock"
  flock -n 8 || die "a pair fetch is running (chaos-ctl.sh spectate-pair log)"
  sp_log "fetching $SPBRANCH (shallow, without the contents of its other files)"
  spg fetch --quiet --depth=1 --filter=blob:none origin "+refs/heads/$SPBRANCH:refs/remotes/origin/$SPBRANCH" \
    || die "git fetch of $SPBRANCH failed (does the checkout's origin reach it?)"
  work=$(mktemp -d "$WORKDIR/chaos-pair.XXXXXX") || die "no work folder in $WORKDIR"
  spg cat-file blob "origin/$SPBRANCH:SHA256SUMS.parts" > "$work/SHA256SUMS.parts" \
    || { rm -rf "$work"; die "$SPBRANCH has no SHA256SUMS.parts"; }
  while IFS= read -r p; do
    [[ $p =~ ^things/things-1098\.tar\.xz\.part[A-Za-z0-9]{1,8}$ ]] || continue
    spg cat-file blob "origin/$SPBRANCH:$p" > "$work/${p#things/}" || { rm -rf "$work"; die "cannot read $p"; }
    parts+=("$work/${p#things/}")
  done < <(spg ls-tree --name-only "origin/$SPBRANCH" things/)
  [ ${#parts[@]} -gt 0 ] || { rm -rf "$work"; die "no things/things-1098.tar.xz.part* on $SPBRANCH"; }
  sp_log "${#parts[@]} part(s); checking the sums and unpacking Tibia.dat and Tibia.spr"
  rm -rf "$SPPAIR.new"
  if ! python3 -I "$SPTOOL" unpack-pair --sums "$work/SHA256SUMS.parts" --out "$SPPAIR.new" "${parts[@]}"; then
    rm -rf "$work" "$SPPAIR.new"; die "the pair archive was refused: nothing changed"
  fi
  rm -rf "$work" "$SPPAIR.old"
  if [ -d "$SPPAIR" ]; then mv "$SPPAIR" "$SPPAIR.old" || die "cannot move the old pair"; fi
  mv "$SPPAIR.new" "$SPPAIR" || die "cannot move the new pair into $SPPAIR"
  rm -rf "$SPPAIR.old"
  sp_log "the pair is in $SPPAIR; building the sprite index"
  python3 -I "$SPTOOL" index --dat "$SPPAIR/Tibia.dat" --cache-dir "$SPSTATE" || die "the index could not be built"
  sp_log "RESULT ok"
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
    ep=""; if p=$(run_pid); then ep=$(proc_user "$p"); fi
    echo "engine_user=$ep"
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
    if [ "${1:-}" = clear ]; then
      [ $# -eq 1 ] || die "errors clear"
      [ -w "$LOG" ] || die "cannot write the log $LOG"
      echo "$CLEAR_MARK $(date '+%F %T')" >> "$LOG"
      echo "error list cleared: errors shows only what comes after now (the log itself is kept)"
      exit 0
    fi
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
  metrics)
    # read-only: fixed query, no argument reaches the shell or the SQL
    mjson=()
    case "${1:-}" in '') ;; --json) mjson=(--json) ;; *) die "metrics [--json]" ;; esac
    [ $# -le 1 ] || die "metrics [--json]"
    mpy="$REPO/server/tools/progress_metrics.py"
    [ -r "$mpy" ] || die "no $mpy"
    command -v python3 >/dev/null 2>&1 || die "python3-not-found"
    mrc=0
    mrows=$(mysql_q "SELECT kind, k1, k2, n FROM chaos_progress_metrics ORDER BY kind, k1, k2" 2>&1) || mrc=$?
    if [ "$mrc" -ne 0 ]; then
      case $mrows in *"doesn't exist"*) merr=no-table ;; *) merr=database ;; esac
      python3 -I "$mpy" ${mjson[@]+"${mjson[@]}"} --error "$merr"
      exit 1
    fi
    printf '%s\n' "$mrows" | python3 -I "$mpy" ${mjson[@]+"${mjson[@]}"}
    ;;
  feedback)
    # players' bug reports and suggestions (chaos_reports, reason bug) as plain text for the owner and for Claude.
    # Read-only. The SQL holds only checked numbers and one fixed category word; no account id, IP or e-mail is read, and
    # the character name only with --names. server/tools/feedback_format.py strips control characters and caps lengths.
    fdays=30 fall=0 fcat="" fnames=0
    while [ $# -gt 0 ]; do
      case $1 in
        --days) shift; { num "${1:-}" && [ "$1" -ge 1 ] && [ "$1" -le 3650 ]; } || die "feedback --days N (1 to 3650)"
          fdays=$((10#$1)) ;;
        --all) fall=1 ;;
        --names) fnames=1 ;;
        --category) shift
          case ${1:-} in map|typo|technical|other|suggestion) fcat=$1 ;; all) fcat="" ;;
            *) die "feedback --category map|typo|technical|other|suggestion|all" ;; esac ;;
        *) die "feedback [--days N] [--all] [--category C] [--names]" ;;
      esac
      shift
    done
    fpy="$REPO/server/tools/feedback_format.py"
    [ -r "$fpy" ] || die "no $fpy"
    command -v python3 >/dev/null 2>&1 || die "python3-not-found"
    fwho="''"
    fnarg=()
    if [ "$fnames" = 1 ]; then fwho="reporter_name"; fnarg=(--names); fi
    fwhere="reason = 'bug' AND created_at >= UNIX_TIMESTAMP() - $fdays * 86400"
    [ "$fall" = 1 ] || fwhere="$fwhere AND status = 'open'"
    [ -z "$fcat" ] || fwhere="$fwhere AND note LIKE '[$fcat] %'"
    frows=$(mysql_q "SELECT id, created_at, note, pos_x, pos_y, pos_z, chat, status, staff_note, $fwho FROM chaos_reports WHERE $fwhere ORDER BY id DESC LIMIT 200") \
      || die "database-down: the reports could not be read (is the database up?)"
    printf '%s\n' "$frows" | python3 -I "$fpy" ${fnarg[@]+"${fnarg[@]}"}
    ;;
  feedback-close)
    # marks one bug report or suggestion closed with a staff note. The id is a checked number; the note reaches the SQL
    # only as a hex literal made from sanitised text, so no quote or backslash of it can matter.
    fid=${1:-}
    { num "$fid" && [ "${#fid}" -le 9 ]; } || die "feedback-close ID [NOTE]"
    shift
    command -v python3 >/dev/null 2>&1 || die "python3-not-found"
    fhex=$(printf '%s' "$*" | python3 -I -c '
import sys, unicodedata
s = sys.stdin.buffer.read().decode("utf-8", "replace")
s = "".join(c if c not in "\r\n\t" else " " for c in s)
s = "".join(c for c in s if unicodedata.category(c) not in ("Cc", "Cf", "Cs", "Co", "Cn"))
print(s.strip()[:200].encode("utf-8").hex())') || die "could not read the note"
    [[ $fhex =~ ^[0-9a-f]*$ ]] || die "bad note"
    fnote="''"
    [ -z "$fhex" ] || fnote="CONVERT(0x$fhex USING utf8mb4)"
    fres=$(mysql_q - <<< "UPDATE chaos_reports SET status = 'closed', closed_at = UNIX_TIMESTAMP(), closed_by = 'chaos-ctl', staff_note = $fnote WHERE id = $((10#$fid)) AND reason = 'bug' AND status = 'open'; SELECT ROW_COUNT();") \
      || die "database-down: the report could not be closed"
    [ "$fres" = 1 ] || die "feedback-not-found: no open bug report or suggestion #$((10#$fid))"
    echo "closed #$((10#$fid))"
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
  spectate)
    [ $# -eq 1 ] || die "spectate NAME"
    name=$1
    if ! [[ $name =~ ^[A-Za-z][A-Za-z\ \'-]{2,28}$ ]] || [[ $name == *' ' ]] || [[ $name == *'  '* ]]; then
      die "spectate NAME: a character name (letters, spaces, ' and -, 3 to 29 characters)"
    fi
    [ -d "$SERVER" ] || die "no server folder $SERVER"
    [ -r "$SPTOOL" ] || die "no $SPTOOL (CHAOS_REPO)"
    sp_state
    exec 9> "$SPSTATE/lock"
    flock -n 9 || sp_fail busy "another view is being drawn" 75
    # at most one view every 0.8 s
    last=$(head -c 20 "$SPSTATE/last" 2>/dev/null | tr -dc 0-9)
    now_ms=$(date +%s%3N)
    if [ -n "$last" ] && [ $((now_ms - last)) -ge 0 ] && [ $((now_ms - last)) -lt 800 ]; then
      sleep "0.$(printf '%03d' $((800 - (now_ms - last))))"
    fi
    date +%s%3N > "$SPSTATE/last"
    # the watch: a new line for a new name, else every 5 s (the engine keeps it 20 s)
    now=$(date +%s)
    prev=$(head -c 100 "$SPSTATE/watch" 2>/dev/null)
    pt=${prev%% *} pn=${prev#* }
    if ! num "$pt" || [ "$pn" != "$name" ] || [ $((now - pt)) -ge 5 ] || [ $((now - pt)) -lt 0 ]; then
      spool "spectate $name" >/dev/null
      printf '%s %s' "$now" "$name" > "$SPSTATE/watch"
    fi
    snap="$SERVER/remote.spectate"
    got=0
    for _ in $(seq 1 32); do
      if [ -r "$snap" ] && [ "$(stat -c %Y "$snap" 2>/dev/null || echo 0)" -ge $((now - 2)) ] \
          && grep -qF "\"watch\":\"$name\"" "$snap"; then
        got=1; break
      fi
      sleep 0.25
    done
    if [ "$got" = 0 ]; then
      rm -f "$SPSTATE/watch"
      sp_fail no-answer "no view in 8 s: is the server running (and spectate.lua loaded)?"
    fi
    timeout 25 python3 -I "$SPTOOL" render --dat "$SPPAIR/Tibia.dat" --spr "$SPPAIR/Tibia.spr" --snapshot "$snap" \
      --watch "$name" --max-age 5 --cache-dir "$SPSTATE"
    rc=$?
    [ "$rc" = 124 ] && sp_fail timeout "the drawing took over 25 s (the first one builds the sprite index: try again)"
    exit "$rc"
    ;;
  cast)
    [ $# -eq 1 ] || die "cast NAME"
    name=$1
    if ! [[ $name =~ ^[A-Za-z][A-Za-z\ \'-]{2,28}$ ]] || [[ $name == *' ' ]] || [[ $name == *'  '* ]]; then
      die "cast NAME: a character name (letters, spaces, ' and -, 3 to 29 characters)"
    fi
    [ -d "$SERVER" ] || die "no server folder $SERVER"
    CTOOL="$REPO/server/tools/cast_relay.py"
    [ -r "$CTOOL" ] || sp_fail no-tool "no $CTOOL (CHAOS_REPO)"
    port=$(cast_port)
    if ! num "$port" || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
      sp_fail cast-off "the cast port is off: castPort in config.lua (install_all.py step castport), then a restart"
    fi
    { [ -r "$SPPAIR/Tibia.dat" ] && [ -r "$SPPAIR/Tibia.spr" ]; } || sp_fail no-pair "no client pair in $SPPAIR (spectate-pair fetch)"
    sp_state
    exec 7> "$SPSTATE/cast.lock"
    flock -n 7 || sp_fail busy "another live view is running" 75
    spool "cast $name" >/dev/null
    trap '( spool caststop ) >/dev/null 2>&1 || true' EXIT
    trap 'exit 143' TERM HUP INT
    otb=()
    [ -r "$SERVER/data/items/items.otb" ] && otb=(--otb "$SERVER/data/items/items.otb")
    timeout 1830 python3 -I "$CTOOL" --port "$port" --dat "$SPPAIR/Tibia.dat" --spr "$SPPAIR/Tibia.spr" "${otb[@]}" \
      --name "$name" --max-seconds 1800
    exit $?
    ;;
  spectate-pair)
    sub=${1:-status}
    case $sub in
      status)
        [ $# -le 1 ] || die "spectate-pair status"
        [ -r "$SPTOOL" ] || die "no $SPTOOL (CHAOS_REPO)"
        echo "branch=$SPBRANCH"
        if [ -f "$SPSTATE/fetch.lock" ] && ! flock -n "$SPSTATE/fetch.lock" true; then echo "fetching=yes"; else echo "fetching=no"; fi
        python3 -I "$SPTOOL" info --dat "$SPPAIR/Tibia.dat" --spr "$SPPAIR/Tibia.spr" --cache-dir "$SPSTATE"
        ;;
      fetch)
        [ $# -eq 1 ] || die "spectate-pair fetch"
        [ -r "$SPTOOL" ] || die "no $SPTOOL (CHAOS_REPO)"
        if [ -f "$SPSTATE/fetch.lock" ] && ! flock -n "$SPSTATE/fetch.lock" true; then
          die "a pair fetch is running (chaos-ctl.sh spectate-pair log)"
        fi
        mkdir -p "$(dirname "$SPLOG")"
        : > "$SPLOG"
        setsid "$SELF" spectate-pair fetch-now >> "$SPLOG" 2>&1 < /dev/null &
        echo "started (the client pair of $SPBRANCH into $SPPAIR); follow it with: chaos-ctl.sh spectate-pair log"
        ;;
      fetch-now)
        [ $# -eq 1 ] || die "spectate-pair fetch-now"
        pair_fetch
        ;;
      log)
        [ $# -le 2 ] || die "spectate-pair log [N]"
        tail -n "$(lines_arg "${2:-60}")" "$SPLOG" 2>&1
        ;;
      *) die "spectate-pair [status | fetch | fetch-now | log [N]]" ;;
    esac
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
  update-check|update-apply|update-rollback|update-downloads)
    [ -n "$KIT" ] || die "kit-not-found: update-check / update-apply are for the Linux kit (set CHAOS_KIT_DIR in $CONF)"
    kup="$REPO/server/deploy/chaos_kit_update.sh"
    [ -x "$kup" ] || die "no $kup (CHAOS_REPO)"
    kargs=()
    if [ "$cmd" = update-apply ]; then
      for a in "$@"; do
        case $a in
          --no-client|--no-downloads|--no-site|--no-map) kargs+=("$a") ;;
          *) die "update-apply [--no-client] [--no-downloads] [--no-site] [--no-map]" ;;
        esac
      done
    elif [ "$cmd" = update-downloads ]; then
      for a in "$@"; do
        case $a in
          --force) kargs+=("$a") ;;
          *) die "update-downloads [--force]" ;;
        esac
      done
    else
      [ $# -eq 0 ] || die "$cmd takes no arguments"
    fi
    kenv=("CHAOS_REPO=$REPO" "CHAOS_KIT_DIR=$KIT" "CHAOS_SERVER_DIR=$SERVER" "CHAOS_ENV=$ENVFILE" "CHAOS_UNIT=$UNIT"
      "CHAOS_LOG=$LOG" "CHAOS_MYSQL=$MYSQL" "CHAOS_KIT_STATE=$KSTATE" "CHAOS_WORK_DIR=$WORKDIR")
    for k in CHAOS_UPDATE_BRANCH CHAOS_RELEASE_REPO CHAOS_BOOT_TIMEOUT CHAOS_SITE_DIR CHAOS_DL_DIR CHAOS_SITE_ENV \
      CHAOS_MAP_BRANCH CHAOS_MAP_BACKUP_DIR CHAOS_STAGING CHAOS_CACHE_DIR \
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
    [ "$cmd" = update-downloads ] && sub=downloads
    setsid env "${kenv[@]}" "$kup" "$sub" "${kargs[@]}" >> "$ULOG" 2>&1 < /dev/null &
    if [ "$cmd" = update-apply ] && [ "$(unit_user)" = root ]; then
      echo "warning: the unit $UNIT runs the server as root (the engine warns about it): chaos-ctl.sh server-user fix" >&2
    fi
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
  client-pair)
    tool="$REPO/server/tools/client_pair.py"
    [ -f "$tool" ] || die "no $tool (CHAOS_REPO)"
    [ -f "$SERVER/config.lua" ] || die "no $SERVER/config.lua (CHAOS_SERVER_DIR)"
    case ${1:-show}:$# in
      show:0|show:1) exec python3 -I "$tool" show "$SERVER" ;;
      set:2) { num "$2" && [ "${#2}" -le 3 ]; } || die "client-pair set N (the pair number, 1..999)"
             exec python3 -I "$tool" set "$SERVER" "$2" ;;
      *) die "client-pair [show | set N]" ;;
    esac
    ;;
  beta-mode)
    bcfg="$SERVER/data/scripts/chaos/beta_mode_config.lua"
    [ -f "$bcfg" ] || die "no $bcfg (CHAOS_SERVER_DIR; run install_all.py)"
    bpat='^([[:space:]]*enabled[[:space:]]*=[[:space:]]*)(true|false)'
    beta_now() {
      sed -n -E "s/$bpat.*/\2/p" "$bcfg" | head -n 1
    }
    sub=${1:-status}
    again=0
    case $sub in
      status)
        [ $# -le 1 ] || die "beta-mode status"
        cur=$(beta_now)
        [ -n "$cur" ] || die "no 'enabled = true|false' line in $bcfg"
        if [ "$cur" = true ]; then echo "beta_mode=on"; else echo "beta_mode=off"; fi
        echo "file=$bcfg"
        exit 0
        ;;
      on|off)
        case $#:${2:-} in 1:) ;; 2:restart) again=1 ;; *) die "beta-mode on|off [restart]" ;; esac
        want=true
        [ "$sub" = on ] || want=false
        cur=$(beta_now)
        [ -n "$cur" ] || die "no 'enabled = true|false' line in $bcfg"
        if [ "$cur" = "$want" ]; then
          echo "beta_mode=$sub (unchanged)"
        else
          cp -p "$bcfg" "$bcfg.before-beta" || die "cannot back up $bcfg"
          sed --follow-symlinks -i -E "0,/$bpat/s//\1$want/" "$bcfg" || die "sed failed on $bcfg"
          if [ "$(beta_now)" != "$want" ]; then
            cp -p "$bcfg.before-beta" "$bcfg"
            die "the edit did not take; $bcfg restored"
          fi
          echo "beta_mode=$sub"
        fi
        ;;
      *) die "beta-mode [status | on | off] [restart]" ;;
    esac
    if [ "$again" = 1 ]; then
      need_unit
      systemctl restart "$UNIT" && echo "restarted ($(systemctl is-active "$UNIT" 2>/dev/null))"
    else
      echo "applies at the next restart (or /reload scripts as a god)"
    fi
    ;;
  clientservices-impl)
    csunit=chaos-clientservices
    csdrop="$SYSD/$csunit.service.d/10-rust.conf"
    csbin="$ROOT/bin/clientservices-rs"
    csbuild="$REPO/server/services/clientservices-rs/build.sh"
    cs_restart() {
      systemctl daemon-reload && systemctl restart "$csunit"
    }
    cs_back() {  # remove the drop-in, back on python
      rm -f "$csdrop"
      rmdir "$SYSD/$csunit.service.d" 2>/dev/null || true
    }
    sub=${1:-status}
    [ $# -le 1 ] || die "clientservices-impl [status | rust | python]"
    case $sub in
      status)
        if [ -f "$csdrop" ]; then echo "clientservices_impl=rust"; else echo "clientservices_impl=python"; fi
        if [ -x "$csbin" ]; then echo "binary=present"; else echo "binary=missing"; fi
        echo "unit=$(systemctl is-active "$csunit" 2>/dev/null || true)"
        exit 0
        ;;
      rust|rebuild)
        [ "$(systemctl show "$csunit" -p LoadState --value 2>/dev/null)" = loaded ] ||
          die "unit-not-found: $csunit is not installed (server/deploy/chaos-clientservices.service)"
        [ -f "$csbuild" ] || die "no $csbuild (CHAOS_REPO; the checkout must be at a release with the Rust crate)"
        if [ "$sub" = rebuild ]; then
          [ -f "$csdrop" ] || { echo "clientservices_impl=python (nothing to rebuild)"; exit 0; }
        fi
        # build first: a failed build changes nothing and the unit keeps running on python
        bash "$csbuild" "$csbin" || die "the Rust build failed (cargo needed on this machine); nothing changed"
        if [ ! -f "$csdrop" ]; then
          mkdir -p "$SYSD/$csunit.service.d" || die "cannot create $SYSD/$csunit.service.d"
          if ! printf '%s\n' \
            "# written by chaos-ctl.sh clientservices-impl rust; clientservices-impl python removes it" \
            "[Service]" "ExecStart=" \
            "ExecStart=$csbin $SERVER/data/chaos_clientservices.json --host 0.0.0.0 --port 8090" > "$csdrop.new"; then
            die "cannot write $csdrop"
          fi
          mv -f "$csdrop.new" "$csdrop" || die "cannot write $csdrop"
        fi
        cs_restart || { cs_back; cs_restart || true; die "the unit did not restart on the Rust binary; back on python"; }
        sleep "${CHAOS_CS_SETTLE:-2}"
        if ! systemctl is-active --quiet "$csunit"; then
          cs_back
          cs_restart || true
          die "the Rust binary did not stay up; back on python (see: chaos-ctl.sh service-log $csunit)"
        fi
        echo "clientservices_impl=rust"
        ;;
      python)
        if [ -f "$csdrop" ]; then
          cs_back
          if [ "$(systemctl show "$csunit" -p LoadState --value 2>/dev/null)" = loaded ]; then cs_restart || die "restart failed"; fi
        fi
        echo "clientservices_impl=python"
        ;;
      *) die "clientservices-impl [status | rust | python]" ;;
    esac
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
  areas-publish)
    apics=0 arot=0
    for a in "$@"; do
      case $a in
        --pictures) apics=1 ;;
        --rotate) arot=1 ;;
        *) die "areas-publish [--pictures] [--rotate]" ;;
      esac
    done
    atool="$REPO/server/tools/area_inbox.py"
    [ -f "$atool" ] || die "no $atool (CHAOS_REPO): update the server's repo first (update-apply)"
    command -v python3 >/dev/null 2>&1 || die "python3-not-found"
    adl=$(setting CHAOS_DL_DIR "$(setting CHAOS_SITE_DIR /var/www/chaos)/dl")
    [ -d "$adl" ] || die "no download folder $adl (CHAOS_DL_DIR)"
    astate=$(setting CHAOS_AREAS_STATE /var/lib/chaos/areas)
    mkdir -p "$astate" || die "cannot create $astate"
    chmod 0700 "$astate" 2>/dev/null || true
    atok=""
    [ -r "$astate/token" ] && atok=$(tr -dc 'a-f0-9' < "$astate/token" | head -c 32)
    aold=$atok
    if [ "${#atok}" -ne 32 ] || [ "$arot" -eq 1 ]; then
      atok=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
      [ "${#atok}" -eq 32 ] || die "no random bytes for the token"
      ( umask 077; printf '%s\n' "$atok" > "$astate/token" ) || die "cannot write $astate/token"
    fi
    atmp=$(mktemp -d "$adl/.areas-new.XXXXXX") || die "cannot write in $adl"
    aargs=()
    if [ "$apics" -eq 1 ]; then
      aass=$(mktemp -d "$WORKDIR/chaos-areas-assets.XXXXXX") || die "no work folder $WORKDIR"
      for f in items.otb items.xml; do ln -s "$SERVER/data/items/$f" "$aass/$f"; done
      for f in Tibia.dat Tibia.spr; do ln -s "$SPPAIR/$f" "$aass/$f"; done
      aargs+=(--assets "$aass")
    fi
    aout=$(python3 -I "$atool" publish "$atmp" "${aargs[@]}" 2>&1); arc=$?
    [ -z "${aass:-}" ] || rm -rf "$aass"
    printf '%s\n' "$aout"
    if [ "$arc" -ne 0 ]; then
      rm -rf "$atmp"
      die "areas-publish: area_inbox.py failed (exit $arc); the published folder is unchanged"
    fi
    chmod 0755 "$atmp"
    find "$atmp" -type d -exec chmod 0755 {} + 2>/dev/null
    find "$atmp" -type f -exec chmod 0644 {} + 2>/dev/null
    adest="$adl/areas-$atok"
    if [ -d "$adest" ]; then mv "$adest" "$atmp.old" && rm -rf "$atmp.old"; fi
    mv "$atmp" "$adest" || die "cannot move the folder into place"
    if [ "$arot" -eq 1 ] && [ "${#aold}" -eq 32 ] && [ "$aold" != "$atok" ]; then rm -rf "$adl/areas-$aold"; fi
    asite=""
    asenv=$(setting CHAOS_SITE_ENV /etc/chaos/site.env)
    [ -r "$asenv" ] && asite=$(sed -n 's/^CHAOS_SITE_URL=\([^ #]*\).*/\1/p' "$asenv" | head -n 1)
    echo "areas-published: $(grep -c . "$adest/list.txt" 2>/dev/null || echo 0) area(s)"
    if [ -n "$asite" ]; then
      echo "url=${asite%/}/dl/areas-$atok/"
    else
      echo "url=(CHAOS_SITE_URL is not in $asenv) the folder is $adest: the site's address + /dl/areas-$atok/"
    fi
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
  discord-set|discord-enable|discord-disable|discord-test|discord-status)
    # Discord announcements (docs/LAUNCH.md "Discord announcements"). The webhook URLs live only in $DENV (mode 600,
    # owner www-data). They are read from stdin, never put on a command line, never printed (not even in an error).
    case $cmd in
      discord-set)
        dch=${1:-}
        { [ $# -eq 1 ] && discord_channel_ok "$dch"; } \
          || die "discord-set CHANNEL (one of: $DISCORD_CHANNELS; the webhook URL on stdin, empty removes it)"
        durl=""
        IFS= read -r -t 30 -n 400 durl; drc=$?
        [ "$drc" -le 128 ] || die "no webhook URL on stdin (timed out)"
        durl=${durl%$'\r'}
        # one line only: more text after it is refused, so nothing else can ride along
        dx=""
        if IFS= read -r -t 2 -n 1 dx && [ -n "$dx" ]; then unset durl; die "one line only on stdin; nothing changed"; fi
        durl=${durl#"${durl%%[![:space:]]*}"}
        durl=${durl%"${durl##*[![:space:]]}"}
        if [ -n "$durl" ] && ! [[ $durl =~ $DISCORD_RE ]]; then
          unset durl
          die "that is not a Discord webhook URL (https://discord.com/api/webhooks/ID/TOKEN); nothing changed"
        fi
        discord_prepare_env || die "cannot prepare $DENV"
        # one writer at a time: two quick saves of different channels must not drop each other's line
        exec 9<"$(dirname -- "$(readlink -m -- "$DENV")")" || die "cannot lock $DENV"
        flock -w 10 9 || die "another discord-set is running; try again"
        dkey="CHAOS_DISCORD_WEBHOOK_$(printf '%s' "$dch" | tr '[:lower:]' '[:upper:]')"
        dreal=$(readlink -m -- "$DENV")
        dtmp=$(mktemp "$dreal.XXXXXX") || die "cannot write next to $DENV"
        chmod 0600 "$dtmp"
        { grep -v -- "^$dkey=" "$dreal" 2>/dev/null || true
          if [ -n "$durl" ]; then printf '%s=%s\n' "$dkey" "$durl"; fi; } > "$dtmp" \
          || { rm -f "$dtmp"; die "cannot write $DENV"; }
        chown --reference="$dreal" -- "$dtmp" 2>/dev/null || chown "$DUSER:$DGROUP" -- "$dtmp" 2>/dev/null || true
        mv -f -- "$dtmp" "$dreal" || { rm -f "$dtmp"; die "cannot replace $DENV"; }
        if [ -n "$durl" ]; then
          did=${durl#*/api/webhooks/}; did=${did%%/*}
          unset durl
          echo "discord-set: $dch saved (webhook id ending ${did: -4}); the timer posts within a minute once it is enabled"
        else
          echo "discord-set: $dch removed"
        fi
        ;;
      discord-enable|discord-disable)
        [ $# -eq 0 ] || die "$cmd (no arguments)"
        if [ "$cmd" = discord-disable ]; then
          systemctl disable --now chaos-discord.timer >/dev/null 2>&1 || die "could not disable chaos-discord.timer"
          echo "discord-disable: chaos-discord.timer is off (the webhooks stay saved; the game keeps queueing)"
          exit 0
        fi
        dsite=$(setting CHAOS_SITE_DIR /var/www/chaos)
        [ -f "$dsite/plugins/chaos/discord_worker.php" ] \
          || die "site-not-installed: $dsite/plugins/chaos/discord_worker.php is missing (run site-install first)"
        [ -d "$REPO/server/deploy" ] || die "no repository checkout at $REPO (update-apply first)"
        discord_prepare_env || die "cannot prepare $DENV"
        install -d -m 0755 "$(dirname "$DLOG")" || die "cannot create $(dirname "$DLOG")"
        dchanged=0
        for dsrc in chaos-discord.service chaos-discord.timer; do
          [ -f "$REPO/server/deploy/$dsrc" ] || die "missing $REPO/server/deploy/$dsrc"
          if ! cmp -s "$REPO/server/deploy/$dsrc" "$SYSD/$dsrc"; then
            install -m 0644 "$REPO/server/deploy/$dsrc" "$SYSD/$dsrc" || die "cannot install $dsrc"
            dchanged=1
          fi
        done
        # the logrotate file also rotates discord.log (docs/LAUNCH.md)
        if [ -f "$REPO/server/deploy/chaos.logrotate" ] && ! cmp -s "$REPO/server/deploy/chaos.logrotate" "$DLROT"; then
          install -m 0644 "$REPO/server/deploy/chaos.logrotate" "$DLROT" || die "cannot install $DLROT"
        fi
        [ "$dchanged" -eq 0 ] || systemctl daemon-reload || die "daemon-reload failed"
        systemctl enable --now chaos-discord.timer >/dev/null 2>&1 || die "could not enable chaos-discord.timer"
        dn=$(discord_configured | wc -l)
        echo "discord-enable: chaos-discord.timer is on (units installed: $([ "$dchanged" -eq 1 ] && echo updated || echo already), channels with a webhook: $dn)"
        [ "$dn" -gt 0 ] || echo "note: no webhook saved yet (discord-set CHANNEL); the queue waits until there is one"
        ;;
      discord-test)
        dwant=${1:-all}
        { [ $# -le 1 ] && { [ "$dwant" = all ] || discord_channel_ok "$dwant"; }; } \
          || die "discord-test [CHANNEL|all] (CHANNEL: $DISCORD_CHANNELS)"
        command -v curl >/dev/null 2>&1 || die "curl-not-found: install curl"
        dfail=0; dsent=0
        for dch in $DISCORD_CHANNELS; do
          [ "$dwant" = all ] || [ "$dwant" = "$dch" ] || continue
          durl=$(discord_url "$dch")
          if [ -z "$durl" ]; then
            [ "$dwant" = all ] || { echo "$dch=not-configured"; dfail=1; }
            continue
          fi
          [ "$dsent" -eq 0 ] || sleep 1
          dsent=$((dsent + 1))
          # the URL goes to curl on stdin as a config line: it never shows in ps
          dcode=$(printf 'url = "%s"\n' "$durl" | curl -K - -sS -o /dev/null -w '%{http_code}' --max-time 15 \
            -H 'Content-Type: application/json' \
            -d "{\"content\":\"Cinders of Chaos: teste do webhook $dch\"}" 2>/dev/null) || dcode=${dcode:-000}
          unset durl
          if [ "$dcode" = 204 ]; then echo "$dch=204 ok"; else echo "$dch=${dcode:-000} fail"; dfail=1; fi
        done
        [ "$dsent" -gt 0 ] || { echo "no webhook saved (discord-set CHANNEL)"; exit 1; }
        [ "$dfail" -eq 0 ] || exit 1
        ;;
      discord-status)
        [ $# -eq 0 ] || die "discord-status (no arguments)"
        for dch in $DISCORD_CHANNELS; do
          durl=$(discord_url "$dch")
          if [ -n "$durl" ]; then
            did=${durl#*/api/webhooks/}; did=${did%%/*}
            echo "channel_$dch=yes id_end=${did: -4}"
          else
            echo "channel_$dch=no"
          fi
        done
        unset durl
        doff=$(sed -n 's/^CHAOS_DISCORD_OFF=\([A-Za-z0-9_,]\{0,200\}\)[[:space:]]*$/\1/p' "$DENV" 2>/dev/null | head -n 1)
        echo "off_kinds=$doff"
        dsu=$(sed -n 's/^CHAOS_SITE_URL=\([^ #]*\).*/\1/p' "$DENV" 2>/dev/null | head -n 1)
        echo "site_url=$dsu"
        if [ -e "$DENV" ]; then echo "env_file=$(stat -c '%a %U:%G' "$DENV" 2>/dev/null)"; else echo "env_file=missing"; fi
        if [ -f "$SYSD/chaos-discord.timer" ]; then echo timer_installed=yes; else echo timer_installed=no; fi
        echo "timer_enabled=$(systemctl is-enabled chaos-discord.timer 2>/dev/null || echo disabled)"
        echo "timer_active=$(systemctl is-active chaos-discord.timer 2>/dev/null || echo inactive)"
        echo "@log"
        if [ -r "$DLOG" ]; then tail -n 8 "$DLOG" 2>/dev/null | discord_redact; else echo "(no $DLOG yet)"; fi
        echo "@queue"
        if dq=$(mysql_q "SELECT id, kind, status, attempts, LEFT(error, 120) FROM chaos_discord_queue ORDER BY id DESC LIMIT 10" 2>/dev/null); then
          printf '%s\n' "$dq" | discord_redact
        else
          echo "(the queue could not be read: is the database up?)"
        fi
        ;;
    esac
    ;;
  server-user)
    sub=${1:-status}
    [ $# -gt 0 ] && shift
    case $sub in
      status)
        [ $# -eq 0 ] || die "server-user status"
        need_unit
        su_status
        ;;
      log)
        [ $# -le 1 ] || die "server-user log [N]"
        [ -f "$SULOG" ] || { echo "(no log yet: $SULOG)"; exit 0; }
        tail -n "$(lines_arg "${1:-60}")" "$SULOG" 2>&1
        ;;
      rollback)
        [ $# -eq 0 ] || die "server-user rollback"
        need_unit
        su_restore || die "no-backup: no kept unit in $SUSTATE"
        systemctl daemon-reload
        echo "the old unit is back ($(su_backups | tail -n 1)); the server keeps its user until the next restart"
        echo "RESULT ok: restart the server to run it as before (restart SECONDS)"
        ;;
      fix)
        again=0
        case $#:${1:-} in
          0:) ;;
          2:--restart)
            again=$2
            { num "$again" && [ "${#again}" -le 3 ] && [ "$again" -ge 30 ] && [ "$again" -le 900 ]; } \
              || die "server-user fix --restart SECONDS (30 to 900)"
            ;;
          *) die "server-user fix [--restart SECONDS]" ;;
        esac
        need_unit
        ufile="$SYSD/$UNIT.service"
        { [ -f "$ufile" ] && [ ! -L "$ufile" ]; } || die "unit-file-not-found: $ufile is not a plain file (CHAOS_SYSTEMD_DIR, CHAOS_UNIT)"
        mkdir -p "$SUSTATE" || die "cannot create $SUSTATE"
        chmod 0700 "$SUSTATE"
        exec 8>"$SUSTATE/.lock"
        flock -n 8 || die "server-user-running: another server-user fix is running"
        # the layout is the installed unit's: the wrong unit stops the server, so a settings mismatch stops here
        have=$(su_layout_of "$ufile"); want=repo; [ -n "$KIT" ] && want=kit
        [ "$have" = "$want" ] \
          || die "layout-mismatch: $ufile starts the $have layout, the settings (CHAOS_KIT_DIR / CHAOS_ROOT in $CONF) say $want; nothing changed"
        if [ "$want" = repo ] && [ "${ROOT%/}" != /opt/chaos ]; then
          die "layout-unsupported: the repo unit is written for /opt/chaos, not $ROOT; install it by hand (server/README.md, Server user)"
        fi
        su_render >/dev/null || die "no-unit-template: $REPO/server/deploy has no unit for the $want layout (CHAOS_REPO)"
        su_repo_ok || die "repo-not-root-owned: $REPO, server/, server/tools or server/deploy is owned by $SUSER or writable by group or others; fix that first (chown root:root, chmod go-w). Nothing changed"
        [ -d "$SERVER" ] || die "no server folder $SERVER"
        while IFS= read -r t; do
          [ ! -L "$t" ] || die "a symbolic link in the way: $t; nothing changed"
        done < <(su_targets)
        if su_targets | su_overlap; then die "the checkout $REPO and a folder to chown contain each other; nothing changed"; fi
        if [ "$want" = kit ]; then
          km=$(stat -c %a "$KIT" 2>/dev/null || echo 0)
          (( (8#$km & 1) != 0 )) || die "kit-not-traversable: $KIT is mode $km; $SUSER cannot enter it (chmod o+x $KIT)"
        fi
        uuser=$(unit_user)
        changed=no
        # 0. the new unit, rendered and verified before anything is touched
        vdir=$(mktemp -d "$SUSTATE/verify.XXXXXX") || die "cannot create a folder in $SUSTATE"
        trap 'rm -rf "$vdir"' EXIT
        tmpu="$vdir/$UNIT.service"
        su_render > "$tmpu" || die "cannot render the unit"
        if command -v systemd-analyze >/dev/null 2>&1; then
          vout=$(systemd-analyze verify "$tmpu" 2>&1); vrc=$?
          vout=$(printf '%s\n' "$vout" | grep -v -E 'Failed to create|Access denied|^$' || true)
          if [ "$vrc" -ne 0 ] && [ -n "$vout" ]; then
            printf '%s\n' "$vout" | head -n 5 >&2
            die "unit-verify-failed: systemd-analyze verify refused the new unit; nothing changed"
          fi
        else
          echo "unit: systemd-analyze is not installed, the new unit is not verified" >&2
        fi
        # 1. the system user
        if getent passwd "$SUSER" >/dev/null 2>&1; then
          [ "$(id -u "$SUSER" 2>/dev/null || echo 1)" != 0 ] || die "user $SUSER has uid 0; refused"
          echo "user: $SUSER exists"
        else
          getent group "$SUSER" >/dev/null 2>&1 && gopt=(--gid "$SUSER") || gopt=(--user-group)
          useradd --system "${gopt[@]}" --home-dir /var/lib/chaos --no-create-home --shell /usr/sbin/nologin "$SUSER" \
            || die "cannot create the user $SUSER; nothing else changed"
          echo "user: $SUSER created"
          changed=yes
        fi
        # 2. the kit's database: its admin is the system user the server runs as (start-server.sh, unix_socket)
        if [ "$want" = kit ]; then
          dbs=$(su_db_admin)
          case $dbs in
            yes) echo "database: socket admin $SUSER already there" ;;
            unknown)
              command -v "$MYSQL" >/dev/null 2>&1 || die "mysql-not-found: no database client $MYSQL (set CHAOS_MYSQL in $CONF); nothing changed"
              die "database-down: the kit's database does not answer on its socket $(su_db_sock); start the server first (it runs as the old user now). Nothing changed" ;;
            *)
              su_db_q "CREATE USER IF NOT EXISTS '$SUSER'@'localhost' IDENTIFIED VIA unix_socket;
                ALTER USER '$SUSER'@'localhost' IDENTIFIED VIA unix_socket;
                GRANT ALL PRIVILEGES ON *.* TO '$SUSER'@'localhost' WITH GRANT OPTION;" >/dev/null \
                || die "cannot give the database admin to $SUSER; nothing else changed"
              echo "database: socket admin $SUSER ready"
              changed=yes ;;
          esac
        fi
        # 3. the writable folders
        foreign=$(su_foreign)
        if [ "$foreign" != 0 ] || [ "$uuser" != "$SUSER" ]; then
          su_chown || die "chown failed; nothing else changed (root can still run the server)"
          echo "folders owned by $SUSER: $(su_targets | tr '\n' ' ')$(su_envfile)"
          changed=yes
        else
          echo "folders: already owned by $SUSER"
        fi
        # 4. the unit
        if [ "$uuser" = "$SUSER" ]; then
          echo "unit: User=$SUSER already, left as it is"
          rm -f "$SUSTATE/pending-backup"
        else
          bak="$SUSTATE/$UNIT.service.before-$(date +%Y%m%d-%H%M%S)"
          cp -p -- "$ufile" "$bak" || die "cannot keep the old unit in $SUSTATE"
          printf '%s\n' "$bak" > "$SUSTATE/pending-backup"
          if ! cp -- "$tmpu" "$ufile.new.$$" || ! chmod 0644 "$ufile.new.$$" || ! mv -f -- "$ufile.new.$$" "$ufile"; then
            rm -f "$ufile.new.$$"; die "cannot write $ufile; the old unit is untouched"
          fi
          systemctl daemon-reload
          if [ "$(unit_user)" != "$SUSER" ]; then
            su_restore "$bak" && systemctl daemon-reload
            die "unit-user-not-applied: systemd still reports User=$(unit_user) (a drop-in in $ufile.d?); the old unit is back"
          fi
          echo "unit: installed $ufile with User=$SUSER (the old one: $bak)"
          changed=yes
          # keep the newest 5 old units
          su_backups | head -n -5 | while IFS= read -r o; do rm -f -- "$o"; done
        fi
        # 5. the restart
        p=$(run_pid) || p=""
        if [ -z "$p" ]; then
          echo "restart: the server is not running; it starts as $SUSER"
        elif [ "$(proc_user "$p")" = "$SUSER" ]; then
          echo "restart: not needed (the server runs as $SUSER)"
        elif [ "$again" != 0 ]; then
          : >> "$SULOG" 2>/dev/null || mkdir -p "$(dirname "$SULOG")"
          exec 8>&-
          setsid "$SELF" server-user-impl "$again" >> "$SULOG" 2>&1 < /dev/null &
          echo "restart: in $again seconds, as $SUSER (follow it with: chaos-ctl.sh server-user log)"
        else
          echo "restart: needed. The engine runs as $(proc_user "$p") until the unit restarts (the daily save restarts only the engine, not the unit): chaos-ctl.sh restart 300"
        fi
        if [ "$changed" = yes ]; then echo "RESULT ok: prepared"; else echo "RESULT ok: nothing to change"; fi
        ;;
      *) die "server-user [status | fix [--restart SECONDS] | rollback | log [N]]" ;;
    esac
    ;;
  server-user-impl)
    # the detached part of server-user fix --restart SECONDS
    { num "${1:-}" && [ "$1" -ge 30 ] && [ "$1" -le 900 ]; } || die "server-user-impl SECONDS (30 to 900)"
    mkdir -p "$SUSTATE"
    exec 8>"$SUSTATE/.lock"
    flock -w 5 8 || die "server-user-running"
    su_restart_impl "$1"
    exit $?
    ;;
  vps)
    sub=${1:-info}
    [ $# -gt 0 ] && shift
    case $sub in
      info)
        [ $# -eq 0 ] || die "vps info"
        echo "host=$(hostname 2>/dev/null)"
        os=""
        [ -r /etc/os-release ] && os=$(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-}")
        echo "os=$os"
        echo "kernel=$(uname -r)"
        echo "uptime=$(uptime -p 2>/dev/null | sed 's/^up //')"
        echo "load=$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)"
        echo "cpus=$(nproc 2>/dev/null)"
        free -m 2>/dev/null | awk '/^Mem:/ { print "mem_total_mb=" $2; print "mem_used_mb=" $3 }'
        df -BG -P / 2>/dev/null | awk 'NR == 2 { gsub(/G/, ""); print "disk_total_gb=" $2; print "disk_used_gb=" $3; print "disk_free_gb=" $4 }'
        up=-1 phpup=-1
        if command -v apt-get >/dev/null 2>&1; then
          sim=$(timeout 60 apt-get -s -o Debug::NoLocking=1 upgrade 2>/dev/null) || sim=""
          if [ -n "$sim" ]; then
            up=$(printf '%s\n' "$sim" | grep -c '^Inst ')
            phpup=$(printf '%s\n' "$sim" | grep -c '^Inst php')
          fi
        fi
        echo "upgrades=$up"
        echo "php_upgrades=$phpup"
        # the installed PHP package that serves the site (php-fpm or Apache mod_php), with the distribution's version
        echo "php=$(dpkg-query -W -f '${Package} ${Version}\n' 'php*-fpm' 'libapache2-mod-php*' 2>/dev/null \
          | grep -Ev '^(php-fpm|libapache2-mod-php) ' | awk 'NF == 2' | head -n 1)"
        if [ -e /run/reboot-required ]; then echo reboot_required=yes; else echo reboot_required=no; fi
        at=""
        [ -r /run/systemd/shutdown/scheduled ] && at=$(sed -n 's/^USEC=//p' /run/systemd/shutdown/scheduled 2>/dev/null \
          | head -n 1 | awk '{ printf "%d", $1 / 1000000 }')
        [ -n "$at" ] && at=$(date -d "@$at" '+%F %T' 2>/dev/null)
        echo "reboot_at=$at"
        ;;
      upgrade)
        [ $# -eq 0 ] || die "vps upgrade"
        command -v apt-get >/dev/null 2>&1 || die "no apt-get on this machine"
        if [ -r "$VLOG.pid" ] && p=$(head -c 20 "$VLOG.pid" | tr -dc 0-9) && [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
          die "an upgrade is already running (pid $p): chaos-ctl.sh vps upgrade-log"
        fi
        mkdir -p "$(dirname "$VLOG")"
        vlog=$VLOG  # the inner bash gets the path as $1 (its pid file), the outer one appends to it
        echo "== $(date '+%F %T') vps upgrade" > "$vlog"
        chmod 0640 "$VLOG" 2>/dev/null || true
        # shellcheck disable=SC2016 # expanded by the inner bash
        setsid bash -c 'echo $$ > "$1.pid"
          export DEBIAN_FRONTEND=noninteractive
          apt-get update && apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold upgrade
          rc=$?; echo "== $(date "+%F %T") done (exit $rc)"; [ -e /run/reboot-required ] && echo "== a reboot is needed"
          rm -f "$1.pid"' _ "$VLOG" >> "$vlog" 2>&1 < /dev/null &
        echo "started (apt-get update and upgrade); follow it with: chaos-ctl.sh vps upgrade-log"
        ;;
      upgrade-log)
        tail -n "$(lines_arg "${1:-60}")" "$VLOG" 2>&1
        ;;
      reboot)
        m=${1:-}
        { num "$m" && [ "$m" -ge 1 ] && [ "$m" -le 60 ]; } || die "vps reboot MINUTES (1 to 60)"
        [ $# -eq 1 ] || die "vps reboot MINUTES"
        if [ -d "$SERVER" ]; then
          spool "broadcast The server machine restarts in $m minute(s). Please log out in a safe place." >/dev/null || true
        fi
        if p=$(engine_pid); then kill -USR1 "$p" 2>/dev/null || true; fi
        shutdown -r "+$m" "chaos-ctl: reboot in $m minute(s)" 2>&1 || die "shutdown failed"
        echo "reboot planned in $m minute(s); players warned, game saved. Cancel: chaos-ctl.sh vps reboot-cancel"
        ;;
      reboot-cancel)
        [ $# -eq 0 ] || die "vps reboot-cancel"
        shutdown -c 2>&1 || die "shutdown -c failed"
        if [ -d "$SERVER" ]; then spool "broadcast The machine restart was cancelled." >/dev/null || true; fi
        echo "planned reboot cancelled"
        ;;
      *) die "vps [info] | upgrade | upgrade-log [N] | reboot MINUTES | reboot-cancel" ;;
    esac
    ;;
  services)
    [ $# -eq 0 ] || die "services"
    # shellcheck disable=SC2086 # WEB_UNITS is a fixed word list
    systemctl list-unit-files --no-legend --no-pager 'chaos-*' "$UNIT.service" 'php*-fpm.service' $WEB_UNITS 2>/dev/null \
      | awk '{ print $1, $2 }' | sort -u | while read -r u en; do
        [ -n "$u" ] || continue
        case $u in *@*) continue ;; esac
        unit_ok "$u" || continue
        printf '%s %s %s\n' "$u" "$(systemctl is-active "$u" 2>/dev/null | head -n 1)" "$en"
      done
    ;;
  service)
    name=${1:-} act=${2:-}
    { [ $# -eq 2 ] && unit_ok "$name"; } || die "service NAME start|stop|restart (NAME: a chaos-* or web server unit, see services)"
    case $act in start|stop|restart) ;; *) die "service NAME start|stop|restart" ;; esac
    [ "$(systemctl show "$name" -p LoadState --value 2>/dev/null)" = loaded ] || die "no such unit: $name (see services)"
    systemctl "$act" "$name" || die "$act $name failed"
    echo "$name: $act done ($(systemctl is-active "$name" 2>/dev/null | head -n 1))"
    ;;
  service-log)
    name=${1:-}
    unit_ok "$name" || die "service-log NAME [N] (NAME: a chaos-* or web server unit, see services)"
    n=$(lines_arg "${2:-60}")
    f=$(systemctl show "$name" -p StandardOutput --value 2>/dev/null | sed -n 's/^append://p; s/^file://p' | head -n 1)
    if [ -n "$f" ] && [ -r "$f" ]; then
      echo "== $f"
      tail -n "$n" "$f"
    else
      echo "== journal of $name"
      journalctl -u "$name" -n "$n" --no-pager 2>&1
    fi
    ;;
  testers)
    sub=${1:-status}
    [ $# -gt 0 ] && shift
    case $sub in
      start)
        n=100 minutes=60 rsecs="" pos=0 keyarg="" checkarg=""
        while [ $# -gt 0 ]; do
          case $1 in
            --keystones) keyarg=--keystones; shift ;;
            --checks) checkarg=--checks; shift ;;
            --restart)
              rsecs=${2:-}
              num "$rsecs" || die "--restart SECONDS"
              [ "$rsecs" -le 900 ] || die "at most 900 seconds"
              shift 2 ;;
            *)
              num "$1" || die "testers start [N] [MINUTES] [--restart SECONDS] [--keystones] [--checks]"
              [ $pos -lt 2 ] || die "testers start [N] [MINUTES] [--restart SECONDS] [--keystones] [--checks]"
              if [ $pos -eq 0 ]; then n=$1; else minutes=$1; fi
              pos=$((pos + 1)); shift ;;
          esac
        done
        if [ "$n" -lt 1 ] || [ "$n" -gt 150 ]; then die "N: 1 to 150 tester bots"; fi
        if [ "$minutes" -lt 1 ] || [ "$minutes" -gt 1440 ]; then die "MINUTES: 1 to 1440"; fi
        p=$(testers_pid) && die "tester bots already running (pid $p): chaos-ctl.sh testers stop"
        dev_key_on && die "config.lua has clientGuardAllowDevKey = true: the tester bots never run with the development key"
        key_file_ok
        [ -d "$SERVER/data/scripts" ] || die "no $SERVER/data/scripts"
        install -d -m 0700 "$TSTATE" || die "cannot create $TSTATE"
        own=$(stat -c %U "$SERVER" 2>/dev/null || echo root)
        if ! cp "$REPO/server/tools/tester_helper.lua" "$SERVER/data/scripts/zz_tester_helper.lua" \
          || ! cp "$REPO/server/tools/tester_helper_core.lua" "$SERVER/data/scripts/zz_tester_helper_core.lua"; then
          remove_helper; die "cannot copy the helper into $SERVER/data/scripts"
        fi
        for f in "${HELPER_FILES[@]}"; do
          chmod 0644 "$SERVER/data/scripts/$f"; chown "$own" "$SERVER/data/scripts/$f" 2>/dev/null || true
        done
        delay=0
        if ! helper_loaded; then
          if [ -z "$rsecs" ]; then
            remove_helper
            die "helper-not-loaded: the TEST ONLY helper loads at a server start. Run: chaos-ctl.sh testers start $n $minutes --restart 300"
          fi
          CHAOS_CTL_NO_SUDO=1 "$SELF" restart "$rsecs" >/dev/null || { remove_helper; die "restart failed"; }
          delay=$((rsecs + 30))
        fi
        have=$( (testers_py status --state "$TSTATE") 2>/dev/null | sed -n 's/^bots=//p')
        have=${have:-0}
        if [ "$have" -lt "$n" ]; then
          [ "$have" -eq 0 ] || { remove_helper; die "the last setup made $have testers, fewer than $n: chaos-ctl.sh testers cleanup --yes first"; }
          testers_py setup --count "$n" --server-dir "$SERVER" --state "$TSTATE" || { remove_helper; die "setup failed"; }
        fi
        mkdir -p "$(dirname "$TLOG")"
        echo "== $(date '+%F %T') testers start $n $minutes" >> "$TLOG"
        # detached, in its own process group (stop ends the whole group); when the run is over by itself the helper
        # goes too (testers stop --finished)
        # shellcheck disable=SC2034 # exported by set -a, for testers.py
        ( set -a; . "$ENVFILE"; [ -n "$DBSOCK" ] && CHAOS_DB_SOCKET=$DBSOCK; CHAOS_MYSQL=$MYSQL; set +a
          # shellcheck disable=SC2016
          exec setsid bash -c 'sleep "$1"; python3 -I "$2" run --key-file "$3" --server-dir "$4" --state "$5" \
            --minutes "$6" --count "$7" --log "$8" --scenarios "${10}" ${11:+"${11}"} ${12:+"${12}"}; CHAOS_CTL_NO_SUDO=1 "$9" testers stop --finished' _ \
            "$delay" "$REPO/server/tools/testers.py" "$TKEY" "$SERVER" "$TSTATE" "$minutes" "$n" "$LOG" "$SELF" \
            "$REPO/server/tools/tester_scenarios.json" "$keyarg" "$checkarg" \
            >> "$TLOG" 2>&1 < /dev/null ) &
        echo $! > "$TSTATE/run.pid"
        date +%s > "$TSTATE/started"
        rm -f "$TSTATE/stopped"
        if [ "$delay" -gt 0 ]; then
          echo "tester bots: $n for $minutes minutes${keyarg:+, keystones and masteries first}${checkarg:+, system checks}, starting in $delay s, after the restart (log $TLOG)"
        else
          echo "tester bots: $n for $minutes minutes${keyarg:+, keystones and masteries first}${checkarg:+, system checks} (log $TLOG)"
        fi
        ;;
      stop)
        if p=$(testers_pid); then
          if [ "${1:-}" != --finished ]; then
            kill -TERM -- "-$p" 2>/dev/null || kill -TERM "$p" 2>/dev/null
            for _ in $(seq 1 30); do kill -0 "$p" 2>/dev/null || break; sleep 1; done
            kill -KILL -- "-$p" 2>/dev/null || true
          fi
        fi
        rm -f "$TSTATE/run.pid"
        remove_helper
        date +%s > "$TSTATE/stopped" 2>/dev/null || true
        [ "${1:-}" = --finished ] && echo "== $(date '+%F %T') run over" >> "$TLOG"
        echo "tester bots stopped; helper removed from data/scripts (its loop ends within seconds, the rest at the next restart)"
        ;;
      status)
        if p=$(testers_pid); then echo running=yes; echo "pid=$p"; else echo running=no; echo pid=; fi
        started=""
        [ -r "$TSTATE/started" ] && started=$(date -d "@$(tr -dc 0-9 < "$TSTATE/started")" '+%F %T' 2>/dev/null)
        echo "started=$started"
        (testers_py status --state "$TSTATE") 2>/dev/null | grep -E '^(bots|minutes|online|online_peak|logins|deaths)='
        # the helper's own count (once a minute on the server console), while the bots run
        srv=""
        if [ -n "${p:-}" ] && [ -r "$LOG" ]; then
          srv=$(tail -n 20000 "$LOG" 2>/dev/null | grep -o 'testers online: [0-9]*' | tail -n 1 | tr -dc 0-9)
        fi
        echo "online_server=$srv"
        if [ -e "$SERVER/data/scripts/zz_tester_helper.lua" ]; then echo helper=copied; else echo helper=absent; fi
        if helper_loaded; then echo helper_loaded=yes; else echo helper_loaded=no; fi
        ;;
      report)
        testers_py report --state "$TSTATE" --log "$LOG"
        ;;
      log)
        n=${1:-200}
        num "$n" || die "testers log [N]"
        { [ "$n" -ge 1 ] && [ "$n" -le 5000 ]; } || die "testers log N: 1 to 5000"
        f=""
        for r in "$TSTATE"/runs/run-*.log; do [ -e "$r" ] && f=$r; done  # the glob sorts: the newest is last
        [ -n "$f" ] || die "no activity log yet (it is written from the next testers start on)"
        echo "== $f ($(wc -l < "$f") lines)"
        tail -n "$n" "$f"
        ;;
      cleanup)
        yes=0
        case "$*" in '') ;; --yes) yes=1 ;; *) die "testers cleanup [--yes]" ;; esac
        if testers_pid >/dev/null; then CHAOS_CTL_NO_SUDO=1 "$SELF" testers stop; fi
        remove_helper
        if [ -r "$TSTATE/stopped" ]; then
          ago=$(( $(date +%s) - $(tr -dc 0-9 < "$TSTATE/stopped") ))
          # a character in a fight stays in game up to 2 minutes after the bots stop: wait it out here (the admin
          # app's Apagar stops running bots and deletes in one tap; it allows 240 s)
          # CHAOS_TESTERS_STOP_WAIT: the wait in seconds (tests set it short)
          wait_s=${CHAOS_TESTERS_STOP_WAIT:-120}
          num "$wait_s" || wait_s=120
          if [ "$ago" -lt "$wait_s" ]; then
            echo "the bots stopped $ago s ago: waiting $((wait_s - ago)) s (a character in a fight stays in game)"
            sleep $((wait_s - ago))
          fi
        fi
        if [ $yes -eq 1 ]; then
          testers_py cleanup --state "$TSTATE" --server-dir "$SERVER"
        else
          testers_py cleanup --state "$TSTATE" --dry-run
          echo "(nothing deleted: chaos-ctl.sh testers cleanup --yes)"
        fi
        ;;
      *) die "testers start [N] [MINUTES] [--restart SECONDS] [--keystones] [--checks] | stop | status | report | log [N] | cleanup [--yes]" ;;
    esac
    ;;
  ''|help|-h|--help)
    sed -n '2,/^set -uo/p' "$SELF" | sed '$d' | sed 's/^# \{0,1\}//'
    ;;
  *)
    die "unknown command: $cmd (chaos-ctl.sh help)"
    ;;
esac
