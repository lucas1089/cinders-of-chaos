#!/usr/bin/env bash
# Debug build of the server engine with AddressSanitizer and UndefinedBehaviorSanitizer
# (server/README.md "Engine hardening (sanitizers, fuzzing)").
#
# usage: server/tools/build_sanitized.sh BASE_TAR_OR_DIR WORK_DIR [--jobs N] [--cxx g++|clang++] [--clean-objects]
#
#   BASE_TAR_OR_DIR  the base server download (.tar.xz with one top folder) or an already extracted folder with
#                    CMakeLists.txt and src/
#   WORK_DIR         scratch folder; it gets WORK_DIR/src-tree (a fresh copy of the engine source with every
#                    server/src-patches/*.patch applied) and WORK_DIR/build (the build; the binary is
#                    WORK_DIR/build/tfs)
#
# Idempotent: a second run keeps the patched tree when the patch list and the base are the same (a stamp file holds
# their sha256), and ninja rebuilds only what changed. A changed patch set or base starts the tree again.
# Flags: -O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer -fno-sanitize-recover=undefined is NOT set: the
# engine keeps running after a UBSan report so one run collects all of them (set UBSAN_OPTIONS=halt_on_error=1 to
# stop at the first). The copy of CMakeLists.txt in WORK_DIR drops -Werror (the sanitizers add warnings at -O1) and
# the link-time optimisation (slow with the sanitizers, and it hides frames). The base download is not changed.
#
# Run the binary from a server folder (config.lua, data/), with for example
#   ASAN_OPTIONS=detect_leaks=0:quarantine_size_mb=64:malloc_context_size=20:log_path=asan
#   UBSAN_OPTIONS=print_stacktrace=1:log_path=ubsan
# (leak checking at exit is off: the engine does not free its world at shutdown, every global would be a report).
set -euo pipefail

usage() { sed -n '2,12p' "$0" >&2; exit 2; }
[ $# -ge 2 ] || usage
BASE=$1
WORK=$2
shift 2
JOBS=$(nproc)
CXX_BIN=${CXX:-g++}
CLEAN=0
while [ $# -gt 0 ]; do
  case $1 in
    --jobs) JOBS=$2; shift 2 ;;
    --cxx) CXX_BIN=$2; shift 2 ;;
    --clean-objects) CLEAN=1; shift ;;
    *) usage ;;
  esac
done

REPO=$(cd "$(dirname "$0")/../.." && pwd)
PATCHES="$REPO/server/src-patches"
mkdir -p "$WORK"
WORK=$(cd "$WORK" && pwd)
TREE="$WORK/src-tree"
BUILD="$WORK/build"

stamp=$( { sha256sum "$PATCHES"/*.patch; if [ -f "$BASE" ]; then sha256sum "$BASE"; else echo "dir $(cd "$BASE" && pwd)"; fi; } \
  | sha256sum | cut -d' ' -f1)

if [ -f "$TREE/.chaos-stamp" ] && [ "$(cat "$TREE/.chaos-stamp")" = "$stamp" ]; then
  echo "== engine source: up to date ($TREE)"
else
  echo "== engine source: fresh copy with every patch"
  rm -rf "$TREE" "$TREE.new"
  mkdir -p "$TREE.new"
  if [ -f "$BASE" ]; then
    tmp=$(mktemp -d "$WORK/extract.XXXXXX")
    # only the engine source, not the data folder
    tar -xJf "$BASE" -C "$tmp" --wildcards '*/CMakeLists.txt' '*/cmake/*' '*/src/*'
    top=$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -1)
    cp -a "$top/CMakeLists.txt" "$top/cmake" "$top/src" "$TREE.new/"
    rm -rf "$tmp"
  else
    [ -f "$BASE/CMakeLists.txt" ] && [ -d "$BASE/src" ] || { echo "not an engine source folder: $BASE" >&2; exit 1; }
    cp -a "$BASE/CMakeLists.txt" "$BASE/cmake" "$BASE/src" "$TREE.new/"
  fi
  for p in "$PATCHES"/*.patch; do
    patch -d "$TREE.new" -p1 -s -f --no-backup-if-mismatch < "$p" > "$WORK/patch.log" 2>&1 || {
      echo "patch failed: $(basename "$p")" >&2; cat "$WORK/patch.log" >&2; exit 1; }
  done
  echo "  $(ls "$PATCHES"/*.patch | wc -l) patches applied"
  # the sanitizer build's own CMakeLists.txt copy: no -Werror, no link-time optimisation
  sed -i -e 's/ -Werror / /' \
    -e 's/set_target_properties(tfs PROPERTIES INTERPROCEDURAL_OPTIMIZATION True)/message(STATUS "IPO off (sanitizer build)")/' \
    "$TREE.new/CMakeLists.txt"
  grep -q -- '-Werror' "$TREE.new/CMakeLists.txt" && { echo "CMakeLists.txt: -Werror still set" >&2; exit 1; }
  echo "$stamp" > "$TREE.new/.chaos-stamp"
  mv "$TREE.new" "$TREE"
  rm -rf "$BUILD"  # new sources: a clean build
fi

SAN="-O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer -fno-optimize-sibling-calls"
echo "== configure ($CXX_BIN: $SAN)"
cmake -S "$TREE" -B "$BUILD" -G Ninja -DCMAKE_BUILD_TYPE=None -DSKIP_GIT=ON \
  -DCMAKE_CXX_COMPILER="$CXX_BIN" \
  -DCMAKE_CXX_FLAGS="$SAN" \
  -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=address,undefined" > "$WORK/configure.log" 2>&1 || {
    tail -30 "$WORK/configure.log" >&2; exit 1; }
echo "== build ($JOBS jobs)"
cmake --build "$BUILD" --parallel "$JOBS" > "$WORK/build.log" 2>&1 || { grep -m20 -B2 -A8 'error' "$WORK/build.log" >&2 || tail -40 "$WORK/build.log" >&2; exit 1; }
[ -x "$BUILD/tfs" ] || { echo "no binary" >&2; exit 1; }
if [ "$CLEAN" = 1 ]; then
  # disk: keep the binary, drop the objects (the next run rebuilds everything)
  find "$BUILD" -name '*.o' -delete
  find "$BUILD" -name '*.gch' -delete
fi
echo "== done: $BUILD/tfs"
