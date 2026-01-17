#!/bin/bash
# auto_update_cron.sh - Automated update wrapper for cron
#
# This script is called hourly by cron and checks if an update should run
# based on the configured schedule. It follows the frame_sync_cron.sh pattern.
#
# Schedule is configured in ~/.picframe/config:
#   AUTO_UPDATE_ENABLED=true/false
#   AUTO_UPDATE_FREQUENCY=weekly/biweekly/monthly
#   AUTO_UPDATE_DAY=0-6 (Sunday-Saturday)
#   AUTO_UPDATE_HOUR=0-23
#   AUTO_UPDATE_MINUTE=0-59

set -euo pipefail

# Required for systemctl --user inside cron
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

# Paths
APP_ROOT="$HOME/picframe_3.0"
DISABLE_FILE="$APP_ROOT/ops_tools/auto_update.disabled"
CONFIG_READER="$APP_ROOT/app_control/read_auto_update_config.py"
UPDATE_SCRIPT="$APP_ROOT/ops_tools/update_app.sh"
LOG_DIR="$HOME/logs"
LOG_FILE="$LOG_DIR/auto_update.log"
STATUS_FILE="$HOME/.picframe/auto_update_status.json"

mkdir -p "$LOG_DIR"
mkdir -p "$(dirname "$STATUS_FILE")"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') auto_update_cron.sh - $1" | tee -a "$LOG_FILE" >&2
}

write_status() {
    local status="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    cat > "$STATUS_FILE" << EOF
{
    "last_run": "$timestamp",
    "status": "$status",
    "message": "$message"
}
EOF
}

# ---------------------------------------------------------------------------
# Check if disabled
# ---------------------------------------------------------------------------

if [ -f "$DISABLE_FILE" ]; then
    log_message "Auto-update disabled via $DISABLE_FILE; skipping"
    exit 0
fi

# ---------------------------------------------------------------------------
# Read configuration
# ---------------------------------------------------------------------------

if [ ! -f "$CONFIG_READER" ]; then
    log_message "ERROR: Config reader not found: $CONFIG_READER"
    exit 1
fi

# Read config into variables
eval "$(python3 "$CONFIG_READER")"

# Check if enabled
if [ "${ENABLED:-false}" != "true" ]; then
    # Silently exit - auto-update is disabled
    exit 0
fi

# ---------------------------------------------------------------------------
# Check if current time matches schedule
# ---------------------------------------------------------------------------

CURRENT_DOW=$(date +%w)    # Day of week (0=Sunday)
CURRENT_HOUR=$(date +%-H)  # Hour (0-23, no leading zero)
CURRENT_DAY=$(date +%-d)   # Day of month (1-31, no leading zero)
CURRENT_WEEK=$(date +%V)   # ISO week number

# Check day of week
if [ "$CURRENT_DOW" != "$DAY" ]; then
    exit 0
fi

# Check hour
if [ "$CURRENT_HOUR" != "$HOUR" ]; then
    exit 0
fi

# Check frequency
case "$FREQUENCY" in
    weekly)
        # Run every week on the configured day - no additional check needed
        ;;
    biweekly)
        # Run on odd weeks only
        if [ $((CURRENT_WEEK % 2)) -eq 0 ]; then
            exit 0
        fi
        ;;
    monthly)
        # Run on first occurrence of configured day in month (day 1-7)
        if [ "$CURRENT_DAY" -gt 7 ]; then
            exit 0
        fi
        ;;
    *)
        log_message "ERROR: Unknown frequency: $FREQUENCY"
        exit 1
        ;;
esac

# ---------------------------------------------------------------------------
# Run update
# ---------------------------------------------------------------------------

log_message "===== Starting scheduled auto-update ====="
log_message "Schedule: $FREQUENCY on day $DAY at $HOUR:$MINUTE"

if [ ! -f "$UPDATE_SCRIPT" ]; then
    log_message "ERROR: Update script not found: $UPDATE_SCRIPT"
    write_status "error" "Update script not found"
    exit 1
fi

if /bin/bash "$UPDATE_SCRIPT" >> "$LOG_FILE" 2>&1; then
    log_message "===== Auto-update completed successfully ====="
    write_status "success" "Update completed successfully"
else
    exit_code=$?
    log_message "===== Auto-update failed (exit code: $exit_code) ====="
    write_status "error" "Update failed with exit code $exit_code"
fi
