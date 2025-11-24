#!/bin/bash
set -euo pipefail

# update_picframe.sh
# Purpose: Pull latest updates from GitHub, reset working tree on Pi to origin/main,
# refresh crontab, and restart picframe service.

LOG_FILE="$HOME/logs/frame_sync.log"
REPO_DIR="$HOME/picframe_3.0"
RESTART_SCRIPT="$REPO_DIR/app_control/pf_restart_svc.sh"
CRONTAB_FILE="$REPO_DIR/app_control/crontab"

REMOTE="origin"
BRANCH="main"

log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') update_picframe.sh - $message" | tee -a "$LOG_FILE" >&2
}

log_message "===== Starting picframe update ====="

# Ensure repo exists
if [[ ! -d "$REPO_DIR/.git" ]]; then
    log_message "ERROR: Repository not found at $REPO_DIR"
    exit 1
fi

cd "$REPO_DIR"

log_message "Fetching latest changes from $REMOTE/$BRANCH..."
if git fetch "$REMOTE" "$BRANCH" >>"$LOG_FILE" 2>&1; then
    log_message "git fetch completed successfully."
else
    log_message "ERROR: git fetch failed."
    exit 1
fi

log_message "Resetting working tree to $REMOTE/$BRANCH (discarding local changes)..."
if git reset --hard "$REMOTE/$BRANCH" >>"$LOG_FILE" 2>&1; then
    log_message "Working tree reset to $REMOTE/$BRANCH. Local changes discarded."
else
    log_message "ERROR: git reset --hard failed."
    exit 1
fi

log_message "Refreshing crontab from $CRONTAB_FILE..."
if crontab "$CRONTAB_FILE"; then
    log_message "Crontab updated successfully."
else
    log_message "ERROR: Failed to update crontab."
    exit 1
fi

log_message "Restarting picframe service via $RESTART_SCRIPT..."
if /bin/bash "$RESTART_SCRIPT"; then
    log_message "Picframe service restart completed successfully."
else
    log_message "ERROR: Picframe service restart failed."
    exit 1
fi

log_message "===== Picframe update finished successfully ====="
