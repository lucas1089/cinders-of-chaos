#!/bin/sh
# Crash record for the game server: chaos-server.service runs it after every stop (ExecStopPost). systemd sets
# SERVICE_RESULT ("success" for a clean stop, such as the daily server save shutdown or systemctl stop) and
# EXIT_CODE / EXIT_STATUS. On anything else it keeps the last lines of the console log in /var/log/chaos/crashes/, and
# posts a short alert when CHAOS_ALERT_WEBHOOK (a Discord-style webhook URL, in /etc/chaos/chaos.env) is set.
# systemd then starts the engine again (Restart=always). docs/LAUNCH.md "Running it".
LOG=${CHAOS_SERVER_LOG:-/var/log/chaos/server.log}
DIR=${CHAOS_CRASH_DIR:-/var/log/chaos/crashes}
[ "${SERVICE_RESULT:-success}" = "success" ] && exit 0
mkdir -p "$DIR" 2>/dev/null || exit 0
STAMP=$(date +%Y%m%d-%H%M%S)
FILE="$DIR/crash-$STAMP.log"
{
	echo "result=$SERVICE_RESULT code=$EXIT_CODE status=$EXIT_STATUS at $(date -Is)"
	echo "--- last 200 lines of $LOG ---"
	tail -n 200 "$LOG" 2>/dev/null
} > "$FILE"
# keep the newest 50 records
ls -1t "$DIR"/crash-*.log 2>/dev/null | tail -n +51 | xargs -r rm -f
if [ -n "$CHAOS_ALERT_WEBHOOK" ] && command -v curl >/dev/null 2>&1; then
	MSG="Cinders of Chaos: the game server stopped ($SERVICE_RESULT $EXIT_CODE $EXIT_STATUS) and is restarting. Log: $FILE"
	curl -s -m 10 -H 'Content-Type: application/json' -d "{\"content\": \"$MSG\"}" "$CHAOS_ALERT_WEBHOOK" >/dev/null 2>&1
fi
exit 0
