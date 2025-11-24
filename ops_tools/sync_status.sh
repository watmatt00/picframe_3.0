#!/bin/bash
# chk_log_status.sh
# Report the last successful sync time and last service restart time
# Usage: ./chk_log_status.sh [optional_log_file]

set -euo pipefail

LOG_FILE="${1:-$HOME/logs/frame_sync.log}"

if [[ ! -f "$LOG_FILE" ]]; then
    echo "Log file not found: $LOG_FILE" >&2
    exit 1
fi

# Find last successful sync line (based on SYNC_RESULT: OK)
last_sync_line="$(grep 'SYNC_RESULT: OK' "$LOG_FILE" | tail -n 1 || true)"

# Find last restart line (anything mentioning restart + picframe.service)
last_restart_line="$(grep -Ei 'restart.*picframe\.service' "$LOG_FILE" | tail -n 1 || true)"

echo "Log file: $LOG_FILE"
echo "----------------------------------------"

if [[ -n "$last_sync_line" ]]; then
    last_sync_time="$(awk '{print $1, $2}' <<< "$last_sync_line")"
    last_sync_source="$(awk '{print $3}' <<< "$last_sync_line")"

    echo "Last successful sync:"
    echo "  Time:   $last_sync_time"
    echo "  Source: $last_sync_source"
    echo "  Line:   $last_sync_line"
else
    echo "Last successful sync:"
    echo "  No entries found matching: SYNC_RESULT: OK"
fi

echo

if [[ -n "$last_restart_line" ]]; then
    last_restart_time="$(awk '{print $1, $2}' <<< "$last_restart_line")"
    last_restart_source="$(awk '{print $3}' <<< "$last_restart_line")"

    echo "Last service restart (picframe.service):"
    echo "  Time:   $last_restart_time"
    echo "  Source: $last_restart_source"
    echo "  Line:   $last_restart_line"
else
    echo "Last service restart (picframe.service):"
    echo "  No entries found matching: restart.*picframe.service"
fi
