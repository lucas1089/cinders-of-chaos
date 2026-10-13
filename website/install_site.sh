#!/usr/bin/env bash
# Installs (or updates) the Cinders of Chaos website: ZnoteX at a pinned commit, the purple "Void" layout it is based
# on, our overlay (layout "chaos", plugin "chaos"), config.local.php from the environment, and ZnoteX's tables and
# migrations in the game database. Idempotent: run it again after changing a setting or pulling the repository.
#
#   CHAOS_SITE_DIR=/var/www/chaos CHAOS_DB_USER=chaos CHAOS_DB_PASSWORD=... CHAOS_DB_NAME=chaos \
#     website/install_site.sh
#
# Or put the variables in files and pass them: website/install_site.sh /etc/chaos/chaos.env /etc/chaos/site.env
# (the game server's env file gives CHAOS_DB_*; website/site.env.example lists the website's own settings).
# Needs: git, php 8.1+ with mysqli, python3, and curl or wget. Full description: website/README.md.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

for envfile in "$@"; do
  [ -f "$envfile" ] || { echo "No such settings file: $envfile" >&2; exit 1; }
  set -a
  # shellcheck disable=SC1090
  . "$envfile"
  set +a
done

# ---------------------------------------------------------------- pins
ZNOTEX_REPO="https://github.com/Open-Games-Community/ZnoteX"
ZNOTEX_COMMIT="07a815e2dda818a042ba894aa205c220a7495fbe"          # main, ZnoteX 2.0.5
# The purple layout "Void" (ZnoteX layout catalogue, branch "layouts"), pinned to a commit and checked by hash.
VOID_URL="https://raw.githubusercontent.com/Open-Games-Community/ZnoteX/296627bbc5094ae79833c0fd556e9c1ad5152ac5/void.zip"
VOID_SHA256="a59fa27e4463e7d8c9ac31cfe3fadcd794301054656485e1af2ddf60c9950017"

# ---------------------------------------------------------------- settings
SITE="${CHAOS_SITE_DIR:-}"
[ -n "$SITE" ] || { echo "Set CHAOS_SITE_DIR to the folder the website is installed in (outside the repository)." >&2; exit 1; }
: "${CHAOS_DB_USER:?Set CHAOS_DB_USER}"
: "${CHAOS_DB_NAME:?Set CHAOS_DB_NAME}"
: "${CHAOS_SITE_URL:?Set CHAOS_SITE_URL to the public address of the site, https://...}"
export CHAOS_DB_HOST="${CHAOS_DB_HOST:-127.0.0.1}"
export CHAOS_DB_PASSWORD="${CHAOS_DB_PASSWORD:-${CHAOS_DB_PASS:-}}"   # CHAOS_DB_PASS: the name in /etc/chaos/chaos.env
export CHAOS_SERVER_DATA="${CHAOS_SERVER_DATA:-$REPO/server/data}"
SITE="$(realpath -m "$SITE")"
case "$SITE/" in
  "$REPO/"*) echo "CHAOS_SITE_DIR must be outside the repository ($REPO)." >&2; exit 1 ;;
esac
mkdir -p "$SITE"
# ZnoteX's git data lives OUTSIDE the web root (README "Web server"): default next to it, /var/www/.chaos.znotex.git for
# /var/www/chaos. An install of an older version of this script had it in $SITE/.git; it is moved on the next run.
ZGIT="${CHAOS_SITE_GIT_DIR:-$(dirname "$SITE")/.$(basename "$SITE").znotex.git}"
ZGIT="$(realpath -m "$ZGIT")"
case "$ZGIT/" in
  "$SITE/"*) echo "CHAOS_SITE_GIT_DIR must be outside CHAOS_SITE_DIR ($SITE)." >&2; exit 1 ;;
esac
if [ -d "$SITE/.git" ] && [ ! -e "$ZGIT" ]; then
  echo "Moving ZnoteX's git data out of the web root to $ZGIT"
  mv "$SITE/.git" "$ZGIT"
  git --git-dir="$ZGIT" config core.worktree "$SITE"
fi
zgit() { git --git-dir="$ZGIT" --work-tree="$SITE" "$@"; }

PHP="${PHP:-php}"
"$PHP" -r 'exit(PHP_VERSION_ID >= 80100 && extension_loaded("mysqli") ? 0 : 1);' 2>/dev/null \
  || { echo "Needs PHP 8.1+ with the mysqli extension ($PHP)." >&2; exit 1; }
command -v git >/dev/null || { echo "Needs git." >&2; exit 1; }
command -v python3 >/dev/null || { echo "Needs python3." >&2; exit 1; }

fetch() { # url file
  if command -v curl >/dev/null; then curl -fsSL -o "$2" "$1"; else wget -q -O "$2" "$1"; fi
}
sha256() {
  if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# ---------------------------------------------------------------- 1. ZnoteX at the pinned commit
if [ -d "$ZGIT" ]; then
  if [ "$(zgit rev-parse HEAD 2>/dev/null)" != "$ZNOTEX_COMMIT" ]; then
    echo "Updating ZnoteX to $ZNOTEX_COMMIT ..."
    zgit fetch -q --depth 1 origin "$ZNOTEX_COMMIT"
    zgit checkout -q --force FETCH_HEAD
  else
    echo "ZnoteX already at $ZNOTEX_COMMIT"
  fi
else
  if [ -n "$(ls -A "$SITE" 2>/dev/null)" ]; then
    echo "$SITE is not empty and is not a ZnoteX checkout; refusing to install over it." >&2; exit 1
  fi
  echo "Cloning ZnoteX $ZNOTEX_COMMIT into $SITE ..."
  git init -q --bare "$ZGIT"
  git --git-dir="$ZGIT" config core.bare false
  git --git-dir="$ZGIT" config core.worktree "$SITE"
  zgit remote add origin "$ZNOTEX_REPO"
  zgit fetch -q --depth 1 origin "$ZNOTEX_COMMIT"
  zgit checkout -q FETCH_HEAD
fi

# ---------------------------------------------------------------- 2. the purple layout (parent of ours)
if [ "$(cat "$SITE/layouts/void/.chaos-pin" 2>/dev/null || true)" != "$VOID_SHA256" ]; then
  echo "Installing the Void layout ..."
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  fetch "$VOID_URL" "$TMP/void.zip"
  got="$(sha256 "$TMP/void.zip")"
  [ "$got" = "$VOID_SHA256" ] || { echo "void.zip checksum mismatch: $got" >&2; exit 1; }
  mkdir -p "$TMP/x"
  python3 -I -m zipfile -e "$TMP/void.zip" "$TMP/x"
  [ -f "$TMP/x/void/theme.json" ] || { echo "void.zip has no void/theme.json" >&2; exit 1; }
  rm -rf "$SITE/layouts/void"
  mv "$TMP/x/void" "$SITE/layouts/void"
  echo "$VOID_SHA256" > "$SITE/layouts/void/.chaos-pin"
else
  echo "Void layout already installed"
fi

# ---------------------------------------------------------------- 3. our overlay
# our own folders are replaced as a whole, so files removed from the repository disappear from the site too
rm -rf "$SITE/layouts/chaos" "$SITE/plugins/chaos"
cp -R "$HERE/overlay/." "$SITE/"
python3 -I "$HERE/tools/recolor_layout.py" "$SITE/layouts/void" "$SITE/layouts/chaos"
# the legal texts (docs/legal/, README "Legal pages"): the plugin's legal page reads them; .md is denied by the web server
mkdir -p "$SITE/plugins/chaos/legal"
for doc in terms privacy donations; do
  for lang in pt-BR en; do
    cp "$REPO/docs/legal/$doc.$lang.md" "$SITE/plugins/chaos/legal/"
  done
done
LEGAL_TODO="$("$PHP" -r 'require $argv[1]; $n = 0; foreach (glob($argv[2] . "/*.md") as $f) { $n += count(chaos_legal_placeholders((string)file_get_contents($f))); } echo $n;' \
  "$SITE/plugins/chaos/legal_lib.php" "$SITE/plugins/chaos/legal")"
[ "$LEGAL_TODO" = "0" ] || echo "WARNING: the legal texts still have $LEGAL_TODO placeholder(s) like [NOME DO RESPONSÁVEL]: fill them in docs/legal/ before launch (docs/legal/README.md)."

# ---------------------------------------------------------------- 3b. salted passwords (patches/, README "Passwords")
# ZnoteX files changed in place by patches/*.patch (the pinned checkout, so they always apply); a patch that is
# already in is skipped, a file changed by hand stops the install.
# The patches are applied to the site folder as a plain folder (git apply outside a repository: the git data is not in
# the web root, and GIT_CEILING_DIRECTORIES stops git from finding a repository above it).
sapply() { (cd "$SITE" && GIT_CEILING_DIRECTORIES="$(dirname "$SITE")" git apply "$@"); }
for p in "$HERE"/patches/*.patch; do
  if sapply --check "$p" 2>/dev/null; then
    sapply "$p"
    echo "Applied $(basename "$p")"
  elif sapply --reverse --check "$p" 2>/dev/null; then
    echo "$(basename "$p") already applied"
  else
    echo "$(basename "$p") does not apply to $SITE (a ZnoteX file was changed by hand?)" >&2; exit 1
  fi
done

# ---------------------------------------------------------------- 3c. PHPMailer (README "Mail")
# ZnoteX sends mail with PHPMailer, a composer package it does not ship. The three source files of the version in
# ZnoteX's composer.lock go to vendor/ (denied by the web server rules), each checked against a SHA-256; the plugin
# loads them (plugins/chaos/mail_lib.php). Installed even with mail off, so turning it on needs only site.env.
PHPMAILER_COMMIT="1bc1716a507a65e039d4ac9d9adebbbd0d346e15"       # PHPMailer v7.1.1 (LGPL 2.1, LICENSE kept next to it)
PHPMAILER_FILES="src/Exception.php:22ab858ae438d98f58f41f38ad2191d1b0d59570aebea0463a7948cfae1021b7
src/PHPMailer.php:45599a196ae7944ee2dcd4f3d3da0ac4243513d346b2d77bbd15dbd0c37f7064
src/SMTP.php:522bcf0d07be7e7e00114711db5c9ce2b4d59ac041c5ec36eaadd979d5fa7046
LICENSE:a1a33180d02960ab1c5de36cf20b1a2f0fe9888d83826ad263da5db52f1b183b"
PM="$SITE/vendor/phpmailer/phpmailer"
if [ "$(cat "$PM/.chaos-pin" 2>/dev/null || true)" != "$PHPMAILER_COMMIT" ]; then
  echo "Installing PHPMailer ..."
  PMTMP="$(mktemp -d)"
  while IFS=: read -r f want; do
    mkdir -p "$PMTMP/$(dirname "$f")"
    fetch "https://raw.githubusercontent.com/PHPMailer/PHPMailer/$PHPMAILER_COMMIT/$f" "$PMTMP/$f"
    got="$(sha256 "$PMTMP/$f")"
    [ "$got" = "$want" ] || { echo "PHPMailer $f checksum mismatch: $got" >&2; rm -rf "$PMTMP"; exit 1; }
  done <<< "$PHPMAILER_FILES"
  mkdir -p "$PM/src"
  cp "$PMTMP"/src/*.php "$PM/src/"
  cp "$PMTMP/LICENSE" "$PM/LICENSE"
  echo "$PHPMAILER_COMMIT" > "$PM/.chaos-pin"
  rm -rf "$PMTMP"
else
  echo "PHPMailer already installed"
fi

# ---------------------------------------------------------------- 3d. sprite images (README "Sprite images")
# Item and outfit images drawn from our client pair by tools/gen_sprite_images.py into chaos-sprites/ (only the tiers
# of CHAOS_SPRITE_PUBLISH; everything else a placeholder). Rebuilt only when the pair, the items.otb, the setting or
# the tool changed; built in a new folder and swapped in, so the site never serves a half-written set. Without
# CHAOS_SPRITE_PAIR an existing set stays and nothing is built (no pair on the site: images off).
SPRITES="$SITE/chaos-sprites"
if [ -n "${CHAOS_SPRITE_PAIR:-}" ]; then
  SP_DAT="$CHAOS_SPRITE_PAIR/Tibia.dat"; SP_SPR="$CHAOS_SPRITE_PAIR/Tibia.spr"
  [ -f "$SP_DAT" ] && [ -f "$SP_SPR" ] || { echo "CHAOS_SPRITE_PAIR: no Tibia.dat / Tibia.spr in $CHAOS_SPRITE_PAIR" >&2; exit 1; }
  SP_OTB="${CHAOS_SPRITE_OTB:-$CHAOS_SERVER_DATA/items/items.otb}"
  SP_OTB_ARG=()
  if [ -f "$SP_OTB" ]; then SP_OTB_ARG=(--otb "$SP_OTB"); else
    echo "note: no items.otb at $SP_OTB: only our own items get images (set CHAOS_SPRITE_OTB)."; SP_OTB=""; fi
  SP_KEY="$( { sha256 "$SP_DAT"; sha256 "$SP_SPR"; [ -z "$SP_OTB" ] || sha256 "$SP_OTB"; echo "${CHAOS_SPRITE_PUBLISH:-own}";
              sha256 "$HERE/tools/gen_sprite_images.py"; sha256 "$HERE/tools/sprite_owners.csv"; } \
            | { if command -v sha256sum >/dev/null; then sha256sum; else shasum -a 256; fi; } | cut -d' ' -f1)"
  if [ "$(cat "$SPRITES/.chaos-key" 2>/dev/null || true)" != "$SP_KEY" ]; then
    echo "Drawing the sprite images (publish ${CHAOS_SPRITE_PUBLISH:-own}) ..."
    rm -rf "$SPRITES.new" "$SPRITES.old"
    python3 -I "$HERE/tools/gen_sprite_images.py" --dat "$SP_DAT" --spr "$SP_SPR" ${SP_OTB_ARG[@]+"${SP_OTB_ARG[@]}"} \
      --publish "${CHAOS_SPRITE_PUBLISH:-own}" --out-dir "$SPRITES.new"
    echo "$SP_KEY" > "$SPRITES.new/.chaos-key"
    [ ! -d "$SPRITES" ] || mv "$SPRITES" "$SPRITES.old"
    mv "$SPRITES.new" "$SPRITES"
    rm -rf "$SPRITES.old" "$SITE/engine/cache/chaos-outfits"
  else
    echo "Sprite images already up to date"
  fi
fi
if [ -f "$SPRITES/index.json" ]; then export CHAOS_SPRITES=1; else export CHAOS_SPRITES=0; fi

# ---------------------------------------------------------------- 4. config.local.php (secrets stay on this machine)
umask 077
"$PHP" "$HERE/setup/write_config.php" > "$SITE/config.local.php.new"
mv "$SITE/config.local.php.new" "$SITE/config.local.php"
chmod 600 "$SITE/config.local.php"
umask 022
mkdir -p "$SITE/engine/cache" "$SITE/engine/img/theme" "$SITE/install"
[ -f "$SITE/install/installed.lock" ] || \
  printf 'Installed by website/install_site.sh on %s\nThe web installer stays locked: the installer script does its work.\n' "$(date '+%F %T')" \
    > "$SITE/install/installed.lock"
rm -f "$SITE"/engine/cache/*.cache "$SITE"/engine/cache/*.cache.php 2>/dev/null || true   # class names, rankings
if [ -n "${CHAOS_WEB_USER:-}" ]; then
  chown -R "$CHAOS_WEB_USER" "$SITE/engine/cache" "$SITE/engine/img/theme" "$SITE/config.local.php"
fi

# ---------------------------------------------------------------- 5. tables, migrations, plugin, layout, menu
(cd "$SITE" && "$PHP" "$HERE/setup/chaos_setup.php")

# ---------------------------------------------------------------- 6. nothing but the site in the web root
# ZnoteX's tests, tools, docker files, composer files and the special/ maintenance scripts are not needed by the site
# and are deleted from it (README "Web server"); the git data is already outside. A ZnoteX update restores them and
# the next run deletes them again. SQL/ (the setup and the admin panel's migrations read it), Lua/ and install/ (the
# installer lock) stay and are denied by .htaccess / the nginx rules.
for f in tests tools docker .github docker-compose.yml Dockerfile .dockerignore .env.example .codefactor.yml \
         .editorconfig .gitattributes .gitignore composer.json composer.lock composer.phar phpunit.xml phpstan.neon; do
  rm -rf "${SITE:?}/$f"
done
find "$SITE/special" -mindepth 1 ! -name .htaccess -exec rm -rf {} + 2>/dev/null || true
[ ! -e "$SITE/.git" ] || { echo "$SITE/.git is still there: move it out of the web root (CHAOS_SITE_GIT_DIR)." >&2; exit 1; }

echo "Done. Website: $SITE (layout ${CHAOS_LAYOUT:-chaos})."
echo "Local test: $PHP -S 127.0.0.1:8095 -t \"$SITE\" \"$HERE/setup/router.php\""
