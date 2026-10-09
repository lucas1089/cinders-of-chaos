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
export CHAOS_DB_HOST="${CHAOS_DB_HOST:-127.0.0.1}"
export CHAOS_DB_PASSWORD="${CHAOS_DB_PASSWORD:-${CHAOS_DB_PASS:-}}"   # CHAOS_DB_PASS: the name in /etc/chaos/chaos.env
export CHAOS_SERVER_DATA="${CHAOS_SERVER_DATA:-$REPO/server/data}"
SITE="$(realpath -m "$SITE")"
case "$SITE/" in
  "$REPO/"*) echo "CHAOS_SITE_DIR must be outside the repository ($REPO)." >&2; exit 1 ;;
esac
mkdir -p "$SITE"

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
if [ -d "$SITE/.git" ]; then
  if [ "$(git -C "$SITE" rev-parse HEAD 2>/dev/null)" != "$ZNOTEX_COMMIT" ]; then
    echo "Updating ZnoteX to $ZNOTEX_COMMIT ..."
    git -C "$SITE" fetch -q --depth 1 origin "$ZNOTEX_COMMIT"
    git -C "$SITE" checkout -q --force FETCH_HEAD
  else
    echo "ZnoteX already at $ZNOTEX_COMMIT"
  fi
else
  if [ -n "$(ls -A "$SITE" 2>/dev/null)" ]; then
    echo "$SITE is not empty and is not a ZnoteX checkout; refusing to install over it." >&2; exit 1
  fi
  echo "Cloning ZnoteX $ZNOTEX_COMMIT into $SITE ..."
  git -C "$SITE" init -q
  git -C "$SITE" remote add origin "$ZNOTEX_REPO"
  git -C "$SITE" fetch -q --depth 1 origin "$ZNOTEX_COMMIT"
  git -C "$SITE" checkout -q FETCH_HEAD
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

# ---------------------------------------------------------------- 3b. salted passwords (patches/, README "Passwords")
# ZnoteX files changed in place by patches/*.patch (the pinned checkout, so they always apply); a patch that is
# already in is skipped, a file changed by hand stops the install.
for p in "$HERE"/patches/*.patch; do
  if git -C "$SITE" apply --check "$p" 2>/dev/null; then
    git -C "$SITE" apply "$p"
    echo "Applied $(basename "$p")"
  elif git -C "$SITE" apply --reverse --check "$p" 2>/dev/null; then
    echo "$(basename "$p") already applied"
  else
    echo "$(basename "$p") does not apply to $SITE (a ZnoteX file was changed by hand?)" >&2; exit 1
  fi
done

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

echo "Done. Website: $SITE (layout ${CHAOS_LAYOUT:-chaos})."
echo "Local test: $PHP -S 127.0.0.1:8095 -t \"$SITE\" \"$HERE/setup/router.php\""
