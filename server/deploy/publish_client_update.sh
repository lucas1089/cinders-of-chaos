#!/usr/bin/env bash
# Cinders of Chaos: publish a signed client update on the website from a client package (docs/LAUNCH.md "Publishing a
# client update", client/MANIFEST.md "Signed updater", website/README.md "Client updates").
#
# usage: publish_client_update.sh [options] TAG|ZIP          (as root: the private key is readable by root only)
#
#   TAG   a release of the repository (winpkg-46): downloads its CindersOfChaos-Client-Windows.zip
#   ZIP   a local client zip instead (not offered by chaos-ctl.sh, which publishes release tags only)
#
#   --version N       the manifest version. Default: the package's baseline (Services.update.baseline in its init.lua,
#                     base patch 0101: the release number the package was built as), else the number at the end of the
#                     tag (winpkg-46 -> 46), else (a ZIP of an older package) the published version + 1. With a
#                     baseline the version must be that baseline: its clients never apply a manifest below their own
#                     baseline, so the files of release N are always update N (a tag of another number is refused).
#                     It must be above the published one: clients refuse an older manifest.
#   --min-package N   clients whose package (Services.update.package = the workflow input client_build) is below N
#                     must download the new package and cannot log in. Default: this package's own client build
#                     (Services.update.package in its init.lua; BUILD_INFO.txt "client build: N" of older packages).
#                     At least 13: the update blobs are encrypted and only build 13 and newer decrypt them.
#   --key-index N     which key of CHAOS_CLIENT_KEY ("old,new" during a rotation) encrypts the blobs, 1-based. A
#                     packed package (chaos.pack) needs none: the key that opens its pack is the one.
#   (launcher, O314) a packed client folder that also holds CindersLauncher.exe: its .exe, .dll and chaos.pack files are
#                     published as the manifest's "native" section (client/MANIFEST.md "Game launcher"), plain blobs
#                     under updates/live/native/, for the launcher; the Lua updater never reads that section.
#   (phone, O313)     every publish also writes the manifest's "android" section: the list of files the Android client
#                     downloads on first start (all but layouts/mobile/; client/MANIFEST.md "Phone data"). No option
#                     here; make_update_manifest.py build has --android-exclude and --no-android.
#   --check-only     no publish: only the web server check of the published manifest (below)
#   --no-check        skip the web server check
#   --keep            keep the work folder (the download and the extracted client) for a look afterwards
#
# Steps: download (curl -fL, https only) into a new empty work folder, size check, SHA-256 printed; extract with
# python3 -I zipfile (absolute paths, "..", links and odd names refused, at most 8 GB unpacked); find the client
# folder: a packed client (build 13+: the exe and chaos.pack) is decrypted with CHAOS_CLIENT_KEY into the work folder
# (make_update_manifest.py unpack; a development pack is refused), an older loose one is used as it is (init.lua,
# modules/, data/things/1098/); check that the package's public key (init.lua) is the one of the private key;
# a single data/things/*/<name>.spr is split into sprite shards (client/tools/sprites/spr_shards.py; the update always
# ships shards: the updater refuses a file over 1 GiB) or, next to its shard set, left out;
# client/tools/make_update_manifest.py build (every blob ENCRYPTED with a key derived from CHAOS_CLIENT_KEY, blobs
# first, manifest.json last, then the old blobs and any plain ones removed) and verify (decrypts every blob and checks
# the signed plaintext SHA-256); then the web server check: GET the manifest URL (the package's
# Services.update.manifest, or CHAOS_UPDATE_URL) and compare it with the file just written, its Content-Type and
# Cache-Control, and a Range request on one blob (206 expected).
#
# Settings (environment; chaos-ctl.sh passes its /etc/chaos/ctl.conf keys of the same names):
#   CHAOS_SITE_DIR        /var/www/chaos      the site folder; the update goes to $CHAOS_SITE_DIR/updates/live
#   CHAOS_UPDATE_KEY      /etc/chaos/update-key.hex   the private key (a path, never the key itself)
#   CHAOS_CLIENT_KEY      (from CHAOS_ENV)    the client guard secret (64 hex digits; "old,new" in a rotation), the
#                                             same value the game server reads. The update blobs are encrypted with a
#                                             key derived from it (client/MANIFEST.md "Signed updater"). Unset: read
#                                             from the CHAOS_CLIENT_KEY= line of CHAOS_ENV. Never printed. Without it
#                                             nothing is published (updates are never served plain).
#   CHAOS_ENV             /etc/chaos/chaos.env  the game server's environment file (only CHAOS_CLIENT_KEY is read)
#   CHAOS_UPDATE_PUBLIC   (empty)             the public key, 64 hex digits; else /etc/chaos/update-key.pub when it
#                                             exists; else derived from the private key. All that are given must agree.
#   CHAOS_UPDATE_REPO     lucas1089/cinders-of-chaos      the GitHub repository of the releases
#   CHAOS_UPDATE_ASSET    CindersOfChaos-Client-Windows.zip
#   CHAOS_UPDATE_URL      (empty)             the public manifest URL for the check (default: the package's own)
#   CHAOS_WORK_DIR        /var/tmp            where the work folder is made (needs about 4x the zip size free: the spr is split there)
#   CHAOS_UPDATE_MIN_MB   50                  a smaller download is refused (an error page, a wrong asset)
# Exit: 0 published (a failed web server check only warns), 1 refused or failed, nothing published.
set -euo pipefail
umask 022

SELF=$(readlink -f "$0")
REPO_DIR=$(cd "$(dirname "$SELF")/../.." && pwd)
TOOL="$REPO_DIR/client/tools/make_update_manifest.py"
SHARDS="$REPO_DIR/client/tools/sprites/spr_shards.py"

SITE=${CHAOS_SITE_DIR:-/var/www/chaos}
KEY=${CHAOS_UPDATE_KEY:-/etc/chaos/update-key.hex}
PUBLIC=${CHAOS_UPDATE_PUBLIC:-}
PUBFILE=${CHAOS_UPDATE_PUBLIC_FILE:-/etc/chaos/update-key.pub}
GHREPO=${CHAOS_UPDATE_REPO:-lucas1089/cinders-of-chaos}
ASSET=${CHAOS_UPDATE_ASSET:-CindersOfChaos-Client-Windows.zip}
CHECK_URL=${CHAOS_UPDATE_URL:-}
WORKBASE=${CHAOS_WORK_DIR:-/var/tmp}
MIN_MB=${CHAOS_UPDATE_MIN_MB:-50}

say() { printf '%s\n' "$*"; }
die() { printf 'publish: %s\n' "$*" >&2; exit 1; }
usage() { sed -n '2,/^set -euo/p' "$SELF" | sed '$d' | sed 's/^# \{0,1\}//'; }
isnum() { [[ ${1:-} =~ ^[0-9]{1,9}$ ]]; }

ENVFILE=${CHAOS_ENV:-/etc/chaos/chaos.env}
ENCRYPTED_MIN_PACKAGE=13

VERSION="" MINPKG="" CHECK=1 PUBLISH=1 KEEP=0 SRC="" KEYIDX=""
while [ $# -gt 0 ]; do
  case $1 in
    --version) isnum "${2:-}" || die "--version N"; VERSION=$((10#$2)); shift 2 ;;
    --key-index) { isnum "${2:-}" && [ "$((10#$2))" -ge 1 ]; } || die "--key-index N (1, 2...)"; KEYIDX=$((10#$2)); shift 2 ;;
    --min-package) isnum "${2:-}" || die "--min-package N"; MINPKG=$((10#$2)); shift 2 ;;
    --check-only) PUBLISH=0; shift ;;
    --no-check) CHECK=0; shift ;;
    --keep) KEEP=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; { [ $# -eq 1 ] && [ -z "$SRC" ]; } || die "one TAG or ZIP"; SRC=$1; shift ;;
    -*) die "unknown option $1 (--help)" ;;
    *) [ -z "$SRC" ] || die "one TAG or ZIP"; SRC=$1; shift ;;
  esac
done

LIVE="$SITE/updates/live"
[[ $SITE == /* ]] || die "CHAOS_SITE_DIR must be an absolute path"
[ -d "$SITE" ] || die "no site folder $SITE (CHAOS_SITE_DIR)"
command -v python3 >/dev/null || die "python3 is missing"
[ -f "$TOOL" ] || die "no $TOOL"

# the web server check: what a client gets from the manifest URL ($1), compared with the local manifest.json
web_check() {
  local url=$1 dir hdr code ctype cache blob bcode ok=0
  if [ -z "$url" ]; then
    say "check: no manifest URL (the package's init.lua has none; set CHAOS_UPDATE_URL); skipped"
    return 0
  fi
  command -v curl >/dev/null || { say "check: WARN curl is missing"; return 1; }
  dir=$(mktemp -d)
  hdr="$dir/h"
  code=$(curl -sS -o "$dir/body" -D "$hdr" -w '%{http_code}' --max-time 30 "$url?t=$(date +%s)" 2>"$dir/err") \
    || { say "check: WARN $url: $(head -c 300 "$dir/err")"; rm -rf "$dir"; return 1; }
  ctype=$(grep -i '^content-type:' "$hdr" | tail -n 1 | tr -d '\r' | cut -d: -f2- | sed 's/^ *//')
  cache=$(grep -i '^cache-control:' "$hdr" | tail -n 1 | tr -d '\r' | cut -d: -f2- | sed 's/^ *//')
  say "check: GET $url -> HTTP $code, Content-Type: ${ctype:-none}, Cache-Control: ${cache:-none}"
  [ "$code" = 200 ] || { say "check: WARN the manifest URL does not answer 200"; ok=1; }
  if [ "$code" = 200 ] && [ -f "$LIVE/manifest.json" ]; then
    if cmp -s "$dir/body" "$LIVE/manifest.json"; then
      say "check: the served manifest is the published one"
    else
      say "check: WARN the served manifest differs from $LIVE/manifest.json (another folder, or a cache in front)"
      ok=1
    fi
  fi
  [[ ${ctype,,} == application/json* ]] || { say "check: WARN Content-Type should be application/json"; ok=1; }
  [[ ${cache,,} == *no-cache* ]] || { say "check: WARN Cache-Control should be no-cache (website/README.md \"Client updates\")"; ok=1; }
  blob=$(python3 -I - "$LIVE/manifest.json" <<'PY' 2>/dev/null || true
import json, sys
m = json.loads(json.load(open(sys.argv[1]))['payload'])
big = max(m['files'], key=lambda f: f['size'])
print(big['blob'])
PY
)
  if [ -n "$blob" ]; then
    bcode=$(curl -sS -o /dev/null -D "$hdr" -w '%{http_code}' --max-time 30 -r 0-15 \
      "${url%manifest.json}files/${blob:0:2}/$blob" 2>/dev/null || echo 000)
    cache=$(grep -i '^cache-control:' "$hdr" | tail -n 1 | tr -d '\r' | cut -d: -f2- | sed 's/^ *//')
    say "check: Range GET of the largest blob -> HTTP $bcode, Cache-Control: ${cache:-none}"
    [ "$bcode" = 206 ] || { say "check: WARN a blob Range request should answer 206 (large files come in parts)"; ok=1; }
  fi
  rm -rf "$dir"
  [ "$ok" = 0 ] && say "check: ok"
  return "$ok"
}

if [ "$PUBLISH" = 0 ]; then
  [ -f "$LIVE/manifest.json" ] || die "nothing published in $LIVE"
  url=$CHECK_URL
  [ -n "$url" ] || die "--check-only needs CHAOS_UPDATE_URL (the public manifest URL)"
  web_check "$url" || exit 1
  exit 0
fi

[ -n "$SRC" ] || die "TAG or ZIP (--help)"
[ -r "$KEY" ] || die "cannot read the private key $KEY (CHAOS_UPDATE_KEY; run as root)"

# the blob key: the client guard secret of the game server (never printed, only passed on in the environment)
if [ -z "${CHAOS_CLIENT_KEY:-}" ] && [ -r "$ENVFILE" ]; then
  CHAOS_CLIENT_KEY=$(sed -n 's/^[[:space:]]*\(export[[:space:]]\{1,\}\)\{0,1\}CHAOS_CLIENT_KEY=//p' "$ENVFILE" | tail -n 1 \
    | tr -d " \"'\r")
fi
[ -n "${CHAOS_CLIENT_KEY:-}" ] || die "no CHAOS_CLIENT_KEY (the environment, or a CHAOS_CLIENT_KEY= line in $ENVFILE): the update blobs are encrypted with it and are never published plain"
export CHAOS_CLIENT_KEY

TAG="" ZIP="" NATIVE=""
if [ -f "$SRC" ]; then
  ZIP=$(readlink -f "$SRC")
elif [[ $SRC =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] && [[ $SRC != *..* ]]; then
  TAG=$SRC
else
  die "$SRC: not a local file and not a release tag"
fi
if [ -z "$VERSION" ] && [[ $TAG =~ -([0-9]{1,9})$ ]]; then VERSION=$((10#${BASH_REMATCH[1]})); fi

# one publish at a time
mkdir -p "$SITE/updates"
if command -v flock >/dev/null; then
  exec 9> "$SITE/updates/.publish.lock"
  flock -n 9 || die "another publish is running"
fi

WORK=$(mktemp -d "$WORKBASE/chaos-publish.XXXXXX")
if [ "$KEEP" = 1 ]; then trap 'say "work folder kept: $WORK"' EXIT; else trap 'rm -rf "$WORK"' EXIT; fi
mkdir "$WORK/dl" "$WORK/x"

if [ -n "$TAG" ]; then
  command -v curl >/dev/null || die "curl is missing"
  url="https://github.com/$GHREPO/releases/download/$TAG/$ASSET"
  say "download: $url"
  curl -fL --proto '=https' --proto-redir '=https' --retry 3 --retry-delay 5 --max-filesize 8589934592 \
    -sS -o "$WORK/dl/client.zip" "$url" || die "download failed ($url)"
  ZIP="$WORK/dl/client.zip"
fi
size=$(stat -c %s "$ZIP")
[ "$size" -ge $((MIN_MB * 1024 * 1024)) ] || die "$ZIP: $size bytes, below $MIN_MB MB (an error page or a wrong asset?)"
say "zip: $size bytes, sha256 $(sha256sum "$ZIP" | cut -d' ' -f1)"

# safe extract: every entry must stay inside the empty folder; links, devices and odd names are refused
python3 -I - "$ZIP" "$WORK/x" <<'PY' || die "the zip was refused"
import os, re, stat, sys, zipfile
src, dest = sys.argv[1], os.path.realpath(sys.argv[2])
LIMIT, MAXN = 8 * 1024 ** 3, 200000
with zipfile.ZipFile(src) as z:
    infos = z.infolist()
    if len(infos) > MAXN:
        sys.exit(f'{len(infos)} entries (at most {MAXN})')
    total = 0
    for i in infos:
        n = i.filename
        mode = i.external_attr >> 16
        if (n.startswith(('/', '\\')) or '\\' in n or ':' in n or '\0' in n
                or any(p in ('..', '.') for p in n.rstrip('/').split('/'))):
            sys.exit(f'refused entry {n!r}: unsafe path')
        if stat.S_IFMT(mode) not in (0, stat.S_IFREG, stat.S_IFDIR):
            sys.exit(f'refused entry {n!r}: a link or special file')
        target = os.path.realpath(os.path.join(dest, n))
        if target != dest and not target.startswith(dest + os.sep):
            sys.exit(f'refused entry {n!r}: outside the folder')
        total += i.file_size
        if total > LIMIT:
            sys.exit('more than 8 GB unpacked')
    for i in infos:
        target = os.path.join(dest, i.filename)
        if i.is_dir():
            os.makedirs(target, exist_ok=True)
            continue
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with z.open(i) as f, open(target, 'xb') as out:
            while True:
                block = f.read(1 << 20)
                if not block:
                    break
                out.write(block)
print(f'extracted {len(infos)} entries, {total} bytes')
PY

# the client folder: a packed client (build 13+: the exe and chaos.pack, decrypted here with the key that opens it),
# else a loose one: init.lua, modules/ and data/things/1098/ (the package's CindersOfChaos-Client/)
mapfile -t packs < <(find "$WORK/x" -maxdepth 3 -type f -name chaos.pack)
mapfile -t found < <(find "$WORK/x" -maxdepth 3 -type f -name init.lua -printf '%h\n' | while read -r d; do
  [ -d "$d/modules" ] && [ -d "$d/data/things/1098" ] && printf '%s\n' "$d"; done)
if [ "${#packs[@]}" -gt 0 ]; then
  [ "${#packs[@]}" -eq 1 ] || die "expected one client pack (chaos.pack), found ${#packs[@]}"
  [ "${#found[@]}" -eq 0 ] || die "the zip has both a chaos.pack and a loose client folder; which one is the client?"
  say "client: ${packs[0]#"$WORK/x/"} (packed; decrypted with CHAOS_CLIENT_KEY)"
  out=$(python3 -I "$TOOL" unpack "${packs[0]}" "$WORK/tree") || die "cannot open the client pack (see above)"
  idx=$(printf '%s\n' "$out" | sed -n 's/^key-index=//p')
  isnum "$idx" || die "unpack gave no key index"
  if [ -n "$KEYIDX" ] && [ "$KEYIDX" != "$idx" ]; then
    die "--key-index $KEYIDX, but key $idx of CHAOS_CLIENT_KEY is the one that opens this package"
  fi
  KEYIDX=$idx
  say "pack: opened with key $KEYIDX of CHAOS_CLIENT_KEY"
  # the launcher's files (O314): the program files of the package beside chaos.pack, when it ships the launcher
  packdir=$(dirname "${packs[0]}")
  if [ -f "$packdir/CindersLauncher.exe" ]; then
    NATIVE="$WORK/native"
    mkdir "$NATIVE"
    find "$packdir" -maxdepth 1 -type f \( -name '*.exe' -o -name '*.dll' -o -name chaos.pack \) -print0 \
      | while IFS= read -r -d '' nf; do ln "$nf" "$NATIVE/" 2>/dev/null || cp "$nf" "$NATIVE/"; done
    say "launcher: $(find "$NATIVE" -mindepth 1 -maxdepth 1 | wc -l) native files for the launcher"
  fi
  rm -f "${packs[0]}"
  CLIENT="$WORK/tree"
  { [ -f "$CLIENT/init.lua" ] && [ -d "$CLIENT/modules" ] && [ -d "$CLIENT/data/things/1098" ]; } \
    || die "the client pack holds no client tree (init.lua, modules/, data/things/1098/)"
else
  [ "${#found[@]}" -eq 1 ] || die "expected one client folder (init.lua, modules/, data/things/1098/) or one chaos.pack, found ${#found[@]}"
  CLIENT=${found[0]}
  say "client: ${CLIENT#"$WORK/x/"}"
fi
[ -d "$CLIENT/mods" ] || say "note: the client has no mods/ folder"

# sprite shards (client/MANIFEST.md "Sharded sprites"): the live update always ships the spr as a shard set, never as
# one file. The updater of every client build refuses a manifest with a file over 1 GiB (pair 37's spr is), and a
# client whose pack holds a shard set would keep drawing those shards over a single new spr. A single spr is split
# (and byte-checked) here; one next to its shard set is left out (the client loads the shards).
for spr in "$CLIENT"/data/things/*/*.spr; do
  [ -f "$spr" ] || continue
  name=$(basename "$spr" .spr)
  [[ $name =~ \.[0-9]{3}$ ]] && continue
  dir=$(dirname "$spr")
  if [ -f "$dir/$name.sprshards" ]; then
    say "sprites: ${spr#"$CLIENT/"} is next to its shard set: the shards are published, the single file is not"
  else
    say "sprites: ${spr#"$CLIENT/"} -> shard set $name.sprshards"
    python3 -I "$SHARDS" split "$spr" "$dir" --name "$name" || die "cannot split $spr into sprite shards"
    python3 -I "$SHARDS" verify "$spr" "$dir" --name "$name" || die "the sprite shards of $spr do not match it"
  fi
  rm -f "$spr"
done

# the package's own settings: Services.update in init.lua, the build in BUILD_INFO.txt
info=$(python3 -I - "$CLIENT" <<'PY'
import os, re, sys
d = sys.argv[1]
text = open(os.path.join(d, 'init.lua'), encoding='utf-8', errors='replace').read()
block = re.search(r'\n  update = \{\n(.*?)\n  \}', text, re.S)
def field(name):
    if not block:
        return ''
    m = re.search(r'\n?\s*%s = ("([^"\n]*)"|(\d+))' % name, block.group(1))
    return (m.group(2) if m and m.group(2) is not None else (m.group(3) if m else '')) or ''
build = ''
try:
    m = re.search(r'^client build: *(\d+)', open(os.path.join(d, 'BUILD_INFO.txt'), encoding='utf-8',
                                                   errors='replace').read(), re.M)
    build = m.group(1) if m else ''
except OSError:
    pass
for k, v in (('block', 'yes' if block else ''), ('manifest', field('manifest')), ('key', field('publicKey')),
             ('package', field('package')), ('baseline', field('baseline')), ('build', build)):
    if not re.fullmatch(r'[A-Za-z0-9:/._~-]*', v):
        v = '?'
    print(f'{k}={v}')
PY
) || die "cannot read the client's init.lua"
get() { printf '%s\n' "$info" | sed -n "s/^$1=//p"; }
PKG_URL=$(get manifest) PKG_KEY=$(get key) PKG_PACKAGE=$(get package) PKG_BUILD=$(get build)
PKG_BASELINE=$(get baseline)
isnum "$PKG_BASELINE" || PKG_BASELINE=0
PKG_BASELINE=$((10#$PKG_BASELINE))
[ -n "$(get block)" ] || say "WARN: init.lua has no Services.update block: this exe has no updater (base patch 0031)"
say "package: client build ${PKG_BUILD:-unknown}, Services.update.package ${PKG_PACKAGE:-unset}, baseline ${PKG_BASELINE}, manifest ${PKG_URL:-none}"

# the keys: the derived one, the configured one, the package's own must all be the same
DERIVED=$(python3 -I "$TOOL" pubkey --private "$KEY") || die "cannot read the private key $KEY"
if [ -z "$PUBLIC" ] && [ -f "$PUBFILE" ]; then PUBLIC=$(tr -d ' \r\n' < "$PUBFILE"); fi
if [ -n "$PUBLIC" ]; then
  [[ $PUBLIC =~ ^[0-9a-f]{64}$ ]] || die "the public key (CHAOS_UPDATE_PUBLIC or $PUBFILE) is not 64 lowercase hex digits"
  [ "$PUBLIC" = "$DERIVED" ] || die "the public key $PUBLIC is not the one of $KEY ($DERIVED)"
fi
PUBLIC=$DERIVED
if [ -z "$PKG_KEY" ]; then
  say "WARN: this package's updater is off (no Services.update.publicKey): its players never fetch this update"
elif [ "$PKG_KEY" != "$PUBLIC" ]; then
  die "the package's public key $PKG_KEY is not the one of $KEY ($PUBLIC): its clients would refuse the update"
fi

# min_package: the package's own build unless given
if [ -z "$MINPKG" ]; then
  if [ -n "$PKG_BUILD" ] && [ -n "$PKG_PACKAGE" ] && [ "$PKG_BUILD" != "$PKG_PACKAGE" ]; then
    die "BUILD_INFO.txt says client build $PKG_BUILD but init.lua package $PKG_PACKAGE; give --min-package"
  fi
  MINPKG=${PKG_PACKAGE:-${PKG_BUILD:-0}}
  MINPKG=$((10#$MINPKG))
fi
if [ -n "$PKG_PACKAGE" ] && [ "$MINPKG" -gt "$((10#$PKG_PACKAGE))" ]; then
  die "--min-package $MINPKG is above this package's own $PKG_PACKAGE: its own players would be told to download it again"
fi
if [ "$MINPKG" -lt "$ENCRYPTED_MIN_PACKAGE" ]; then
  die "min_package $MINPKG: the update blobs are encrypted and only client build $ENCRYPTED_MIN_PACKAGE or newer decrypts them (publish a build $ENCRYPTED_MIN_PACKAGE+ package, min_package $ENCRYPTED_MIN_PACKAGE or more)"
fi

# the version: the package's baseline is the version of its files (base patch 0101); clients skip a manifest below
# their own baseline, so these files under another number would be skipped (lower) or downgrade newer packages (higher)
if [ "$PKG_BASELINE" -gt 0 ]; then
  if [ -z "$VERSION" ]; then
    VERSION=$PKG_BASELINE
  elif [ "$VERSION" -ne "$PKG_BASELINE" ]; then
    die "version $VERSION is not this package's baseline $PKG_BASELINE (Services.update.baseline, the release it was built as); its update is version $PKG_BASELINE (give no --version, or the release tag winpkg-$PKG_BASELINE)"
  fi
fi

PREV=$(python3 -I - "$LIVE/manifest.json" <<'PY'
import json, sys
try:
    print(json.loads(json.load(open(sys.argv[1]))['payload'])['version'])
except Exception:
    print(0)
PY
)
if [ -n "$VERSION" ] && [ "$VERSION" -le "$PREV" ]; then
  if [ "$PKG_BASELINE" -gt 0 ]; then
    die "version $VERSION is not above the published $PREV: this package is older than the live update (publish a newer package)"
  fi
  die "version $VERSION is not above the published $PREV (clients refuse an older manifest); give --version $((PREV + 1)) or more"
fi

args=(build "$CLIENT" --out "$LIVE" --key "$KEY" --min-package "$MINPKG")
vargs=(verify "$LIVE" --public "$PUBLIC")
[ -n "$VERSION" ] && args+=(--version "$VERSION")
if [ -n "$NATIVE" ]; then
  isnum "$PKG_PACKAGE" || die "the launcher's files need Services.update.package in init.lua"
  args+=(--native-dir "$NATIVE" --native-package "$((10#$PKG_PACKAGE))" --native-launcher CindersLauncher.exe)
fi
if [ -n "$KEYIDX" ]; then args+=(--key-index "$KEYIDX"); vargs+=(--key-index "$KEYIDX"); fi
say "build: version ${VERSION:-$((PREV + 1))}, min_package $MINPKG, encrypted -> $LIVE"
python3 -I "$TOOL" "${args[@]}" || die "make_update_manifest.py build failed; nothing new was published"
python3 -I "$TOOL" "${vargs[@]}" || die "verify failed: check $LIVE/manifest.json before players fetch it"
NEWV=$(python3 -I -c 'import json,sys; print(json.loads(json.load(open(sys.argv[1]))["payload"])["version"])' "$LIVE/manifest.json")

chk="skipped"
if [ "$CHECK" = 1 ]; then
  if web_check "${CHECK_URL:-$PKG_URL}"; then chk=ok; else chk="WARN (see above)"; fi
fi

say ""
say "published: version $NEWV (was $PREV), min_package $MINPKG, from ${TAG:-$SRC}"
say "  folder: $LIVE"
say "  public key: $PUBLIC"
say "  clients of package $MINPKG or newer with this key apply it at their next start; older packages with the"
say "  updater are told to download the new client (the game server refuses them when clientGuardManifest names it)"
say "  web server check: $chk"
