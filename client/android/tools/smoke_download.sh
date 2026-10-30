#!/usr/bin/env bash
# Emulator test of the whole first start (android-client.yml smoke_download): install, wait for the first-start screen,
# drop the autostart marker into the app's write folder (run-as: debug APKs only), restart the app so the screen presses
# Download, wait for the download, the unpack and the restart, then keep the logcat and screenshots of the game after it.
# Usage: smoke_download.sh <apk> <out-dir>
set -uo pipefail
APK=${1:?apk}; OUT=${2:?out dir}; PKG=com.cindersofchaos.client
mkdir -p "$OUT"
wait_for() {  # pattern, tries of 5 s
  for _ in $(seq "$2"); do adb logcat -d | grep -q "$1" && return 0; sleep 5; done; return 1
}
adb logcat -c
adb install -r "$APK" || exit 1
adb shell am start -W -n $PKG/.ChaosActivity
wait_for "firststart: screen shown" 96 || { echo "FIRST START SCREEN: not shown"; adb logcat -d -v threadtime > "$OUT/logcat.txt"; exit 1; }
sleep 10
echo "write folders:"; adb shell run-as $PKG find . -maxdepth 3 -type d | head -40
for d in $(adb shell run-as $PKG find . -maxdepth 3 -type d | tr -d '\r'); do
  adb shell run-as $PKG touch "$d/firststart_autostart"
done
adb shell am force-stop $PKG; sleep 3
adb shell am start -W -n $PKG/.ChaosActivity
wait_for "firststart: autostart marker found" 96 || echo "AUTOSTART: marker not seen"
if wait_for "firststart: restarting the client" 360; then echo "RESTART: seen"; else echo "RESTART: not seen in 30 min"; fi
sleep 30; adb exec-out screencap -p > "$OUT/after-restart-30s.png"
sleep 150; adb exec-out screencap -p > "$OUT/after-restart-180s.png"
adb shell pidof $PKG && echo STILL RUNNING || echo NOT RUNNING
adb logcat -d -v threadtime > "$OUT/logcat.txt"
adb shell run-as $PKG find . -maxdepth 2 > "$OUT/write-folder.txt" 2>&1
adb shell run-as $PKG cat chaos_update/android_state.txt > "$OUT/state.txt" 2>&1
for f in $(adb shell run-as $PKG find . -maxdepth 3 -name '*.log' | tr -d '\r'); do
  adb shell run-as $PKG cat "$f" > "$OUT/$(basename "$f")" 2>&1
done
grep -E "CindersOfChaos|AndroidRuntime|DEBUG|libc|F/" "$OUT/logcat.txt" | grep -v "Loaded module" | tail -n 250
exit 0
