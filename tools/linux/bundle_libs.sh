#!/usr/bin/env bash
# Copy the non-system shared libraries of a Linux binary next to it and make it find them there (rpath $ORIGIN/...).
# Used by tools/linux/package_server.sh and tools/linux/package_client.sh (.github/workflows/windows-package.yml).
#
# usage: tools/linux/bundle_libs.sh BINARY LIBDIR
#
# Every library `ldd BINARY` resolves (and, again, every library of a bundled one) is copied into LIBDIR unless its
# name is in SYSTEM below: glibc, the C++ runtime, compression, OpenSSL 3 and the desktop stack (OpenGL, X11, ALSA,
# PulseAudio) that every Ubuntu 22.04+ / Debian 12 machine has and that must come from the machine itself. The binary
# gets RUNPATH $ORIGIN/<LIBDIR relative to it>, each bundled library RUNPATH $ORIGIN. Then the check: ldd again, with
# no LD_LIBRARY_PATH; it fails on a library that is not found or that is not a SYSTEM one and still comes from
# outside LIBDIR. Needs patchelf.
set -euo pipefail

[ $# -eq 2 ] || { echo "usage: $0 BINARY LIBDIR" >&2; exit 2; }
BIN=$(readlink -f "$1")
mkdir -p "$2"
LIBDIR=$(readlink -f "$2")
command -v patchelf >/dev/null || { echo "patchelf is needed (apt install patchelf)" >&2; exit 1; }

SYSTEM='^(linux-vdso|ld-linux-x86-64|libc|libm|libdl|libpthread|librt|libresolv|libutil|libanl|libcrypt|libstdc\+\+|libgcc_s'
SYSTEM+='|libz|libbz2|liblzma|libzstd|liblz4|libssl|libcrypto|libsystemd|libcap|libgcrypt|libgpg-error'
SYSTEM+='|libGL|libGLX|libGLdispatch|libOpenGL|libEGL|libGLU|libgbm|libdrm|libwayland-[a-z]+'
SYSTEM+='|libX11|libX11-xcb|libxcb|libxcb-[a-z0-9-]+|libXau|libXdmcp|libXext|libXrandr|libXrender|libXi|libXcursor'
SYSTEM+='|libXfixes|libXinerama|libXxf86vm|libxkbcommon|libasound|libpulse|libpulse-simple|libbsd|libmd'
SYSTEM+='|libgnutls|libnettle|libhogweed|libgmp|libp11-kit|libtasn1|libunistring|libidn2|libffi)\.so'

deps() {  # "name path" for every library ldd resolves; "name not-found" for a missing one
  env -u LD_LIBRARY_PATH ldd "$1" | awk '$2 == "=>" { print $1, ($3 == "not" ? "not-found" : $3) }'
}

queue=("$BIN")
i=0
while [ $i -lt ${#queue[@]} ]; do
  f=${queue[$i]}
  i=$((i + 1))
  while read -r name path; do
    [[ $name =~ $SYSTEM ]] && continue
    [ -e "$LIBDIR/$name" ] && continue
    if [ "$path" = not-found ]; then
      echo "::error::$name (needed by $(basename "$f")) is not installed on this machine" >&2
      exit 1
    fi
    cp -L "$path" "$LIBDIR/$name"
    chmod 0755 "$LIBDIR/$name"
    queue+=("$LIBDIR/$name")
  done < <(deps "$f")
done

rel=$(realpath --relative-to="$(dirname "$BIN")" "$LIBDIR")
patchelf --set-rpath "\$ORIGIN/$rel" "$BIN"
shopt -s nullglob
for lib in "$LIBDIR"/*.so*; do
  patchelf --set-rpath "\$ORIGIN" "$lib"
done

bad=0
for f in "$BIN" "$LIBDIR"/*.so*; do
  while read -r name path; do
    if [ "$path" = not-found ]; then
      echo "::error::$(basename "$f"): $name not found" >&2
      bad=1
    elif [ "$(dirname "$(readlink -f "$path")")" = "$LIBDIR" ] || [ "$(dirname "$path")" = "$LIBDIR" ]; then
      :
    elif ! [[ $name =~ $SYSTEM ]]; then
      echo "::error::$(basename "$f"): $name would come from the system ($path), not from $LIBDIR" >&2
      bad=1
    fi
  done < <(deps "$f")
done
[ $bad -eq 0 ] || exit 1

echo "$(basename "$BIN"): RUNPATH $(patchelf --print-rpath "$BIN")"
echo "  bundled in $rel/:"
for lib in "$LIBDIR"/*.so*; do
  echo "    $(basename "$lib") ($(du -k "$lib" | cut -f1) KB)"
done
echo "  from the system:"
deps "$BIN" | awk '{ print $1 }' | grep -E "$SYSTEM" | sort -u | sed 's/^/    /' || true
