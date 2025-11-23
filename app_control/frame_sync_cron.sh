#!/bin/bash

# Required for systemctl --user inside cron
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

DISABLE_FILE="$HOME/picframe_3.0/ops_tools/frame_sync.disabled"
LOG_DIR="$HOME/logs"
LOG_FILE="$LOG_DIR/frame_sync_$(date +%Y-%m-%d).log"

mkdir -p "$LOG_DIR"

# If SAFE_MODE flag exists, log and exit quietly.
if [ -f "$DISABLE_FILE" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') frame_sync_cron.sh - Frame sync disabled via $DISABLE_FILE; skipping frame_sync.sh" >>"$LOG_FILE" 2>&1
    exit 0
fi

# Otherwise run the main sync script using /bin/bash (same as your original cron line)
/bin/bash /home/pi/picframe_3.0/ops_tools/frame_sync.sh >>"$LOG_FILE" 2>&1
