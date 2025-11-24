#!/bin/bash
# chk_log_status.sh
# Report the last file_sync run time, last file download, and last service restart time
# Usage: ./chk_log_status.sh [optional_log_file]

set -euo pipefail

LOG_FILE="${1:-$HOME/logs/frame_sync.log}"

if [[ ! -f "$LOG_FILE" ]]; then
    echo "Log file not found: $LOG_FILE" >&2
    exit 1
fi

# 1. Last time file_sync ran (start of frame_sync.sh)
last_sync_run_line="$(grep -E 'SYNC_RESULT: OK' "$LOG_FILE" | tail -n 1 || true)"

# 2. Last time files were downloaded (based on a known marker)
# Adjust pattern if your logs use something else
last_download_line="$(grep -E 'FILES_DOWNLOADED:' "$LOG_FILE" | tail -n 1 || true)"

# 3. Last service restart line
last_restart_line="$(grep -Ei 'restart.*picframe\.service' "$LOG_FILE" | tail -n 1 || true)"

clear
echo "Log file: $LOG_FILE"
echo "----------------------------------------"


###########################################
# 1. Check: Last file_sync run
###########################################
echo
echo "--------------------------------------------"
echo "   Check Last file_sync Run"
echo "--------------------------------------------"
echo

if [[ -n "$last_sync_run_line" ]]; then
    sync_run_time="$(awk '{print $1, $2}' <<< "$last_sync_run_line")"
    sync_run_source="$(awk '{print $3}' <<< "$last_sync_run_line")"

    echo "Last file_sync run:"
    echo "  Time:   $sync_run_time"
    echo "  Source: $sync_run_source"
    echo "  Line:   $last_sync_run_line"
else
    echo "Last file_sync run:"
    echo "  No entries found matching: frame_sync.sh - ===== Starting"
fi


###########################################
# 2. Check: Last file download event
###########################################
echo
echo "--------------------------------------------"
echo "   Check Last File Download"
echo "--------------------------------------------"
echo

if [[ -n "$last_download_line" ]]; then
    download_time="$(awk '{print $1, $2}' <<< "$last_download_line")"
    download_source="$(awk '{print $3}' <<< "$last_download_line")"

    echo "Last file download:"
    echo "  Time:   $download_time"
    echo "  Source: $download_source"
    echo "  Line:   $last_download_line"
else
    echo "Last file download:"
    echo "  No entries found matching: FILES_DOWNLOADED:"
fi


###########################################
# 3. Check: Last service restart
###########################################
echo
echo "--------------------------------------------"
echo "   Check Restart"
echo "--------------------------------------------"
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
