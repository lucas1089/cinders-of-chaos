#!/usr/bin/env bash
# Check the build properties of the Linux engine (server/README.md "Build flags and allocator (O201)"): position
# independent executable, full RELRO with immediate binding, stack protector, glibc _FORTIFY_SOURCE checks, a
# non-executable stack, and mimalloc as the first needed library. Prints one line per property; exit 1 when one is
# missing. mimalloc is only required with --require-mimalloc (the build falls back to the system allocator without it).
#
# usage: tools/linux/check_engine_hardening.sh BINARY [--require-mimalloc]
set -euo pipefail

[ $# -ge 1 ] || { echo "usage: $0 BINARY [--require-mimalloc]" >&2; exit 2; }
BIN=$1
NEED_MI=0
[ "${2:-}" = --require-mimalloc ] && NEED_MI=1
command -v readelf >/dev/null || { echo "readelf is needed (binutils)" >&2; exit 1; }

hdr=$(readelf -hW "$BIN")
seg=$(readelf -lW "$BIN")
dyn=$(readelf -dW "$BIN")
sym=$(readelf --dyn-syms -W "$BIN")
bad=0
check() { # name condition-result
  if [ "$2" = 1 ]; then echo "ok       $1"; else echo "MISSING  $1"; bad=1; fi
}
has() { grep -q -- "$2" <<<"$1" && echo 1 || echo 0; }

check "PIE (type DYN)" "$(has "$hdr" 'Type:.*DYN')"
check "RELRO (GNU_RELRO segment)" "$(has "$seg" 'GNU_RELRO')"
check "BIND_NOW (full RELRO)" "$( { grep -qE 'BIND_NOW|FLAGS_1.*NOW' <<<"$dyn" && echo 1; } || echo 0)"
check "stack protector (__stack_chk_fail)" "$(has "$sym" '__stack_chk_fail')"
check "FORTIFY_SOURCE (__*_chk functions)" "$( { grep -qE '__(memcpy|memmove|memset|sprintf|snprintf|vsnprintf|strcpy|read|fdelt)_chk' <<<"$sym" && echo 1; } || echo 0)"
check "non-executable stack" "$( { grep -E 'GNU_STACK' <<<"$seg" | grep -qE 'RW ' && echo 1; } || echo 0)"
if grep -q mimalloc <<<"$(grep NEEDED <<<"$dyn")"; then
  echo "ok       mimalloc needed ($(grep -o 'libmimalloc[^]]*' <<<"$dyn" | head -1))"
elif [ "$NEED_MI" = 1 ]; then
  echo "MISSING  mimalloc (not a needed library)"; bad=1
else
  echo "info     mimalloc not linked (system allocator)"
fi
exit $bad
