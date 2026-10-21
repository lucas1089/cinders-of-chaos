#!/usr/bin/env bash
# shellcheck source=/dev/null disable=SC2015
# Cinders of Chaos: update the live server of the Linux kit layout (/opt/chaos-trial) from GitHub, for the admin app's
# "Atualizar servidor" (docs/ADMIN_APP.md) through chaos-ctl.sh update-check / update-apply / update-rollback.
# Run as root. The routine it automates: docs/LAUNCH.md "Updating the kit server (admin app)".
#
# usage: chaos_kit_update.sh check
#        chaos_kit_update.sh apply [--no-client] [--no-downloads] [--no-site]
#        chaos_kit_update.sh rollback
#
# check     key=value lines: branch, local_commit, remote_commit, behind, ahead, commit (one per new commit, newest
#           first, at most 15: short hash and subject), installed_release, latest_release, needs_engine, published_client,
#           needs_client, downloads_release, needs_downloads, website_changed, update_available, running, last_status,
#           last_result. Fetches the branch; changes nothing else.
# apply     the update, in steps (each starts with a "STEP n/9 name" line; the last line is "RESULT status: text"):
#            1 check      lock, clean checkout not ahead of the branch, the newest winpkg-N release of CHAOS_RELEASE_REPO
#            2 download   when the release is newer than the installed one: CindersOfChaos-Server-Linux.tar.gz (https
#                         only, size against GitHub's, SHA-256 printed and compared with GitHub's digest), the engine
#                         taken out of it with a checked tar reader, ldd finds every library
#            3 backup     server/tools/backup.sh with the server up (save first, database dump, config.lua + data/)
#            4 install    the XP rates saved (chaos_config_rates.py), git checkout of the branch, the server stopped, the
#                         engine replaced (the old one kept as tfs.antes-N), install_all.py --no-sql, the rates put back,
#                         the server folder owned by the unit's user
#            5 database   the server started (the kit's MariaDB runs inside the unit), the database waited for,
#                         install_all.py --only sql, then a restart so the engine starts on the new tables
#            6 verify     the unit active and "Server Online" in the log within CHAOS_BOOT_TIMEOUT seconds
#                         A failure in steps 4-6 rolls the server back: engine, config.lua and data/ from the backup,
#                         the previous commit, started and verified again (RESULT rolled-back). The database keeps the
#                         new tables (the SQL files only add; a full restore is the runbook's).
#            7 client     publish_client_update.sh winpkg-N when the release is newer than the live client update
#                         (--no-client skips it)
#            8 downloads  the release's Windows zip and Linux tar.gz into CHAOS_DL_DIR: temporary name, size and
#                         SHA-256 checked, the old file kept as NAME.prev, then renamed; NAME.sha256 and downloads.json
#                         (the downloads page shows release, date, size, checksum) (--no-downloads skips it)
#            9 site       website/install_site.sh when website/ changed in this update and CHAOS_SITE_ENV exists
#                         (--no-site skips it)
#           Steps 7-9 never undo the server update: a failure there ends with RESULT warn.
# rollback  back to the state before the last apply: engine, config.lua and data/, the previous commit, the download
#           files (NAME.prev); started and verified.
#
# Settings (environment; chaos-ctl.sh passes its /etc/chaos/ctl.conf keys of the same names):
#   CHAOS_REPO /opt/chaos/repo         CHAOS_UPDATE_BRANCH main         CHAOS_RELEASE_REPO lucas1089/cinders-of-chaos
#   CHAOS_KIT_DIR /opt/chaos-trial     CHAOS_SERVER_DIR $KIT/server     CHAOS_ENV $KIT/chaos.env (CHAOS_DB_*)
#   CHAOS_UNIT chaos-server            CHAOS_LOG $KIT/logs/server.log   CHAOS_MYSQL $KIT/mariadb/bin/mariadb
#   CHAOS_KIT_STATE /var/lib/chaos/kit-update   CHAOS_WORK_DIR /var/tmp   CHAOS_BOOT_TIMEOUT 900
#   CHAOS_SITE_DIR /var/www/chaos      CHAOS_DL_DIR $SITE/dl            CHAOS_SITE_ENV /etc/chaos/site.env
#   CHAOS_BACKUP_DIR (else the env file's, else /var/backups/chaos); publish_client_update.sh reads its own
#   (CHAOS_UPDATE_KEY, ...). Exit: 0 ok, 1 failed, 2 rolled back, 3 ok with warnings.
set -uo pipefail
umask 022

# run from a copy: the checkout this file lives in changes while it runs
if [ -z "${CHAOS_KIT_COPY:-}" ]; then
  copy=$(mktemp "${TMPDIR:-/tmp}/chaos_kit_update.XXXXXX") || exit 1
  cp "$0" "$copy"
  CHAOS_KIT_COPY=$copy exec bash "$copy" "$@"
fi
trap 'rm -f "$CHAOS_KIT_COPY"' EXIT

REPO=${CHAOS_REPO:-/opt/chaos/repo}
BRANCH=${CHAOS_UPDATE_BRANCH:-main}
GHREPO=${CHAOS_RELEASE_REPO:-lucas1089/cinders-of-chaos}
KIT=${CHAOS_KIT_DIR:-/opt/chaos-trial}
SERVER=${CHAOS_SERVER_DIR:-$KIT/server}
ENVFILE=${CHAOS_ENV:-$KIT/chaos.env}
UNIT=${CHAOS_UNIT:-chaos-server}
SLOG=${CHAOS_LOG:-$KIT/logs/server.log}
MYSQL=${CHAOS_MYSQL:-$KIT/mariadb/bin/mariadb}
STATE_DIR=${CHAOS_KIT_STATE:-/var/lib/chaos/kit-update}
WORKBASE=${CHAOS_WORK_DIR:-/var/tmp}
BOOT_TIMEOUT=${CHAOS_BOOT_TIMEOUT:-900}
SITE=${CHAOS_SITE_DIR:-/var/www/chaos}
DL=${CHAOS_DL_DIR:-$SITE/dl}
SITE_ENV=${CHAOS_SITE_ENV:-/etc/chaos/site.env}
SERVER_ASSET=CindersOfChaos-Server-Linux.tar.gz
CLIENT_ASSETS="CindersOfChaos-Client-Windows.zip CindersOfChaos-Client-Linux.tar.gz"
STATE="$STATE_DIR/state"

say() { printf '%s\n' "$*"; }
log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }
die() { printf 'chaos_kit_update: %s\n' "$*" >&2; exit 1; }

[[ $GHREPO =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "CHAOS_RELEASE_REPO must be OWNER/REPO"
[[ $BRANCH =~ ^[A-Za-z0-9][A-Za-z0-9._/-]{0,99}$ ]] && [[ $BRANCH != *..* ]] || die "bad CHAOS_UPDATE_BRANCH"
[[ $BOOT_TIMEOUT =~ ^[0-9]+$ ]] || die "CHAOS_BOOT_TIMEOUT must be a number of seconds"
g() { git -C "$REPO" -c safe.directory="$REPO" "$@"; }

state_get() { [ -f "$STATE" ] && sed -n "s/^$1=//p" "$STATE" | tail -n 1; }
# state_set KEY=VALUE...: changes those keys, keeps the others
state_set() {
  mkdir -p "$STATE_DIR"
  local tmp="$STATE.tmp" kv
  [ -f "$STATE" ] && cp "$STATE" "$tmp" || : > "$tmp"
  for kv in "$@"; do
    grep -v "^${kv%%=*}=" "$tmp" > "$tmp.2" || true
    printf '%s\n' "$kv" >> "$tmp.2"
    mv "$tmp.2" "$tmp"
  done
  mv "$tmp" "$STATE"
}

# the GitHub releases: "latest=N" and "asset=NAME SIZE SHA256" (SHA256 "-" when GitHub gives none) of release N
releases() {
  local out=$1
  curl -fsSL --proto '=https' --proto-redir '=https' --max-time 30 --retry 2 \
    -H 'Accept: application/vnd.github+json' -o "$out" \
    "https://api.github.com/repos/$GHREPO/releases?per_page=50" || return 1
  python3 -I - "$out" "$SERVER_ASSET" <<'PY'
import json, re, sys
data = json.load(open(sys.argv[1], encoding='utf-8'))
best = None
for r in data if isinstance(data, list) else []:
    m = re.fullmatch(r'winpkg-([0-9]{1,6})', str(r.get('tag_name', '')))
    if not m or r.get('draft'):
        continue
    names = {a.get('name') for a in r.get('assets') or []}
    if sys.argv[2] not in names:
        continue
    n = int(m.group(1))
    if best is None or n > best[0]:
        best = (n, r)
if best is None:
    sys.exit('no winpkg-N release with the server package')
print('latest=%d' % best[0])
for a in best[1].get('assets') or []:
    name = str(a.get('name', ''))
    if not re.fullmatch(r'[A-Za-z0-9._-]{1,100}', name):
        continue
    d = str(a.get('digest') or '')
    sha = d[7:] if re.fullmatch(r'sha256:[0-9a-f]{64}', d) else '-'
    print('asset=%s %d %s' % (name, int(a.get('size') or 0), sha))
PY
}
asset_info() { sed -n "s/^asset=$1 //p" <<< "$REL"; }

# the live client update's version (publish_client_update.sh's manifest), 0 when none
published_client() {
  python3 -I - "$SITE/updates/live/manifest.json" <<'PY' 2>/dev/null || echo 0
import json, sys
print(int(json.loads(json.load(open(sys.argv[1]))['payload'])['version']))
PY
}
dl_release() {
  python3 -I -c 'import json,sys; print(int(json.load(open(sys.argv[1]))["release"]))' "$DL/downloads.json" 2>/dev/null || echo 0
}

# download ASSET of release N into FILE: https only, size as GitHub says, sha256 printed and compared when known
fetch_asset() {
  local name=$1 file=$2 info size sha got
  info=$(asset_info "$name")
  [ -n "$info" ] || { log "release winpkg-$LATEST has no $name"; return 1; }
  read -r size sha <<< "$info"
  log "download https://github.com/$GHREPO/releases/download/winpkg-$LATEST/$name ($size bytes)"
  curl -fL --proto '=https' --proto-redir '=https' --retry 3 --retry-delay 5 --max-filesize 8589934592 -sS \
    -o "$file" "https://github.com/$GHREPO/releases/download/winpkg-$LATEST/$name" || { log "download failed"; return 1; }
  got=$(stat -c %s "$file")
  [ "$got" = "$size" ] || { log "size $got, GitHub says $size: refused"; return 1; }
  [ "$got" -ge 1048576 ] || { log "only $got bytes: refused (an error page?)"; return 1; }
  got=$(sha256sum "$file" | cut -d' ' -f1)
  log "sha256 $got"
  if [ "$sha" != - ] && [ "$sha" != "$got" ]; then log "GitHub's digest is $sha: refused"; return 1; fi
  return 0
}

# the engine out of the server package: every entry checked; CindersOfChaos-Server-Linux/server/tfs and its libraries
# (server/lib/: the engine's RUNPATH is $ORIGIN/lib) written under DEST (DEST/tfs, DEST/lib/); a link in lib/ may only
# name a file of lib/ itself
extract_tfs() {
  python3 -I - "$1" "$2" <<'PY'
import os, sys, tarfile
src, dest = sys.argv[1], sys.argv[2]
base = 'CindersOfChaos-Server-Linux/server/'
found = False
libs = 0
os.makedirs(os.path.join(dest, 'lib'))
with tarfile.open(src, 'r:gz') as t:
    for m in t:
        n = m.name
        if n.startswith('/') or '\0' in n or '..' in n.split('/'):
            sys.exit('refused entry %r: unsafe path' % n)
        n = n.lstrip('./')
        if n == base + 'tfs':
            target = os.path.join(dest, 'tfs')
        elif n.startswith(base + 'lib/') and '/' not in n[len(base) + 4:] and n != base + 'lib/':
            target = os.path.join(dest, 'lib', n[len(base) + 4:])
        else:
            continue
        if m.issym():
            if not n.startswith(base + 'lib/') or '/' in m.linkname or m.linkname in ('', '.', '..'):
                sys.exit('refused link %r -> %r' % (n, m.linkname))
            os.symlink(m.linkname, target)
            libs += 1
            continue
        if not m.isfile() or m.size > 512 * 1024 * 1024:
            sys.exit('%s is not a regular file of at most 512 MB' % n)
        f = t.extractfile(m)
        with open(target, 'xb') as out:
            while True:
                b = f.read(1 << 20)
                if not b:
                    break
                out.write(b)
        if target.endswith('/tfs'):
            os.chmod(target, 0o755)
            found = True
        else:
            os.chmod(target, 0o644)
            libs += 1
if not found:
    sys.exit('no %stfs in the package' % base)
print('engine: %stfs, %d librar%s' % (base, libs, 'y' if libs == 1 else 'ies'))
PY
}

# ------------------------------------------------------------------------------------------------ check
cmd_check() {
  local cur remote work n
  [ -d "$REPO/.git" ] || g rev-parse --git-dir >/dev/null 2>&1 || die "no git checkout at $REPO (CHAOS_REPO)"
  say "branch=$BRANCH"
  g fetch --quiet origin "$BRANCH" 2>/dev/null || die "git fetch origin $BRANCH failed"
  cur=$(g rev-parse HEAD) remote=$(g rev-parse "origin/$BRANCH")
  say "local_commit=$(g rev-parse --short HEAD)"
  say "remote_commit=$(g rev-parse --short "origin/$BRANCH")"
  say "behind=$(g rev-list --count "HEAD..origin/$BRANCH")"
  say "ahead=$(g rev-list --count "origin/$BRANCH..HEAD")"
  g log --no-decorate --format='commit=%h %s' -n 15 "HEAD..origin/$BRANCH" | cut -c1-160
  work=$(mktemp -d "$WORKBASE/chaos-kit-check.XXXXXX") || die "no work folder in $WORKBASE"
  REL=$(releases "$work/rel.json") || REL=""
  rm -rf "$work"
  LATEST=$(sed -n 's/^latest=//p' <<< "$REL")
  n=$(state_get installed_release)
  say "installed_release=${n:-unknown}"
  say "latest_release=${LATEST:-unknown}"
  if [ -z "$LATEST" ]; then say "needs_engine=unknown"
  elif [ -z "$n" ] || [ "$n" -lt "$LATEST" ]; then say "needs_engine=yes"
  else say "needs_engine=no"; fi
  n=$(published_client)
  say "published_client=$n"
  [ -n "$LATEST" ] && [ "$n" -lt "$LATEST" ] && [ -n "$(asset_info CindersOfChaos-Client-Windows.zip)" ] \
    && say "needs_client=yes" || say "needs_client=no"
  n=$(dl_release)
  say "downloads_release=$n"
  [ -n "$LATEST" ] && [ "$n" -lt "$LATEST" ] && [ -d "$DL" ] && say "needs_downloads=yes" || say "needs_downloads=no"
  if g diff --quiet "$cur" "$remote" -- website/ 2>/dev/null; then say "website_changed=no"; else say "website_changed=yes"; fi
  if [ "$cur" != "$remote" ] || [ "$(state_get installed_release)" != "$LATEST" ]; then
    say "update_available=yes"
  else
    say "update_available=no"
  fi
  if [ -f "$STATE_DIR/.lock" ] && ! flock -n "$STATE_DIR/.lock" true; then say "running=yes"; else say "running=no"; fi
  say "last_status=$(state_get status)"
  say "last_result=$(state_get result)"
  say "last_time=$(state_get time)"
}

# ------------------------------------------------------------------------------------------------ the server
active() { systemctl is-active --quiet "$UNIT"; }
log_size() { stat -c %s "$SLOG" 2>/dev/null || echo 0; }
# the unit active and "Server Online" in the log after byte FROM, within BOOT_TIMEOUT seconds
wait_online() {
  local from=$1 waited=0
  log "waiting for \"Server Online\" in $SLOG (at most ${BOOT_TIMEOUT}s; the map load takes a few minutes)"
  while :; do
    [ "$(log_size)" -ge "$from" ] || from=0
    if tail -c +"$((from + 1))" "$SLOG" 2>/dev/null | grep -q 'Server Online'; then
      if active; then log "ok: the server is online"; return 0; fi
    fi
    if ! active; then
      log "FAIL: $UNIT is not running ($(systemctl is-active "$UNIT" 2>/dev/null))"
      tail -c +"$((from + 1))" "$SLOG" 2>/dev/null | tail -n 15
      return 1
    fi
    if [ "$waited" -ge "$BOOT_TIMEOUT" ]; then
      log "FAIL: no \"Server Online\" after ${BOOT_TIMEOUT}s"
      tail -c +"$((from + 1))" "$SLOG" 2>/dev/null | tail -n 15
      return 1
    fi
    sleep 5
    waited=$((waited + 5))
  done
}
# the game database answers (the kit starts it inside the unit)
wait_db() {
  local cnf i
  cnf=$(mktemp) || return 1
  chmod 600 "$cnf"
  ( set -a; . "$ENVFILE"; set +a
    printf '[client]\nhost=%s\nport=%s\nuser=%s\npassword="%s"\n' "${CHAOS_DB_HOST:-127.0.0.1}" "${CHAOS_DB_PORT:-3306}" \
      "${CHAOS_DB_USER:-chaos}" "${CHAOS_DB_PASS:-}" ) > "$cnf"
  for i in $(seq 1 60); do
    if "$MYSQL" --defaults-extra-file="$cnf" -N -B -e 'SELECT 1' >/dev/null 2>&1; then
      rm -f "$cnf"; log "the database answers"; return 0
    fi
    active || break
    sleep 2
    : "$i"
  done
  rm -f "$cnf"
  log "FAIL: the database did not answer in 120 s"
  return 1
}
own_server() {
  local user group
  user=$(systemctl show -p User --value "$UNIT" 2>/dev/null || true)
  group=$(systemctl show -p Group --value "$UNIT" 2>/dev/null || true)
  [ -n "$user" ] && [ "$user" != root ] || return 0
  chown -R "$user:${group:-$user}" "$SERVER" && log "ownership of $SERVER: $user:${group:-$user}"
}
install_all() {  # extra arguments for install_all.py; the database settings of the env file
  ( set -a; . "$ENVFILE"; set +a
    python3 -I "$REPO/server/tools/install_all.py" "$SERVER" --mysql "$MYSQL" --quiet "$@" )
}

# the server back to the recorded state before the update: engine, config.lua + data/, commit; started and verified
restore_server() {
  local prev engine_bk archive aside stamp from
  prev=$(state_get prev_commit) engine_bk=$(state_get engine_backup) archive=$(state_get data_archive)
  [ -f "$SERVER/config.lua" ] && [ -d "$SERVER/data" ] || { log "FAIL: $SERVER is not a server folder"; return 1; }
  stamp=$(date '+%Y%m%d-%H%M%S')
  log "rollback: stopping $UNIT"
  systemctl stop "$UNIT" || true
  if [ -n "$engine_bk" ] && [ -f "$engine_bk" ]; then
    install -m 0755 "$engine_bk" "$SERVER/tfs" && log "engine put back from $engine_bk"
    if [ -d "$engine_bk.lib" ]; then
      rm -rf "${SERVER:?}/lib" && cp -a "$engine_bk.lib" "$SERVER/lib" && log "engine libraries put back from $engine_bk.lib"
    fi
  fi
  if [ -n "$archive" ] && [ -f "$archive" ]; then
    aside="$SERVER/data.before-rollback-$stamp"
    mv "$SERVER/data" "$aside"
    cp -p "$SERVER/config.lua" "$SERVER/config.lua.before-rollback-$stamp"
    if tar -C "$SERVER" -xzf "$archive" config.lua data; then
      # the archive leaves out the maps, logs and reports: carry them over
      (cd "$aside" && find . -name '*.otbm' -type f -print0) | while IFS= read -r -d '' f; do
        mkdir -p "$SERVER/data/$(dirname "$f")"
        mv "$aside/$f" "$SERVER/data/$f"
      done
      for d in logs reports; do
        if [ -d "$aside/$d" ]; then rm -rf "${SERVER:?}/data/$d"; mv "$aside/$d" "$SERVER/data/$d"; fi
      done
      log "config.lua and data/ restored from $archive (the replaced folder: $aside)"
    else
      rm -rf "$SERVER/data"; mv "$aside" "$SERVER/data"
      cp -p "$SERVER/config.lua.before-rollback-$stamp" "$SERVER/config.lua"
      log "FAIL: could not unpack $archive: data/ left as it was"
    fi
  else
    log "no data archive recorded: config.lua and data/ stay"
  fi
  if [ -n "$prev" ]; then
    g checkout --quiet --detach "$prev" && log "checkout back at $(g rev-parse --short "$prev")"
  fi
  own_server
  from=$(log_size)
  systemctl start "$UNIT" || true
  if wait_online "$from"; then
    state_set "installed_release=$(state_get prev_release)" "deployed_commit=$prev"
    return 0
  fi
  return 1
}

finish() {  # STATUS TEXT EXIT
  state_set "status=$1" "result=$2" "time=$(date '+%F %T')"
  say ""
  say "RESULT $1: $2"
  exit "$3"
}

lock() {
  mkdir -p "$STATE_DIR"
  chmod 700 "$STATE_DIR"
  exec 8>"$STATE_DIR/.lock"
  flock -n 8 || die "another update or rollback is running"
}

# ------------------------------------------------------------------------------------------------ apply
cmd_apply() {
  local client=1 downloads=1 site=1 a
  for a in "$@"; do
    case $a in
      --no-client) client=0 ;; --no-downloads) downloads=0 ;; --no-site) site=0 ;;
      *) die "apply [--no-client] [--no-downloads] [--no-site]" ;;
    esac
  done
  lock
  local work warn="" cur remote installed prev_release engine_new="" stamp from dirty rates
  stamp=$(date '+%Y%m%d-%H%M%S')
  state_set "status=running" "result=" "time=$(date '+%F %T')"
  say "STEP 1/9 check"
  for tool in git python3 curl systemctl tar sha256sum ldd; do
    command -v "$tool" >/dev/null || finish failed "$tool is missing" 1
  done
  [ -f "$SERVER/config.lua" ] && [ -d "$SERVER/data" ] || finish failed "$SERVER is not a server folder" 1
  [ -r "$ENVFILE" ] || finish failed "cannot read $ENVFILE (CHAOS_ENV)" 1
  dirty=$(g status --porcelain --untracked-files=no 2>&1) || finish failed "$REPO is not a git checkout" 1
  [ -z "$dirty" ] || { say "$dirty" | head -n 10; finish failed "the checkout $REPO has changed files (above): nothing done" 1; }
  g fetch --quiet origin "$BRANCH" || finish failed "git fetch origin $BRANCH failed" 1
  cur=$(g rev-parse HEAD) remote=$(g rev-parse "origin/$BRANCH")
  [ "$(g rev-list --count "origin/$BRANCH..HEAD")" = 0 ] \
    || finish failed "the checkout has commits that are not on origin/$BRANCH: nothing done" 1
  log "code: $(g rev-parse --short HEAD) -> $(g rev-parse --short "origin/$BRANCH") ($(g rev-list --count "HEAD..origin/$BRANCH") commit(s))"
  work=$(mktemp -d "$WORKBASE/chaos-kit-update.XXXXXX") || finish failed "no work folder in $WORKBASE" 1
  trap 'rm -rf "$work"; rm -f "$CHAOS_KIT_COPY"' EXIT
  REL=$(releases "$work/rel.json") || finish failed "cannot read the releases of $GHREPO" 1
  LATEST=$(sed -n 's/^latest=//p' <<< "$REL")
  installed=$(state_get installed_release)
  log "release: installed ${installed:-unknown}, newest winpkg-$LATEST"
  if [ "$cur" = "$remote" ] && [ "$installed" = "$LATEST" ]; then
    log "the server is up to date"
  fi

  say "STEP 2/9 download"
  if [ -z "$installed" ] || [ "$installed" -lt "$LATEST" ]; then
    fetch_asset "$SERVER_ASSET" "$work/server.tar.gz" || finish failed "the server package of winpkg-$LATEST was refused: nothing changed" 1
    extract_tfs "$work/server.tar.gz" "$work/engine" || finish failed "no engine in the package: nothing changed" 1
    rm -f "$work/server.tar.gz"
    if ldd "$work/engine/tfs" 2>&1 | grep 'not found'; then
      finish failed "the new engine needs libraries this machine lacks (above; apt install them): nothing changed" 1
    fi
    if [ -f "$SERVER/tfs" ] && cmp -s "$work/engine/tfs" "$SERVER/tfs" && diff -rq "$work/engine/lib" "$SERVER/lib" >/dev/null 2>&1; then
      log "the installed engine is already the one of winpkg-$LATEST"
    else
      engine_new="$work/engine"
      log "new engine: sha256 $(sha256sum "$work/engine/tfs" | cut -d' ' -f1)"
    fi
  else
    log "the engine is current (winpkg-$installed)"
  fi

  if [ "$cur" = "$remote" ] && [ -z "$engine_new" ]; then
    log "no new code and no new engine: the server is not restarted"
    state_set "installed_release=$LATEST"
    prev_release=$installed
  else
    say "STEP 3/9 backup"
    [ -x "$REPO/server/tools/backup.sh" ] || finish failed "no $REPO/server/tools/backup.sh: nothing changed" 1
    local save=() bdir pid
    pid=$(head -c 20 "$KIT/run/server.pid" 2>/dev/null | tr -dc 0-9)
    if [ -n "$pid" ] && [ "$(cat "/proc/$pid/comm" 2>/dev/null)" = tfs ]; then save=(--save-pid "$pid"); fi
    bdir=${CHAOS_BACKUP_DIR:-$( . "$ENVFILE" 2>/dev/null; echo "${CHAOS_BACKUP_DIR:-/var/backups/chaos}" )}
    ( set -a; . "$ENVFILE"; CHAOS_BACKUP_DIR=$bdir; set +a; PATH="$PATH:$KIT/mariadb/bin"
      "$REPO/server/tools/backup.sh" "${save[@]}" --server-dir "$SERVER" 2>&1 | tail -n 15; exit "${PIPESTATUS[0]}" ) \
      || finish failed "the backup failed: nothing changed" 1
    local archive
    # shellcheck disable=SC2012 # plain backup names
    archive=$(ls -1t "$bdir"/data/chaos-data-*.tar.gz 2>/dev/null | head -n 1)
    [ -n "$archive" ] || finish failed "no data archive in $bdir/data after the backup: nothing changed" 1
    log "backup: $archive"

    say "STEP 4/9 install"
    rates="$STATE_DIR/rates-$stamp.json"
    python3 -I "$REPO/server/deploy/chaos_config_rates.py" save "$SERVER/config.lua" "$rates" \
      || finish failed "cannot read the rates of config.lua: nothing changed" 1
    prev_release=$installed
    state_set "prev_commit=$cur" "prev_release=$installed" "data_archive=$archive" "engine_backup=" "target_commit=$remote" \
      "target_release=$LATEST"
    g checkout --quiet -B "$BRANCH" "origin/$BRANCH" || finish failed "git checkout $BRANCH failed: nothing changed" 1
    log "checkout at $(g rev-parse --short HEAD) ($BRANCH)"
    log "stopping $UNIT (the game saves everyone; players are disconnected)"
    systemctl stop "$UNIT"
    local ok=1
    if [ -n "$engine_new" ]; then
      local bk="$SERVER/tfs.antes-$LATEST"
      [ -e "$bk" ] && bk="$bk.$stamp"
      if cp -p "$SERVER/tfs" "$bk" && { [ ! -d "$SERVER/lib" ] || cp -a "$SERVER/lib" "$bk.lib"; } \
        && install -m 0755 "$engine_new/tfs" "$SERVER/tfs" && rm -rf "$SERVER/lib.new" \
        && cp -a "$engine_new/lib" "$SERVER/lib.new" && rm -rf "${SERVER:?}/lib" && mv "$SERVER/lib.new" "$SERVER/lib"; then
        state_set "engine_backup=$bk"
        log "engine of winpkg-$LATEST installed (the old one: $bk)"
      else
        ok=0; log "FAIL: could not replace the engine"
      fi
    fi
    if [ "$ok" = 1 ]; then
      log "install_all.py (every step but sql; the database is down with the server):"
      install_all --no-sql 2>&1 | tail -n 60
      [ "${PIPESTATUS[0]}" = 0 ] || { ok=0; log "FAIL: install_all.py failed"; }
    fi
    if [ "$ok" = 1 ]; then
      python3 -I "$REPO/server/deploy/chaos_config_rates.py" restore "$SERVER/config.lua" "$rates" || ok=0
      own_server
    fi
    if [ "$ok" = 1 ]; then
      say "STEP 5/9 database"
      systemctl start "$UNIT" || true
      if wait_db; then
        log "install_all.py --only sql:"
        install_all --only sql 2>&1 | tail -n 30
        [ "${PIPESTATUS[0]}" = 0 ] || { ok=0; log "FAIL: the sql step failed"; }
      else
        ok=0
      fi
    fi
    if [ "$ok" = 1 ]; then
      from=$(log_size)
      log "restart: the engine starts on the new tables"
      systemctl restart "$UNIT" || true
      say "STEP 6/9 verify"
      wait_online "$from" || ok=0
    fi
    if [ "$ok" = 0 ]; then
      say "STEP 6/9 rollback"
      if restore_server; then
        finish rolled-back "the update failed; the server is back on the previous version and online (the database keeps the new tables)" 2
      fi
      finish failed "the update failed and the rollback did not bring the server up: docs/LAUNCH.md \"Incident runbook\"" 1
    fi
    state_set "installed_release=$LATEST" "deployed_commit=$remote"
    log "server updated: $(g rev-parse --short HEAD), winpkg-$LATEST"
  fi

  say "STEP 7/9 client"
  local pub
  pub=$(published_client)
  if [ "$client" = 0 ]; then
    log "skipped (--no-client)"
  elif [ "$pub" -ge "$LATEST" ]; then
    log "the live client update is version $pub: nothing newer"
  elif [ -z "$(asset_info CindersOfChaos-Client-Windows.zip)" ]; then
    log "winpkg-$LATEST has no client package"
  else
    log "publish_client_update.sh winpkg-$LATEST (live: $pub)"
    if "$REPO/server/deploy/publish_client_update.sh" -- "winpkg-$LATEST" 2>&1 | tail -n 25; [ "${PIPESTATUS[0]}" = 0 ]; then
      log "client update $LATEST published"
    else
      warn="$warn client"; log "WARN: the client update was not published (above)"
    fi
  fi

  say "STEP 8/9 downloads"
  local have
  have=$(dl_release)
  if [ "$downloads" = 0 ]; then
    log "skipped (--no-downloads)"
  elif [ ! -d "$DL" ]; then
    log "no download folder $DL (CHAOS_DL_DIR): skipped"
  elif [ "$have" -ge "$LATEST" ]; then
    log "the site's downloads are release $have already"
  elif update_downloads; then
    log "downloads: release $LATEST"
  else
    warn="$warn downloads"; log "WARN: the downloads were not replaced (the old files stay)"
  fi

  say "STEP 9/9 site"
  if [ "$site" = 0 ]; then
    log "skipped (--no-site)"
  elif g diff --quiet "$cur" HEAD -- website/; then
    log "website/ did not change"
  elif [ ! -r "$SITE_ENV" ]; then
    log "website/ changed, but there is no $SITE_ENV (CHAOS_SITE_ENV): run website/install_site.sh by hand"
    warn="$warn site"
  elif "$REPO/website/install_site.sh" "$ENVFILE" "$SITE_ENV" 2>&1 | tail -n 25; [ "${PIPESTATUS[0]}" = 0 ]; then
    log "site installed again"
  else
    warn="$warn site"; log "WARN: install_site.sh failed (above)"
  fi

  if [ -n "$warn" ]; then
    finish warn "server on $(g rev-parse --short HEAD), winpkg-$LATEST; not done:$warn (see above)" 3
  fi
  finish ok "server on $(g rev-parse --short HEAD), winpkg-$LATEST${prev_release:+ (was $prev_release)}" 0
}

# the release's client packages into the download folder, one at a time: temp name, checked, NAME.prev, rename
update_downloads() {
  local real name tmp sha size json="" first=1
  real=$(readlink -f "$DL") || return 1
  for name in $CLIENT_ASSETS; do
    [ -n "$(asset_info "$name")" ] || { log "winpkg-$LATEST has no $name: kept the old one"; continue; }
    tmp="$real/.$name.new"
    rm -f "$tmp"
    if ! fetch_asset "$name" "$tmp"; then rm -f "$tmp"; return 1; fi
    sha=$(sha256sum "$tmp" | cut -d' ' -f1) size=$(stat -c %s "$tmp")
    chmod 644 "$tmp"
    # the old file stays reachable all the time: a hard link as NAME.prev, then the rename replaces NAME at once
    if [ -f "$real/$name" ]; then ln -f "$real/$name" "$real/$name.prev" || cp -p "$real/$name" "$real/$name.prev"; fi
    if [ -f "$real/$name.sha256" ]; then cp -p "$real/$name.sha256" "$real/$name.sha256.prev"; fi
    mv -f "$tmp" "$real/$name"
    printf '%s  %s\n' "$sha" "$name" > "$real/.$name.sha256.new"
    chmod 644 "$real/.$name.sha256.new"
    mv -f "$real/.$name.sha256.new" "$real/$name.sha256"
    [ "$first" = 1 ] || json+=","
    first=0
    json+="\"$name\":{\"size\":$size,\"sha256\":\"$sha\"}"
    log "$name: release $LATEST in place (the old file: $name.prev)"
  done
  [ -f "$real/downloads.json" ] && cp -p "$real/downloads.json" "$real/downloads.json.prev"
  printf '{"release":%d,"tag":"winpkg-%d","updated":"%s","files":{%s}}\n' "$LATEST" "$LATEST" \
    "$(date -u '+%Y-%m-%d %H:%M UTC')" "$json" > "$real/.downloads.json.new"
  chmod 644 "$real/.downloads.json.new"
  mv -f "$real/.downloads.json.new" "$real/downloads.json"
  state_set "dl_release=$LATEST"
}

# ------------------------------------------------------------------------------------------------ rollback
cmd_rollback() {
  lock
  local prev real name
  prev=$(state_get prev_commit)
  [ -n "$prev" ] || die "nothing recorded to roll back to ($STATE)"
  state_set "status=running" "result=" "time=$(date '+%F %T')"
  say "STEP 1/2 server"
  log "rollback to $(g rev-parse --short "$prev" 2>/dev/null || echo "$prev"), release $(state_get prev_release)"
  if ! restore_server; then
    finish failed "the rollback did not bring the server up: docs/LAUNCH.md \"Incident runbook\"" 1
  fi
  state_set "prev_commit=" "engine_backup="
  say "STEP 2/2 downloads"
  real=$(readlink -f "$DL" 2>/dev/null || true)
  if [ -n "$real" ] && [ -f "$real/downloads.json.prev" ]; then
    for name in $CLIENT_ASSETS; do
      [ -f "$real/$name.prev" ] && mv -f "$real/$name.prev" "$real/$name"
      [ -f "$real/$name.sha256.prev" ] && mv -f "$real/$name.sha256.prev" "$real/$name.sha256"
    done
    mv -f "$real/downloads.json.prev" "$real/downloads.json"
    log "downloads back to the previous files"
  else
    log "no previous downloads"
  fi
  finish ok "rolled back; the server is online (the database and the client update were not changed)" 0
}

case ${1:-} in
  check) shift; [ $# -eq 0 ] || die "check takes no arguments"; cmd_check ;;
  apply) shift; cmd_apply "$@" ;;
  rollback) shift; [ $# -eq 0 ] || die "rollback takes no arguments"; cmd_rollback ;;
  -h|--help|'') sed -n '3,/^set -uo/p' "$0" | sed '$d; s/^# \{0,1\}//' ;;
  *) die "unknown command $1 (check, apply, rollback)" ;;
esac
