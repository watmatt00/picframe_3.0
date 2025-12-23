#!/bin/bash
set -euo pipefail

LOG_FILE="$HOME/logs/frame_sync.log"
mkdir -p "$HOME/logs"

log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') pf_web_stop_svc.sh - $message" | tee -a "$LOG_FILE" >&2
}

log_message "Stopping pf-web-status.service"
sudo systemctl stop pf-web-status.service || true

# Kill any rogue processes on port 5050
log_message "Checking for processes on port 5050"
if sudo ss -tulpn | grep -q ':5050'; then
    log_message "Found process on port 5050, killing it"
    PID=$(sudo ss -tulpn | grep ':5050' | grep -oP 'pid=\K\d+' | head -1)
    if [ -n "$PID" ]; then
        sudo kill "$PID" 2>/dev/null || true
        sleep 1
    fi
fi

log_message "Web status service stopped successfully"
