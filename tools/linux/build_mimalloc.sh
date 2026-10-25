#!/usr/bin/env bash
# Build the secure mimalloc (MI_SECURE=ON: guard pages, randomised allocation, encoded free lists, double-free
# detection) from the pinned upstream release and install it into PREFIX (PREFIX/lib/libmimalloc-secure.so*; the secure build names itself so). The engine's
# CMake finds it with -DCHAOS_MIMALLOC_DIR=PREFIX (src/chaos_build.cmake, server/README.md "Build flags and allocator
# (O201)"). Used by the engine-linux job of .github/workflows/windows-package.yml. The distro package is not used: it is
# the default (not secure) build.
#
# The source is the git tag below, checked twice before anything is built: the commit it resolves to and the sha256 of
# `git archive --format=tar` of that commit (the tar is deterministic for a commit; a GitHub tar.gz is not pinned that
# way). Change the three values together when the version is bumped (docs/CREDITS.md names the version).
#
# usage: tools/linux/build_mimalloc.sh PREFIX [WORK_DIR]
set -euo pipefail

VERSION=2.1.7
COMMIT=8c532c32c3c96e5ba1f2283e032f69ead8add00f
TAR_SHA256=cac1d8d67cc5043fc13073f82a458f15d6cf2978619b9f8df84c73577f202325

[ $# -ge 1 ] || { echo "usage: $0 PREFIX [WORK_DIR]" >&2; exit 2; }
mkdir -p "$1"
PREFIX=$(cd "$1" && pwd)
WORK=${2:-$(mktemp -d)}
mkdir -p "$WORK"
SRC="$WORK/mimalloc"
rm -rf "$SRC"

GIT_LFS_SKIP_SMUDGE=1 git clone -q --depth 1 --branch "v$VERSION" https://github.com/microsoft/mimalloc "$SRC" 2>/dev/null
got=$(git -C "$SRC" rev-parse HEAD)
[ "$got" = "$COMMIT" ] || { echo "::error::mimalloc v$VERSION is commit $got, expected $COMMIT" >&2; exit 1; }
sum=$(git -C "$SRC" archive --format=tar --prefix="mimalloc-$VERSION/" HEAD | sha256sum | cut -d' ' -f1)
[ "$sum" = "$TAR_SHA256" ] || { echo "::error::mimalloc source sha256 $sum, expected $TAR_SHA256" >&2; exit 1; }
echo "mimalloc v$VERSION: commit and source sha256 match"

cmake -S "$SRC" -B "$WORK/build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DMI_SECURE=ON -DMI_BUILD_TESTS=OFF -DMI_BUILD_OBJECT=OFF -DMI_BUILD_STATIC=OFF -DMI_BUILD_SHARED=ON \
  -DMI_OVERRIDE=ON -DMI_INSTALL_TOPLEVEL=ON > "$WORK/configure.log" 2>&1 || { tail -30 "$WORK/configure.log" >&2; exit 1; }
grep -q 'MI_SECURE=ON' "$WORK/configure.log" || { echo "::error::mimalloc configured without MI_SECURE" >&2; exit 1; }
cmake --build "$WORK/build" --parallel "$(nproc)" > "$WORK/build.log" 2>&1 || { tail -30 "$WORK/build.log" >&2; exit 1; }
cmake --install "$WORK/build" > "$WORK/install.log" 2>&1 || { tail -30 "$WORK/install.log" >&2; exit 1; }
ls -l "$PREFIX"/lib/libmimalloc-secure.so*
