#!/bin/bash
# update_picframe.sh
# Purpose: Pull latest updates from GitHub, refresh crontab, and restart picframe service

set -Eeuo pipefail

LOG_FILE="$HOME/logs/frame_sync.log"
REPO_DIR="$HOME/picframe_3.0"
RESTART_SCRIPT="$REPO_DIR/app_control/pf_restart_svc.sh"
CRONTAB_FILE="$REPO_DIR/app_control/crontab"

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

# Ensure clean working tree on Pi (treat Pi as read-only consumer of repo)
log_message "Checking for local changes in repo..."

if ! git diff --quiet || ! git diff --cached --quiet; then
    log_message "Local changes detected on Pi. Resetting to last committed state (discarding local edits)."
    git reset --hard HEAD >> "$LOG_FILE" 2>&1
    git clean -fd >> "$LOG_FILE" 2>&1
else
    log_message "No local changes detected."
fi

# Pull latest from origin/main
log_message "Pulling latest changes from origin/main with rebase..."
if git pull --rebase origin main >> "$LOG_FILE" 2>&1; then
    log_message "Git pull completed successfully."
else
    log_message "Git pull failed! Check git status and logs."
    git status >> "$LOG_FILE" 2>&1
    exit 1
fi

# Fix permissions on script files only (exclude archive directory)
find "$REPO_DIR/app_control" -type f -name "*.sh" -exec chmod 755 {} \;
find "$REPO_DIR/ops_tools" -type f -name "*.sh" ! -path "$REPO_DIR/ops_tools/archive/*" -exec chmod 755 {} \;
log_message "Permissions set on script files (excluding archive)."


# Auto-apply updated crontab if it exists
if [ -f "$CRONTAB_FILE" ]; then
    log_message "Updating system crontab from repo..."
    if crontab "$CRONTAB_FILE"; then
        log_message "System crontab successfully updated from $CRONTAB_FILE"
    else
        log_message "Failed to update system crontab!"
    fi
else
    log_message "No crontab file found at $CRONTAB_FILE (skipping)"
fi

# Restart the picframe service
if [ -x "$RESTART_SCRIPT" ]; then
    log_message "Restarting picframe service via pf_restart_svc.sh..."
    bash "$RESTART_SCRIPT"
    log_message "Restart command issued."
else
    log_message "Restart script not found or not executable: $RESTART_SCRIPT"
    exit 1
fi

# 🔄 Reload and restart user service to apply latest override
if systemctl --user daemon-reload >> "$LOG_FILE" 2>&1 && \
   systemctl --user restart picframe.service >> "$LOG_FILE" 2>&1; then
    log_message "Systemd user service reloaded and restarted."
else
    log_message "Failed to reload/restart systemd user service picframe.service."
    exit 1
fi

log_message "===== picframe update complete ====="
exit 0
