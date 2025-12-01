#!/bin/bash
set -euo pipefail

LOG_FILE="$HOME/logs/frame_sync.log"
mkdir -p "$HOME/logs"

# Function to log messages
log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') pf_stop_svc.sh - $message" | tee -a "$LOG_FILE" >&2
}

# Stop the service
log_message "Beginning of service stop"
if systemctl --user stop picframe.service; then
    echo "Service picframe.service stopped successfully"
    log_message "Service picframe.service stopped successfully"
else
    echo "Failed to stop picframe.service"
    log_message "Failed to stop picframe.service"
    exit 1
fi
