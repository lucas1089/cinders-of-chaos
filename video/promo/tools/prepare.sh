#!/bin/bash
# prepare.sh: copy repo art and OFL fonts into public/ (git-ignored copies, the repo files stay the source).
set -e
P=$(cd "$(dirname "$0")/.." && pwd); R=$(cd "$P/../.." && pwd)
mkdir -p "$P/public/art/dungeons" "$P/public/fonts"
cp "$R/client/overlay/data/images/chaos/logo.png" "$P/public/art/logo.png"
cp "$R/client/overlay/data/images/chaos/login/ember.png" "$P/public/art/ember.png"
for b in Bones MasterElement Forbidden Rootkraken HollowVault MarrowCrypts IronCrucible FallenSanctum PyreThrone; do
  cp "$R/client/overlay/data/images/dungeons/$b.png" "$P/public/art/dungeons/$b.png"
done
cp "$R/client/fonts-src/Cinzel/Cinzel-VariableFont_wght.ttf" "$P/public/fonts/Cinzel.ttf"
cp "$R/client/fonts-src/AlegreyaSans/AlegreyaSans-Medium.ttf" "$P/public/fonts/AlegreyaSans-Medium.ttf"
[ -f "$P/public/footage/login_ptbr.mp4" ] || echo "missing public/footage/login_ptbr.mp4: run tools/capture_login.sh (README)"
[ -f "$P/public/footage/login_en.mp4" ] || echo "missing public/footage/login_en.mp4 (English cut only)"
echo prepared
