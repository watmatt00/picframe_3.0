#!/bin/bash
# chk_status.sh
# Report:
#   1. Last successful file_sync run
#   2. Last time files were downloaded
#   3. Last time the picframe service was restarted
#
# Usage: ./chk_log_status.sh [optional_log_file]

set -euo pipefail

LOG_FILE="${1:-$HOME/logs/frame_sync.log}"

if [[ ! -f "$LOG_FILE" ]]; then
    echo "Log file not found: $LOG_FILE" >&2
    exit 1
fi

############################################
# Grab last relevant log lines
############################################

# 1) Last SUCCESSFUL file_sync run
#    Success = SYNC_RESULT: OK or SYNC_RESULT: RESTART
last_success_line="$(
    grep -E 'SYNC_RESULT: (OK|RESTART)' "$LOG_FILE" | tail -n 1 || true
)"

# 2) Last time files were downloaded (i.e., rclone sync actually ran and finished)
#    From perform_sync():
#      log_message "rclone sync completed successfully."
last_download_line="$(
    grep 'rclone sync completed successfully.' "$LOG_FILE" | tail -n 1 || true
)"

# 3) Last time service was successfully restarted
#    From restart_picframe_service():
#      log_message "Service restarted successfully."
last_restart_line="$(
    grep 'Service restarted successfully.' "$LOG_FILE" | tail -n 1 || true
)"

echo "Log file: $LOG_FILE"
echo "----------------------------------------"

############################################
# 1. Check: Last SUCCESSFUL file_sync run
############################################
echo
echo "--------------------------------------------"
echo "   Check Last Successful file_sync Run"
echo "--------------------------------------------"
echo

if [[ -n "$last_success_line" ]]; then
    # Format: "YYYY-MM-DD HH:MM:SS frame_sync.sh [MODE] - SYNC_RESULT: ..."
    success_time="$(awk '{print $1, $2}' <<< "$last_success_line")"
    success_source="$(awk '{print $3}' <<< "$last_success_line")"

    echo "Last successful file_sync run:"
    echo "  Time:   $success_time"
    echo "  Source: $success_source"
    echo "  Line:   $last_success_line"
else
    echo "Last successful file_sync run:"
    echo "  No entries found matching: SYNC_RESULT: OK or RESTART"
fi

############################################
# 2. Check: Last File Download
############################################
echo
echo "--------------------------------------------"
echo "   Check Last File Download"
echo "--------------------------------------------"
echo

if [[ -n "$last_download_line" ]]; then
    # Format: "YYYY-MM-DD HH:MM:SS frame_sync.sh [MODE] - rclone sync completed successfully."
    download_time="$(awk '{print $1, $2}' <<< "$last_download_line")"
    download_source="$(awk '{print $3}' <<< "$last_download_line")"

    echo "Last file download (rclone sync completed):"
    echo "  Time:   $download_time"
    echo "  Source: $download_source"
    echo "  Line:   $last_download_line"
else
    echo "Last file download:"
    echo "  No entries found matching: rclone sync completed successfully."
fi

############################################
# 3. Check: Last Service Restart
############################################
echo
echo "--------------------------------------------"
echo "   Check Restart"
echo "--------------------------------------------"
echo

if [[ -n "$last_restart_line" ]]; then
    # Format: "YYYY-MM-DD HH:MM:SS frame_sync.sh [MODE] - Service restarted successfully."
    last_restart_time="$(awk '{print $1, $2}' <<< "$last_restart_line")"
    last_restart_source="$(awk '{print $3}' <<< "$last_restart_line")"

    echo "Last service restart (picframe.service):"
    echo "  Time:   $last_restart_time"
    echo "  Source: $last_restart_source"
    echo "  Line:   $last_restart_line"
else
    echo "Last service restart (picframe.service):"
    echo "  No entries found matching: Service restarted successfully."
fi
