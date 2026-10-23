#!/usr/bin/env bash
# Build (and run) the fuzz harnesses of server/tools/fuzz/ (server/README.md "Engine hardening (sanitizers, fuzzing)").
#
# usage: server/tools/fuzz/build_fuzz.sh OUT_DIR [--src ENGINE_DIR] [--libfuzzer] [--run] [--only NAME,...]
#
#   OUT_DIR       where the binaries go (one per harness: OUT_DIR/fuzz_<name>)
#   --src DIR     the patched engine source (build_sanitized.sh's WORK_DIR/src-tree): takes the engine files from
#                 there and also builds fuzz_netmsg (it needs base engine files that are not in git). Without it the
#                 new files of the patches are taken out of server/src-patches/*.patch (as CI does): proxyprotocol
#                 (0025), clientguard (0021), loginlimit (0047)
#   --libfuzzer   clang++ -fsanitize=fuzzer,address,undefined: real fuzzing, e.g.
#                   OUT_DIR/fuzz_proxyprotocol -max_total_time=300 NEW_CORPUS_DIR server/tools/fuzz/corpus/proxyprotocol
#                 Without it: g++ -fsanitize=address,undefined with the regression driver standalone_main.cpp, which
#                 runs each file of the seed corpus once (what CI runs)
#   --run         run each built harness over its seed corpus server/tools/fuzz/corpus/<name>/ (regression mode, or
#                 libFuzzer with -runs=0 on the corpus)
#   --only        a subset of: proxyprotocol, clientguard, loginlimit, netmsg
# Needs: g++ or clang++ with the sanitizer runtimes, Crypto++ and fmt headers and libraries (clientguard).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../.." && pwd)
PATCHES="$REPO/server/src-patches"
[ $# -ge 1 ] || { sed -n '2,20p' "$0" >&2; exit 2; }
OUT=$1
shift
SRC=""
LIBFUZZER=0
RUN=0
ONLY="proxyprotocol,clientguard,loginlimit,netmsg"
while [ $# -gt 0 ]; do
  case $1 in
    --src) SRC=$(cd "$2" && pwd); shift 2 ;;
    --libfuzzer) LIBFUZZER=1; shift ;;
    --run) RUN=1; shift ;;
    --only) ONLY=$2; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
want() { [[ ",$ONLY," == *",$1,"* ]]; }

# the engine files the harnesses need, in OUT/src
ENG="$OUT/src"
rm -rf "$ENG"
mkdir -p "$ENG"
if [ -n "$SRC" ]; then
  [ -f "$SRC/src/networkmessage.h" ] || { echo "not a patched engine source: $SRC (want SRC/src/...)" >&2; exit 1; }
  cp "$SRC"/src/{proxyprotocol.cpp,proxyprotocol.h,clientguard.cpp,clientguard.h,loginlimit.h} "$ENG/"
else
  # the new files of a patch: from their "--- " header to the next file's header, applied with patch(1)
  take() { # PATCH FILE
    awk -v f="$2" '
      /^--- / { p = 0; hdr = $0; next }
      /^\+\+\+ b\// { if ($2 == "b/src/" f) { p = 1; print "--- a/src/" f; print $0 }; next }
      p { print }' "$PATCHES/$1" > "$OUT/take.patch"
    [ -s "$OUT/take.patch" ] || { echo "$2 not found in $1" >&2; exit 1; }
    patch -s -p1 -d "$OUT" < "$OUT/take.patch"
    rm -f "$OUT/take.patch"
  }
  take 0025-proxy-protocol.patch proxyprotocol.cpp
  take 0025-proxy-protocol.patch proxyprotocol.h
  take 0021-client-guard.patch clientguard.cpp
  take 0021-client-guard.patch clientguard.h
  take 0047-login-failure-limit.patch loginlimit.h
fi

if [ $LIBFUZZER = 1 ]; then
  CXX_BIN=${CXX:-clang++}
  FLAGS=(-std=c++17 -O1 -g -fno-omit-frame-pointer -fsanitize=fuzzer,address,undefined -fno-sanitize-recover=undefined)
  MAIN=()
else
  CXX_BIN=${CXX:-g++}
  FLAGS=(-std=c++17 -O1 -g -fno-omit-frame-pointer -fsanitize=address,undefined -fno-sanitize-recover=undefined)
  MAIN=("$HERE/standalone_main.cpp")
fi
STUBS=(-I "$HERE/stubs" -I "$ENG")

built=()
if want proxyprotocol; then
  "$CXX_BIN" "${FLAGS[@]}" "${STUBS[@]}" "$ENG/proxyprotocol.cpp" "$HERE/fuzz_proxyprotocol.cpp" "${MAIN[@]}" \
    -o "$OUT/fuzz_proxyprotocol"
  built+=(proxyprotocol)
fi
if want clientguard; then
  "$CXX_BIN" "${FLAGS[@]}" "${STUBS[@]}" "$ENG/clientguard.cpp" "$HERE/fuzz_clientguard.cpp" "${MAIN[@]}" \
    -lcryptopp -lfmt -o "$OUT/fuzz_clientguard"
  built+=(clientguard)
fi
if want loginlimit; then
  "$CXX_BIN" "${FLAGS[@]}" -I "$ENG" "$HERE/fuzz_loginlimit.cpp" "${MAIN[@]}" -o "$OUT/fuzz_loginlimit"
  built+=(loginlimit)
fi
if want netmsg && [ -n "$SRC" ]; then
  # the four engine functions the harness needs, word for word, out of the engine source
  inc="$OUT/netmsg_inc"
  mkdir -p "$inc"
  {
    echo "// taken out of $SRC/src by build_fuzz.sh"
    awk '/^std::string NetworkMessage::getString\(/,/^}/' "$SRC/src/networkmessage.cpp"
    awk '/^Position NetworkMessage::getPosition\(/,/^}/' "$SRC/src/networkmessage.cpp"
    awk '/^uint32_t adlerChecksum\(/,/^}/' "$SRC/src/tools.cpp"
    echo "namespace {"
    awk '/^bool XTEA_decrypt\(/,/^}/' "$SRC/src/protocol.cpp"
    echo "}"
  } > "$inc/netmsg_engine.inc"
  for fn in 'NetworkMessage::getString' 'NetworkMessage::getPosition' 'adlerChecksum' 'XTEA_decrypt'; do
    grep -q "$fn(" "$inc/netmsg_engine.inc" || { echo "netmsg: $fn not found in the engine source" >&2; exit 1; }
  done
  # the read sequences the harness copies: stop when the engine changed them (then update fuzz_netmsg.cpp)
  for line in 'msg.skipBytes((msg.getLength() - 128) - msg.getBufferPosition());' \
              'if (size == 0 || size >= NETWORKMESSAGE_MAXSIZE - 16) {' \
              'msg.setLength(size + NetworkMessage::HEADER_LENGTH);' \
              'std::memset(msg.getBuffer() + NetworkMessage::HEADER_LENGTH + size, 0, NetworkMessage::INITIAL_BUFFER_POSITION);' \
              'if(otcV8StringLength == 5 && msg.getString(5) == "OTCv8") {'; do
    grep -qF "$line" "$SRC"/src/{connection.cpp,protocollogin.cpp,protocolgame.cpp} ||
      { echo "netmsg: the engine no longer has: $line (update fuzz_netmsg.cpp)" >&2; exit 1; }
  done
  "$CXX_BIN" "${FLAGS[@]}" -I "$inc" -I "$SRC/src" "$HERE/fuzz_netmsg.cpp" "$SRC/src/xtea.cpp" "${MAIN[@]}" \
    -o "$OUT/fuzz_netmsg"
  built+=(netmsg)
fi
echo "built: ${built[*]} ($CXX_BIN, $([ $LIBFUZZER = 1 ] && echo libFuzzer || echo regression driver)) in $OUT"

if [ $RUN = 1 ]; then
  for name in "${built[@]}"; do
    corpus="$HERE/corpus/$name"
    [ -d "$corpus" ] || { echo "no seed corpus: $corpus" >&2; exit 1; }
    if [ $LIBFUZZER = 1 ]; then
      "$OUT/fuzz_$name" -runs=0 "$corpus"
    else
      "$OUT/fuzz_$name" "$corpus"
    fi
  done
fi
