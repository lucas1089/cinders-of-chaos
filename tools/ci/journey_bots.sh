#!/usr/bin/env bash
# Journey bots on a CI server (O542, unity/README.md "Journey bots (O542)"; .github/workflows/journey-bots.yml, manual).
# Three bots (a Warrior, a Ranger, a Mystic: melee, ranged, caster) play a fresh level 1 character each on the server that
# tools/ci/unity_live_check.sh --serve-only brings up (base server of windows-assets, install_all.py of this commit, private MariaDB,
# the engine of the newest release): no teleport, no staff command, no helper file. Each writes its numbers as JSON; the report
# (server/tools/journey_report.py) compares minutes per level against server/tools/progression_model.lua and lists deaths, stuck
# positions and the coverage table. The run is a report, not a gate: the exit code is 0 unless the server or a bot did not start.
#
# usage: UL_ASSETS=DIR UL_WORK=DIR JB_OUT=DIR tools/ci/journey_bots.sh
#   UL_ASSETS, UL_WORK   as for unity_live_check.sh (UL_WORK: an empty folder)
#   JB_OUT               folder for the bot JSON files, the logs and the report (the artifact of the workflow)
#   JB_MINUTES           wall minutes per bot (default 40); JB_LEVEL: the level a bot stops at (default 25)
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
: "${UL_ASSETS:?UL_ASSETS: checkout of windows-assets}" "${UL_WORK:?UL_WORK: work folder}" "${JB_OUT:?JB_OUT: output folder}"
MINUTES=${JB_MINUTES:-40}
LEVEL=${JB_LEVEL:-25}
mkdir -p "$UL_WORK" "$JB_OUT"
WORK=$(cd "$UL_WORK" && pwd)
OUT=$(cd "$JB_OUT" && pwd)
export UL_IDENTITIES=chaos

log() { printf '== %s\n' "$*"; }
die() { printf '::error::%s\n' "$*" >&2; exit 1; }

# shellcheck disable=SC2317 # run by the trap
stop_server() { UL_WORK="$WORK" bash "$REPO/tools/ci/unity_live_check.sh" --stop > /dev/null 2>&1 || true; }
trap stop_server EXIT

log "server (unity_live_check.sh --serve-only)"
UL_ASSETS="$UL_ASSETS" UL_WORK="$WORK" bash "$REPO/tools/ci/unity_live_check.sh" --serve-only
ENVF="$WORK/client-chaos.env"
[ -f "$ENVF" ] || die "no $ENVF"
# the guard key, the RSA modulus and the login port reach the bots by the environment; nothing secret is printed
set -a
# shellcheck disable=SC1090
. "$ENVF"
set +a
SOCK=$(cat "$WORK/run/mariadb.sockpath" 2>/dev/null || echo "$WORK/run/mariadb.sock")
SERVER="$WORK/server"
[ -r "$SERVER/data/chaos_poi.lua" ] || die "no $SERVER/data/chaos_poi.lua (install step poi)"

log "bot program"
dotnet build -c Release -o "$WORK/journeybin" "$REPO/unity/Core.LiveCheck" > "$WORK/journey-build.log" 2>&1 || { tail -n 30 "$WORK/journey-build.log"; die "Core.LiveCheck does not build"; }

dbq() { mariadb --no-defaults --socket="$SOCK" -uroot "$@"; }

# one fresh account and character the way the website makes one (level 1, 150 health, 0 mana, 400 capacity, position 0,0,0, last login 0):
# the first login gives the start level, the kit and the temple of Cinderhold. new_char TAG VOCATION NAME
declare -A ACC PASSW
declare -A NAMES=([warrior]="Live Jb Warrior" [ranger]="Live Jb Ranger" [mystic]="Live Jb Mystic")
new_char() {
  local tag=$1 voc=$2 name=$3
  ACC[$tag]="jb$(openssl rand -hex 4)"
  PASSW[$tag]=$(openssl rand -hex 12)
  dbq chaos <<SQL
INSERT INTO accounts (name, password, type, creation) VALUES ('${ACC[$tag]}', SHA1('${PASSW[$tag]}'), 1, UNIX_TIMESTAMP());
INSERT INTO players (name, group_id, account_id, vocation, level, experience, health, healthmax, mana, manamax, cap, soul,
                     sex, looktype, lookhead, lookbody, looklegs, lookfeet, lookaddons, town_id, posx, posy, posz, lastlogin)
  SELECT '$name', 1, id, $voc, 1, 0, 150, 150, 0, 0, 400, 100, 1, 128, 78, 68, 58, 76, 3, 2, 0, 0, 0, 0 FROM accounts WHERE name = '${ACC[$tag]}';
SQL
}
new_char warrior 4 "${NAMES[warrior]}"
new_char ranger 3 "${NAMES[ranger]}"
new_char mystic 1 "${NAMES[mystic]}"

log "three bots, $MINUTES min or level $LEVEL"
pids=()
seed=0
for tag in warrior ranger mystic; do
  seed=$((seed + 1))

  (
    export CHAOS_LIVE_PASSWORD="${PASSW[$tag]}"
    export CHAOS_LIVE_BIND="127.1.0.$seed"   # one source address per bot (the server allows one connection per address)
    exec dotnet "$WORK/journeybin/Core.LiveCheck.dll" 127.0.0.1 "$CHAOS_LIVE_PORT" "${ACC[$tag]}" "${NAMES[$tag]}" --identity chaos --journey \
      --otb "$SERVER/data/items/items.otb" --poi "$SERVER/data/chaos_poi.lua" --journey-minutes "$MINUTES" --journey-level "$LEVEL" \
      --journey-out "$OUT/bot-$tag.json" --seed "$seed" --class "$tag" > "$OUT/bot-$tag.log" 2>&1
  ) &
  pids+=($!)
  sleep 3
done
rc=0
for p in "${pids[@]}"; do wait "$p" || rc=1; done

log "report"
python3 -I "$REPO/server/tools/journey_report.py" "$OUT"/bot-*.json --model-dir "$REPO/server" --out "$OUT/journey-report.md" --json "$OUT/journey-summary.json" || rc=1
if [ -n "${GITHUB_STEP_SUMMARY:-}" ] && [ -f "$OUT/journey-report.md" ]; then cat "$OUT/journey-report.md" >> "$GITHUB_STEP_SUMMARY"; fi
tail -n 300 "$WORK/tfs.log" > "$OUT/tfs-log-tail.txt" 2>/dev/null || true
# passwords and the guard key are cut from every text file as a last guard
for secret in "${PASSW[@]}" "${CHAOS_CLIENT_KEY:-}"; do
  [ -n "$secret" ] || continue
  grep -l -F -r -- "$secret" "$OUT" 2>/dev/null | while read -r f; do sed -i "s/$secret/<removed>/g" "$f"; done || true
done
exit "$rc"
