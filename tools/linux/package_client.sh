#!/usr/bin/env bash
# Put the Linux client folder together (CindersOfChaos-Client-Linux.tar.gz of .github/workflows/windows-package.yml).
#
# usage: tools/linux/package_client.sh GAME_DIR BUILD_DIR OUT
#
#   GAME_DIR   the assembled client (client/tools/assemble_client.sh: base + client/base-patches + client/overlay)
#   BUILD_DIR  its CMake build folder (client/LINUX.md "Build"); it must hold exactly one ELF executable
#   OUT        the client folder to create
#
# OUT gets: chaos-client (the executable, RUNPATH $ORIGIN/lib), lib/ (its non-system libraries,
# tools/linux/bundle_libs.sh), init.lua, data/, modules/, mods/, layouts/, run-client.sh and README.txt. The
# Tibia.dat / Tibia.spr pair goes into OUT/data/things/1098/ afterwards (the workflow has it from the assets branch).
set -euo pipefail

[ $# -eq 3 ] || { echo "usage: $0 GAME_DIR BUILD_DIR OUT" >&2; exit 2; }
GAME=$(readlink -f "$1")
BUILD=$(readlink -f "$2")
OUT=$3
REPO=$(cd "$(dirname "$0")/../.." && pwd)
[ -f "$GAME/init.lua" ] || { echo "not an assembled client folder: $GAME" >&2; exit 1; }
[ ! -e "$OUT" ] || { echo "$OUT exists" >&2; exit 1; }

exes=()
while IFS= read -r -d '' f; do
  file -b "$f" | grep -q '^ELF 64-bit.*executable' && exes+=("$f")
done < <(find "$BUILD" -maxdepth 1 -type f -perm -u+x -print0)
if [ ${#exes[@]} -ne 1 ]; then
  echo "::error::expected one executable in $BUILD, found: ${exes[*]:-none}" >&2
  exit 1
fi

mkdir -p "$OUT"
cp "${exes[0]}" "$OUT/chaos-client"
chmod 0755 "$OUT/chaos-client"
for p in init.lua data modules mods layouts; do
  if [ -e "$GAME/$p" ]; then cp -r "$GAME/$p" "$OUT/"; fi
done
if [ -d "$BUILD/data" ]; then cp -r "$BUILD/data/." "$OUT/data/"; fi
bash "$REPO/tools/linux/bundle_libs.sh" "$OUT/chaos-client" "$OUT/lib"
install -m 0755 "$REPO/tools/linux/client/run-client.sh" "$OUT/run-client.sh"
install -m 0644 "$REPO/tools/linux/client/README.txt" "$OUT/README.txt"
du -sh "$OUT"
