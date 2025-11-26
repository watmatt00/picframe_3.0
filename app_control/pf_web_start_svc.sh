#!/bin/bash
set -euo pipefail

LOG_FILE="$HOME/logs/frame_sync.log"

log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') pf_web_start_svc.sh  - $message" | tee -a "$LOG_FILE" >&2
}

log_message "Starting pf-web-status.service"
sudo systemctl start pf-web-status.service
