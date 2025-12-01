#!/bin/bash
set -euo pipefail

LOG_FILE="$HOME/logs/frame_sync.log"
mkdir -p "$HOME/logs"

log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') pf_web_stop_svc.sh - $message" | tee -a "$LOG_FILE" >&2
}

log_message "Stopping pf-web-status.service"
sudo systemctl stop pf-web-status.service
