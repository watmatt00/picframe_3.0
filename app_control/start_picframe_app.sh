#!/bin/bash

LOG_FILE="$HOME/logs/frame_sync.log"


# Function to log messages
log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') start_picframe_app.sh  - $message" | tee -a "$LOG_FILE" >&2
}

log_message "Starting picframe app"
xset -display :0 dpms 0 0 0 &
xset -display :0 s off &
source /home/pi/venv_picframe/bin/activate  # activate phyton virtual env
picframe
