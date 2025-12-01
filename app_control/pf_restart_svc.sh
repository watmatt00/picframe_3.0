#!/bin/bash
set -euo pipefail

LOG_FILE="$HOME/logs/frame_sync.log"
mkdir -p "$HOME/logs"

# Function to log messages
log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') pf_restart_svc.sh - $message" | tee -a "$LOG_FILE" >&2
}

# Restart the service
log_message "Beginning of service restart"
if systemctl --user restart picframe.service; then
    echo "Service picframe.service restarted successfully"
    log_message "Service picframe.service restarted successfully"
else
    echo "Failed to restart picframe.service"
    log_message "Failed to restart picframe.service"
    exit 1
fi
