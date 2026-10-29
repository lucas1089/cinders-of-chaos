#!/usr/bin/env bash
# Pack the files the engine reads from the APK: data.zip with init.lua, data/, modules/, mods/, layouts/ of an assembled
# client folder (client/tools/assemble_client.sh). The sprite pair (data/things/), the encrypted pack and the build
# folders stay out: the pair is downloaded on first start (docs/ANDROID_CLIENT.md, "Assets on a phone").
# Usage: client/android/tools/make_assets.sh <assembled-client-dir> <out-dir>   -> <out-dir>/data.zip
set -euo pipefail
SRC=${1:?assembled client dir}; OUT=${2:?output dir}
[ -f "$SRC/init.lua" ] && [ -d "$SRC/modules" ] || { echo "not an assembled client tree: $SRC"; exit 1; }
mkdir -p "$OUT"; rm -f "$OUT/data.zip"
(cd "$SRC" && zip -q -r -9 "$(cd "$OUT" && pwd)/data.zip" init.lua data modules mods layouts \
  -x 'data/things/*' -x '*.bak' -x '*.orig' -x '*.rej' -x '*.log')
echo "data.zip: $(du -h "$OUT/data.zip" | cut -f1)"
