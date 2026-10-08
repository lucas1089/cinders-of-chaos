#!/usr/bin/env bash
# Stand-in for the mysql client, used by prepare_server.sh as `install_all.py --mysql`: instead of running the SQL step
# against a database it writes each file the step would run, in order, to $CAPTURE_DIR/chaos-NN.sql. Queries given
# with -e (install_all.py's SHOW TABLES before and after) print nothing.
set -euo pipefail
for a in "$@"; do
  if [ "$a" = "-e" ]; then exit 0; fi
done
: "${CAPTURE_DIR:?CAPTURE_DIR is not set}"
n=$(find "$CAPTURE_DIR" -maxdepth 1 -name 'chaos-*.sql' | wc -l)
cat > "$CAPTURE_DIR/$(printf 'chaos-%02d.sql' "$n")"
