#!/usr/bin/env bash
# shellcheck source=/dev/null disable=SC2015
# Cinders of Chaos: update the live server of the Linux kit layout (/opt/chaos-trial) from GitHub, for the admin app's
# "Atualizar servidor" (docs/ADMIN_APP.md) through chaos-ctl.sh update-check / update-apply / update-rollback.
# Run as root. The routine it automates: docs/LAUNCH.md "Updating the kit server (admin app)".
#
# usage: chaos_kit_update.sh check
#        chaos_kit_update.sh apply [--no-client] [--no-downloads] [--no-site] [--no-map]
#        chaos_kit_update.sh downloads [--force]
#        chaos_kit_update.sh rollback
#
# check     key=value lines: branch, local_commit, remote_commit, behind, ahead, commit (one per new commit, newest
#           first, at most 15: short hash and subject), installed_release, latest_release, needs_engine, map_master,
#           installed_map, needs_map, published_client, needs_client, downloads_release, needs_downloads,
#           website_changed, update_available, running, last_status, last_result. Fetches the branch and the map
#           master's metadata (CHAOS_MAP_BRANCH); changes nothing else.
# apply     the update, in steps (each starts with a "STEP n/10 name" line; the last line is "RESULT status: text"):
#            1 check      lock, clean checkout not ahead of the branch, the newest winpkg-N release of CHAOS_RELEASE_REPO
#            2 download   when the release is newer than the installed one: CindersOfChaos-Server-Linux.tar.gz (https
#                         only, size against GitHub's, SHA-256 printed and compared with GitHub's digest), the engine
#                         taken out of it with a checked tar reader, ldd finds every library
#            3 map        the map master (server/README.md "Map master": the owner's edited map, world/ of the branch
#                         CHAOS_MAP_BRANCH, default windows-assets): when its version is newer than the installed map's
#                         (the marker data/world/<map>.otbm.master.json), its files are fetched (a shallow fetch without
#                         blobs; git takes only world/), every part checked against SHA256SUMS and the whole map
#                         decompressed and checked against MAP_MASTER.json. No branch or no master: skipped
#                         (--no-map skips it)
#            4 backup     server/tools/backup.sh with the server up (save first, database dump, config.lua + data/)
#            5 install    the XP rates saved (chaos_config_rates.py), git checkout of the branch, the server stopped, the
#                         engine replaced (the old one kept as tfs.antes-N), the new map master in place of the map
#                         (map_master.py install: the old map kept as CHAOS_MAP_BACKUP_DIR/<map>.otbm.<timestamp>, the
#                         newest 3 stay), install_all.py --no-sql (its map steps find their work in place), the rates put
#                         back, the kit's helper files (clientservices.py, helpai, start / stop scripts) brought up to
#                         date, the players' changelog (data/changelog/changelog.json, server/tools/gen_changelog.py;
#                         a shallow checkout gets about 100 days of history first; never fails the update; also run
#                         when nothing else changed and after a client update is published), the server folder owned
#                         by the unit's user
#            6 database   the server started (the kit's MariaDB runs inside the unit), the database waited for,
#                         install_all.py --only sql, then a restart so the engine starts on the new tables (and map)
#            7 verify     the unit active and "Server Online" in the log within CHAOS_BOOT_TIMEOUT seconds
#                         A failure in steps 5-7 rolls the server back: engine, config.lua and data/ from the backup,
#                         the map from its backup, the previous commit, started and verified again (RESULT rolled-back).
#                         The database keeps the new tables (the SQL files only add; a full restore is the runbook's).
#            8 client     publish_client_update.sh winpkg-N when the release is newer than the live client update
#                         (--no-client skips it)
#            9 downloads  the release's Windows zip and Linux tar.gz into CHAOS_DL_DIR: temporary name, size and
#                         SHA-256 checked, the old file kept as NAME.prev, then renamed; NAME.sha256 and downloads.json
#                         (the downloads page shows release, date, size, checksum) (--no-downloads skips it)
#           10 site       website/install_site.sh when website/ changed since the site was last installed (state
#                         site_commit; else since this update's start) and CHAOS_SITE_ENV exists
#                         (--no-site skips it)
#           Steps 8-10 never undo the server update: a failure there ends with RESULT warn.
# downloads only step 9, on its own (no server restart, no code change): the newest release's Windows zip and Linux
#           tar.gz into CHAOS_DL_DIR, the same checks, NAME.prev, NAME.sha256 and downloads.json. For the case where the
#           signed client update was published (publish-update) but the site's download link still serves an older
#           package: a client from that older zip mounts the update over it. Nothing to do when the downloads are the
#           newest release's already (--force replaces them anyway). Exit: 0 ok, 1 failed.
# rollback  back to the state before the last apply: engine, config.lua and data/, the map (when that apply replaced
#           it), the previous commit, the download files (NAME.prev); started and verified.
#
# Settings (environment; chaos-ctl.sh passes its /etc/chaos/ctl.conf keys of the same names):
#   CHAOS_REPO /opt/chaos/repo         CHAOS_UPDATE_BRANCH main         CHAOS_RELEASE_REPO lucas1089/cinders-of-chaos
#   CHAOS_KIT_DIR /opt/chaos-trial     CHAOS_SERVER_DIR $KIT/server     CHAOS_ENV $KIT/chaos.env (CHAOS_DB_*)
#   CHAOS_UNIT chaos-server            CHAOS_LOG $KIT/logs/server.log   CHAOS_MYSQL $KIT/mariadb/bin/mariadb
#   CHAOS_KIT_STATE /var/lib/chaos/kit-update   CHAOS_WORK_DIR /var/tmp   CHAOS_BOOT_TIMEOUT 900
#   CHAOS_SITE_DIR /var/www/chaos      CHAOS_DL_DIR $SITE/dl            CHAOS_SITE_ENV /etc/chaos/site.env
#   CHAOS_MAP_BRANCH windows-assets    CHAOS_MAP_BACKUP_DIR $KIT/map-backups
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
MAP_BRANCH=${CHAOS_MAP_BRANCH:-windows-assets}
MAP_BACKUPS=${CHAOS_MAP_BACKUP_DIR:-$KIT/map-backups}
SERVER_ASSET=CindersOfChaos-Server-Linux.tar.gz
CLIENT_ASSETS="CindersOfChaos-Client-Windows.zip CindersOfChaos-Client-Linux.tar.gz"
STATE="$STATE_DIR/state"

say() { printf '%s\n' "$*"; }
log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }
die() { printf 'chaos_kit_update: %s\n' "$*" >&2; exit 1; }

[[ $GHREPO =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "CHAOS_RELEASE_REPO must be OWNER/REPO"
[[ $BRANCH =~ ^[A-Za-z0-9][A-Za-z0-9._/-]{0,99}$ ]] && [[ $BRANCH != *..* ]] || die "bad CHAOS_UPDATE_BRANCH"
[[ $MAP_BRANCH =~ ^[A-Za-z0-9][A-Za-z0-9._/-]{0,99}$ ]] && [[ $MAP_BRANCH != *..* ]] || die "bad CHAOS_MAP_BRANCH"
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
# the kit's helper files beside the engine, from this checkout (the same list as tools/linux/package_server.sh): a kit
# made from an older package lacks the newer ones (clientservices.py: the login-screen services; live log 2026-10-21)
# and keeps old start / stop scripts. Copied when missing or different; a source missing in the checkout is skipped.
# the players' changelog (server/README.md "Changelog"): server/tools/gen_changelog.py writes
# $SERVER/data/changelog/changelog.json from the history of this checkout; patchnotes.lua reads it again within a
# minute, so no restart is needed for it. The kit's checkout may be a shallow clone (docs/HOST_TRIAL.md: git clone
# --depth 1): then about 100 days of the branch and the winpkg-N tags are fetched first (one bounded fetch); a full
# checkout only gets the tags (never pruned here, so a version GitHub dropped stays known). Never fails the update:
# a problem is logged and the old file stays.
changelog() {
  local gen="$REPO/server/tools/gen_changelog.py" out="$SERVER/data/changelog/changelog.json" since pub
  [ -f "$gen" ] || { log "changelog: no server/tools/gen_changelog.py in this checkout: skipped"; return 0; }
  if [ "$(g rev-parse --is-shallow-repository 2>/dev/null)" = true ]; then
    since=$(date -d '-100 days' +%F 2>/dev/null || echo 2000-01-01)
    g fetch --quiet --shallow-since="$since" origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH" \
      '+refs/tags/winpkg-*:refs/tags/winpkg-*' 2>/dev/null || log "changelog: could not fetch more history (the list may be short)"
  else
    g fetch --quiet origin '+refs/tags/winpkg-*:refs/tags/winpkg-*' 2>/dev/null || log "changelog: could not fetch the winpkg tags"
  fi
  pub=$(published_client)
  if timeout 120 python3 -I "$gen" --repo "$REPO" --out "$out" --published-client "${pub:-0}" 2>&1 | tail -n 3 \
    && [ "${PIPESTATUS[0]}" = 0 ]; then
    return 0
  fi
  log "WARN: the changelog was not written (the old file stays)"
  return 0
}

sync_sidecars() {
  local pair src dst n=0
  for pair in \
    "server/tools/clientservices.py:$SERVER/tools/clientservices.py:0644" \
    "server/tools/helpai.py:$SERVER/tools/helpai.py:0644" \
    "server/tools/helpai_config.json:$SERVER/tools/helpai_config.json:0644" \
    "server/tools/rsa_key.py:$SERVER/tools/rsa_key.py:0644" \
    "website/overlay/plugins/chaos/wiki/wiki_data.json:$SERVER/tools/wiki_data.json:0644" \
    "tools/linux/server/start-server.sh:$KIT/start-server.sh:0755" \
    "tools/linux/server/stop-server.sh:$KIT/stop-server.sh:0755" \
    "tools/linux/server/add-account.sh:$KIT/add-account.sh:0755"; do
    src="$REPO/${pair%%:*}"; dst=${pair#*:}; dst=${dst%:*}
    [ -f "$src" ] || continue
    if ! cmp -s "$src" "$dst"; then
      mkdir -p "$(dirname "$dst")" && install -m "${pair##*:}" "$src" "$dst" && n=$((n + 1))
    fi
  done
  log "kit helper files: $n updated"
}

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

# ------------------------------------------------------------------------------------------------ the map master
# MAP_STATE: "none" (no branch, or no world/MAP_MASTER.json on it), "error" (the fetch failed) or the master's version.
# The fetch is shallow and without blobs (git fetches a file's blob when it is read), so the large parts of the other
# files of the branch never come down; the checkout of CHAOS_UPDATE_BRANCH is not touched.
map_master_version() {
  local rc
  g ls-remote --exit-code --heads origin "refs/heads/$MAP_BRANCH" >/dev/null 2>&1; rc=$?
  if [ "$rc" = 2 ]; then MAP_STATE=none; return 0; fi
  [ "$rc" = 0 ] || { MAP_STATE=error; return 1; }
  g fetch --quiet --depth=1 --filter=blob:none origin "+refs/heads/$MAP_BRANCH:refs/remotes/origin/$MAP_BRANCH" 2>/dev/null \
    || { MAP_STATE=error; return 1; }
  if ! g cat-file -e "origin/$MAP_BRANCH:world/MAP_MASTER.json" 2>/dev/null; then MAP_STATE=none; return 0; fi
  MAP_STATE=$(g show "origin/$MAP_BRANCH:world/MAP_MASTER.json" 2>/dev/null | python3 -I -c \
    'import json, sys; v = json.load(sys.stdin)["version"]; assert isinstance(v, int) and v > 0; print(v)' 2>/dev/null) \
    || { MAP_STATE=error; return 1; }
}
# the version of the map master installed in the server folder (its marker next to the map of config.lua's mapName), 0
installed_map() {
  python3 -I - "$SERVER" <<'PY' 2>/dev/null || echo 0
import json, os, re, sys
cfg = open(os.path.join(sys.argv[1], 'config.lua'), encoding='latin-1').read()
name = re.search(r'^\s*mapName\s*=\s*"([A-Za-z0-9_.-]+)"', cfg, re.M).group(1)
v = json.load(open(os.path.join(sys.argv[1], 'data', 'world', name + '.otbm.master.json')))['version']
print(int(v))
PY
}
# the map path of config.lua's mapName
map_path() {
  python3 -I - "$SERVER" <<'PY'
import os, re, sys
cfg = open(os.path.join(sys.argv[1], 'config.lua'), encoding='latin-1').read()
name = re.search(r'^\s*mapName\s*=\s*"([A-Za-z0-9_.-]+)"', cfg, re.M).group(1)
print(os.path.join(sys.argv[1], 'data', 'world', name + '.otbm'))
PY
}
# world/ of the map branch into DEST (only plain file names), and the branch's map_master.py as DEST/../map_master.py
map_fetch_files() {
  local dest=$1 name base n=0
  mkdir -p "$dest" || return 1
  while IFS= read -r name; do
    base=${name#world/}
    [[ $base =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$ ]] || continue
    g cat-file blob "origin/$MAP_BRANCH:$name" > "$dest/$base" || return 1
    n=$((n + 1))
  done < <(g ls-tree --name-only "origin/$MAP_BRANCH" world/)
  log "map master: $n file(s) of $MAP_BRANCH:world/"
  g show "origin/$BRANCH:server/tools/map_master.py" > "$(dirname "$dest")/map_master.py" \
    || { log "origin/$BRANCH has no server/tools/map_master.py"; return 1; }
}

# ------------------------------------------------------------------------------------------------ check
cmd_check() {
  local cur remote work n
  [ -d "$REPO/.git" ] || g rev-parse --git-dir >/dev/null 2>&1 || die "no git checkout at $REPO (CHAOS_REPO)"
  say "branch=$BRANCH"
  g fetch --quiet origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH" 2>/dev/null || die "git fetch origin $BRANCH failed"
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
  local needs_map=no imap
  map_master_version || true
  imap=$(installed_map)
  case $MAP_STATE in
    none) say "map_master=none" ;;
    error) say "map_master=unknown"; needs_map=unknown ;;
    *) say "map_master=$MAP_STATE"; [ "$imap" -lt "$MAP_STATE" ] && needs_map=yes ;;
  esac
  say "installed_map=$imap"
  say "needs_map=$needs_map"
  n=$(published_client)
  say "published_client=$n"
  [ -n "$LATEST" ] && [ "$n" -lt "$LATEST" ] && [ -n "$(asset_info CindersOfChaos-Client-Windows.zip)" ] \
    && say "needs_client=yes" || say "needs_client=no"
  n=$(dl_release)
  say "downloads_release=$n"
  [ -n "$LATEST" ] && [ "$n" -lt "$LATEST" ] && [ -d "$DL" ] && say "needs_downloads=yes" || say "needs_downloads=no"
  # the site counts from the commit it was last installed from (a checkout moved by hand skips no site change)
  n=$(state_get site_commit); [ -n "$n" ] && g cat-file -e "$n^{commit}" 2>/dev/null || n=$cur
  if g diff --quiet "$n" "$remote" -- website/ 2>/dev/null; then say "website_changed=no"; else say "website_changed=yes"; fi
  if [ "$cur" != "$remote" ] || [ "$(state_get installed_release)" != "$LATEST" ] || [ "$needs_map" = yes ]; then
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
  local map_bk target
  map_bk=$(state_get map_backup)
  if [ -n "$map_bk" ] && [ -f "$map_bk" ] && target=$(map_path); then
    if cp -p "$map_bk" "$target.rollback-new" && mv -f "$target.rollback-new" "$target"; then
      log "map put back from $map_bk"
    else
      rm -f "$target.rollback-new"; log "FAIL: could not put the map back from $map_bk"
    fi
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
  local client=1 downloads=1 site=1 map=1 a
  for a in "$@"; do
    case $a in
      --no-client) client=0 ;; --no-downloads) downloads=0 ;; --no-site) site=0 ;; --no-map) map=0 ;;
      *) die "apply [--no-client] [--no-downloads] [--no-site] [--no-map]" ;;
    esac
  done
  lock
  local work warn="" cur remote installed prev_release engine_new="" map_new="" stamp from dirty rates
  stamp=$(date '+%Y%m%d-%H%M%S')
  state_set "status=running" "result=" "time=$(date '+%F %T')"
  say "STEP 1/10 check"
  for tool in git python3 curl systemctl tar sha256sum ldd; do
    command -v "$tool" >/dev/null || finish failed "$tool is missing" 1
  done
  [ -f "$SERVER/config.lua" ] && [ -d "$SERVER/data" ] || finish failed "$SERVER is not a server folder" 1
  [ -r "$ENVFILE" ] || finish failed "cannot read $ENVFILE (CHAOS_ENV)" 1
  dirty=$(g status --porcelain --untracked-files=no 2>&1) || finish failed "$REPO is not a git checkout" 1
  [ -z "$dirty" ] || { say "$dirty" | head -n 10; finish failed "the checkout $REPO has changed files (above): nothing done" 1; }
  g fetch --quiet origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH" || finish failed "git fetch origin $BRANCH failed" 1
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

  say "STEP 2/10 download"
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

  say "STEP 3/10 map"
  local imap
  imap=$(installed_map)
  if [ "$map" = 0 ]; then
    log "skipped (--no-map)"
  elif ! map_master_version; then
    finish failed "cannot read the map master of $MAP_BRANCH: nothing changed" 1
  elif [ "$MAP_STATE" = none ]; then
    log "no map master ($MAP_BRANCH:world/MAP_MASTER.json): the map stays"
  elif [ "$imap" -ge "$MAP_STATE" ]; then
    log "the map is the map master's version $imap already"
  else
    log "map master: version $MAP_STATE (installed: ${imap/#0/none})"
    map_fetch_files "$work/map/world" || finish failed "could not fetch the map master: nothing changed" 1
    python3 -I "$work/map/map_master.py" verify "$work/map/world" --deep 2>&1 | tail -n 5
    [ "${PIPESTATUS[0]}" = 0 ] || finish failed "the map master was refused (above): nothing changed" 1
    map_new=$MAP_STATE
  fi

  if [ "$cur" = "$remote" ] && [ -z "$engine_new" ] && [ -z "$map_new" ]; then
    log "no new code, no new engine and no new map: the server is not restarted"
    changelog
    state_set "installed_release=$LATEST"
    prev_release=$installed
  else
    say "STEP 4/10 backup"
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

    say "STEP 5/10 install"
    rates="$STATE_DIR/rates-$stamp.json"
    python3 -I "$REPO/server/deploy/chaos_config_rates.py" save "$SERVER/config.lua" "$rates" \
      || finish failed "cannot read the rates of config.lua: nothing changed" 1
    prev_release=$installed
    state_set "prev_commit=$cur" "prev_release=$installed" "data_archive=$archive" "engine_backup=" "target_commit=$remote" \
      "target_release=$LATEST" "map_backup="
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
    if [ "$ok" = 1 ] && [ -n "$map_new" ]; then
      local mout map_bk
      log "map master version $map_new in place of the map:"
      mout=$(python3 -I "$work/map/map_master.py" install "$work/map/world" "$SERVER" --backup-dir "$MAP_BACKUPS" \
        --stamp "$stamp" 2>&1); a=$?
      say "$mout" | tail -n 12
      map_bk=$(sed -n 's/^backup=//p' <<< "$mout" | tail -n 1)
      [ -n "$map_bk" ] && state_set "map_backup=$map_bk"
      [ "$a" = 0 ] || { ok=0; log "FAIL: the map master was not installed"; }
    fi
    if [ "$ok" = 1 ]; then
      log "install_all.py (every step but sql; the database is down with the server):"
      install_all --no-sql 2>&1 | tail -n 60
      [ "${PIPESTATUS[0]}" = 0 ] || { ok=0; log "FAIL: install_all.py failed"; }
    fi
    if [ "$ok" = 1 ]; then
      python3 -I "$REPO/server/deploy/chaos_config_rates.py" restore "$SERVER/config.lua" "$rates" || ok=0
      sync_sidecars
      changelog
      own_server
    fi
    if [ "$ok" = 1 ]; then
      say "STEP 6/10 database"
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
      say "STEP 7/10 verify"
      wait_online "$from" || ok=0
    fi
    if [ "$ok" = 0 ]; then
      say "STEP 7/10 rollback"
      if restore_server; then
        finish rolled-back "the update failed; the server is back on the previous version and online (the database keeps the new tables)" 2
      fi
      finish failed "the update failed and the rollback did not bring the server up: docs/LAUNCH.md \"Incident runbook\"" 1
    fi
    state_set "installed_release=$LATEST" "deployed_commit=$remote"
    [ -n "$map_new" ] && state_set "map_version=$map_new"
    log "server updated: $(g rev-parse --short HEAD), winpkg-$LATEST${map_new:+, map master $map_new}"
  fi

  say "STEP 8/10 client"
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
      changelog  # its client entries are no longer "next client update"
    else
      warn="$warn client"; log "WARN: the client update was not published (above)"
    fi
  fi

  say "STEP 9/10 downloads"
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

  say "STEP 10/10 site"
  local sitebase
  sitebase=$(state_get site_commit); [ -n "$sitebase" ] && g cat-file -e "$sitebase^{commit}" 2>/dev/null || sitebase=$cur
  if [ "$site" = 0 ]; then
    log "skipped (--no-site)"
  elif g diff --quiet "$sitebase" HEAD -- website/; then
    log "website/ did not change"
  elif [ ! -r "$SITE_ENV" ]; then
    log "website/ changed, but there is no $SITE_ENV (CHAOS_SITE_ENV): run website/install_site.sh by hand"
    warn="$warn site"
  elif "$REPO/website/install_site.sh" "$ENVFILE" "$SITE_ENV" 2>&1 | tail -n 25; [ "${PIPESTATUS[0]}" = 0 ]; then
    log "site installed again"
    state_set "site_commit=$(g rev-parse HEAD)"
  else
    warn="$warn site"; log "WARN: install_site.sh failed (above)"
  fi

  if [ -n "$warn" ]; then
    finish warn "server on $(g rev-parse --short HEAD), winpkg-$LATEST; not done:$warn (see above)" 3
  fi
  finish ok "server on $(g rev-parse --short HEAD), winpkg-$LATEST${prev_release:+ (was $prev_release)}${map_new:+, map master $map_new}" 0
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
  state_set "prev_commit=" "engine_backup=" "map_backup="
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

# ------------------------------------------------------------------------------------------------ downloads
cmd_downloads() {
  local force=0 a work have
  for a in "$@"; do
    case $a in
      --force) force=1 ;;
      *) die "downloads [--force]" ;;
    esac
  done
  lock
  state_set "status=running" "result=" "time=$(date '+%F %T')"
  say "STEP 1/1 downloads"
  for tool in python3 curl sha256sum; do
    command -v "$tool" >/dev/null || finish failed "$tool is missing" 1
  done
  [ -d "$DL" ] || finish failed "no download folder $DL (CHAOS_DL_DIR)" 1
  work=$(mktemp -d "$WORKBASE/chaos-kit-update.XXXXXX") || finish failed "no work folder in $WORKBASE" 1
  trap 'rm -rf "$work"; rm -f "$CHAOS_KIT_COPY"' EXIT
  REL=$(releases "$work/rel.json") || finish failed "cannot read the releases of $GHREPO" 1
  LATEST=$(sed -n 's/^latest=//p' <<< "$REL")
  have=$(dl_release)
  log "downloads: the site has release $have, newest winpkg-$LATEST"
  if [ "$have" -ge "$LATEST" ] && [ "$force" = 0 ]; then
    finish ok "the site's downloads are release $have already (nothing changed; --force replaces them)" 0
  fi
  update_downloads || finish failed "the downloads were not replaced (the old files stay)" 1
  finish ok "the site's downloads are release $LATEST now" 0
}

case ${1:-} in
  check) shift; [ $# -eq 0 ] || die "check takes no arguments"; cmd_check ;;
  apply) shift; cmd_apply "$@" ;;
  downloads) shift; cmd_downloads "$@" ;;
  rollback) shift; [ $# -eq 0 ] || die "rollback takes no arguments"; cmd_rollback ;;
  -h|--help|'') sed -n '3,/^set -uo/p' "$0" | sed '$d; s/^# \{0,1\}//' ;;
  *) die "unknown command $1 (check, apply, downloads, rollback)" ;;
esac
