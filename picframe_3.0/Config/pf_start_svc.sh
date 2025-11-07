#!/bin/bash

LOG_FILE="$HOME/logs/frame_sync.log"


# Function to log messages
log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') pf_start_svc.sh  - $message" | tee -a "$LOG_FILE" >&2
}


# Start the service
log_message "Begining of restart"
if systemctl --user start picframe.service; then
    echo "Service picframe.service started successfully."
    log_message "Service picframe.service started successfully"
else
    echo "Failed to start picframe.service."
    log_message "Failed to start picframe.service"
    exit 1
fi
