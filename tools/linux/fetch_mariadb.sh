#!/usr/bin/env bash
# Portable MariaDB for the Linux server package: the official glibc binary tarball from archive.mariadb.org, checked
# against its sha256sums.txt, cut down to what the package runs (mariadbd, the mariadb / mariadb-admin / mariadb-dump
# clients, mariadb-install-db and the plugins without extra system libraries), debug symbols stripped.
# Used by .github/workflows/windows-package.yml (job engine-linux).
#
# usage: tools/linux/fetch_mariadb.sh VERSION DEST      (DEST must not exist; about 130 MB afterwards)
set -euo pipefail

[ $# -eq 2 ] || { echo "usage: $0 VERSION DEST" >&2; exit 2; }
VERSION=$1
DEST=$2
[ ! -e "$DEST" ] || { echo "$DEST exists" >&2; exit 1; }
NAME="mariadb-$VERSION-linux-systemd-x86_64"
URL="https://archive.mariadb.org/mariadb-$VERSION/bintar-linux-systemd-x86_64"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

curl -fsSL --retry 3 -o "$TMP/$NAME.tar.gz" "$URL/$NAME.tar.gz"
curl -fsSL --retry 3 -o "$TMP/sha256sums.txt" "$URL/sha256sums.txt"
(cd "$TMP" && grep " $NAME.tar.gz\$" sha256sums.txt | sha256sum -c -)

KEEP_BIN="mariadbd mariadb mariadb-admin mariadb-dump mariadb-check mariadb-upgrade my_print_defaults resolveip"
members=()
for b in $KEEP_BIN; do members+=("$NAME/bin/$b"); done
members+=("$NAME/scripts" "$NAME/share" "$NAME/lib" "$NAME/COPYING" "$NAME/README.md" "$NAME/THIRDPARTY")
tar -xzf "$TMP/$NAME.tar.gz" -C "$TMP" --exclude='*.a' --exclude="$NAME/lib/pkgconfig" "${members[@]}"
rm "$TMP/$NAME.tar.gz"
M="$TMP/$NAME"

# storage engines and plugins the game never uses; some need libraries a stock system lacks (Judy, cracklib)
rm -f "$M"/lib/plugin/ha_rocksdb.so "$M"/lib/plugin/ha_mroonga.so "$M"/lib/plugin/ha_spider.so \
  "$M"/lib/plugin/ha_connect.so "$M"/lib/plugin/ha_oqgraph.so "$M"/lib/plugin/cracklib_password_check.so \
  "$M"/lib/libgalera_smm.so
rm -rf "$M"/share/mroonga "$M"/share/groonga "$M"/share/groonga-normalizer-mysql "$M"/share/*.jar
strip --strip-debug "$M"/bin/* "$M"/lib/*.so* "$M"/lib/plugin/*.so 2>/dev/null || true

# every kept binary and plugin must load on this machine with the system's libraries only
bad=0
for f in "$M"/bin/* "$M"/lib/plugin/*.so; do
  [ -f "$f" ] && file -b "$f" | grep -q ELF || continue
  if ldd "$f" 2>/dev/null | grep -q "not found"; then
    echo "::error::$(basename "$f"): $(ldd "$f" | grep "not found" | tr -s ' \t' ' ')" >&2
    bad=1
  fi
done
[ $bad -eq 0 ] || exit 1
for f in mariadbd mariadb mariadb-admin mariadb-dump my_print_defaults resolveip; do
  test -x "$M/bin/$f" || { echo "::error::MariaDB tarball has no bin/$f" >&2; exit 1; }
done
test -x "$M/scripts/mariadb-install-db" || { echo "::error::MariaDB tarball has no scripts/mariadb-install-db" >&2; exit 1; }

mv "$M" "$DEST"
du -sh "$DEST"
