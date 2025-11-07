#!/bin/bash

LOG_FILE="$HOME/logs/frame_sync.log"

# Function to log messages
log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') pf_stop_svc.sh  - $message" | tee -a "$LOG_FILE" >&2
}


# Restart the service
#log_message "Begining of svc stop"
if systemctl --user stop picframe.service; then
    echo "Service picframe.service stopped successfully."
    log_message "Service picframe.service stopped successfully."
else
    echo "Failed to stop picframe.service."
    log_message "Failed to stop picframe.service"
    exit 1
fi
