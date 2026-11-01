#!/usr/bin/env bash
# Emulator play test (android-client.yml smoke_play, O313), after smoke_download.sh left the game data on the phone:
# drop the marker phonetest_run (account and password of the test server's account) into the app's write folders
# (run-as: debug APKs only), restart the app, take a screenshot at every "phonetest: shot <name>" line of
# client_chaos_phonetest, keep the logcat. Fails when the test did not finish or a step failed.
# Usage: smoke_play.sh <out-dir> <account> <password>
set -uo pipefail
OUT=${1:?out dir}; ACC=${2:?account}; PASS=${3:?password}; PKG=com.cindersofchaos.client
mkdir -p "$OUT"
printf 'account=%s\npassword=%s\n' "$ACC" "$PASS" > "$OUT/marker.txt"
adb push "$OUT/marker.txt" /data/local/tmp/phonetest_run >/dev/null && adb shell chmod 644 /data/local/tmp/phonetest_run
for d in $(adb shell run-as $PKG find . -maxdepth 3 -type d | tr -d '\r'); do
  adb shell run-as $PKG cp /data/local/tmp/phonetest_run "$d/phonetest_run"
done
adb logcat -c
adb shell am force-stop $PKG; sleep 3
adb shell am start -W -n $PKG/.ChaosActivity
# screenshots on request, until "phonetest: done" or 30 minutes
deadline=$((SECONDS + 1800)); seen=" "
while [ $SECONDS -lt $deadline ]; do
  log=$(adb logcat -d -s CindersOfChaos:I 2>/dev/null | grep -o 'phonetest: .*' | tr -d '\r')
  for name in $(printf '%s\n' "$log" | sed -n 's/^phonetest: shot \([A-Za-z0-9_]*\).*/\1/p'); do
    case "$seen" in *" $name "*) continue ;; esac
    seen="$seen$name "
    adb exec-out screencap -p > "$OUT/$name.png"
  done
  printf '%s\n' "$log" | grep -q '^phonetest: done' && break
  adb shell pidof $PKG >/dev/null || { echo "the game stopped"; break; }
  sleep 1
done
adb shell dumpsys meminfo $PKG | head -n 40 || true
adb logcat -d -v threadtime > "$OUT/logcat.txt"
grep -o 'phonetest: .*' "$OUT/logcat.txt" | tee "$OUT/phonetest.txt"
ls "$OUT"
grep -q '^phonetest: done' "$OUT/phonetest.txt" || { echo "PLAY TEST: did not finish"; exit 1; }
if grep -E '^phonetest: [a-z]+ fail' "$OUT/phonetest.txt"; then echo "PLAY TEST: a step failed"; exit 1; fi
echo "PLAY TEST: ok"
