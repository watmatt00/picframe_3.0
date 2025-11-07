#!/bin/bash
# update_picframe.sh
# Purpose: Pull latest updates from GitHub and restart picframe service

LOG_FILE="$HOME/logs/frame_sync.log"
REPO_DIR="$HOME/picframe_3.0"
RESTART_SCRIPT="$REPO_DIR/app_control/pf_restart_svc.sh"

log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') update_picframe.sh - $message" | tee -a "$LOG_FILE" >&2
}

log_message "===== Starting picframe update ====="

# Ensure repo exists
if [ ! -d "$REPO_DIR/.git" ]; then
    log_message "Repository not found at $REPO_DIR"
    exit 1
fi

cd "$REPO_DIR" || exit 1

# Run git sync (fetch, rebase, push)
if git sync >> "$LOG_FILE" 2>&1; then
    log_message "Git sync completed successfully."
else
    log_message "Git sync failed!"
    exit 1
fi

# Fix permissions
chmod -R 755 "$REPO_DIR"
log_message "Permissions set."

# Restart the picframe service
if [ -x "$RESTART_SCRIPT" ]; then
    log_message "Restarting picframe service via pf_restart_svc.sh..."
    bash "$RESTART_SCRIPT"
    log_message "Restart command issued."
else
    log_message "Restart script not found or not executable: $RESTART_SCRIPT"
    exit 1
fi

log_message "===== picframe update complete ====="
exit 0
