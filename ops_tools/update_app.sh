#!/bin/bash
set -euo pipefail

LOG_FILE="$HOME/logs/frame_sync.log"
REPO_DIR="$HOME/picframe_3.0"
CRONTAB_FILE="$REPO_DIR/app_control/crontab"
PF_RESTART="$REPO_DIR/app_control/pf_restart_svc.sh"
DASHBOARD_RESTART="$REPO_DIR/app_control/pf_web_restart_svc.sh"

log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') update_app.sh - $message" | tee -a "$LOG_FILE" >&2
}

log_message "===== Starting app update ====="

# Ensure repo exists
if [[ ! -d "$REPO_DIR/.git" ]]; then
    log_message "Repository not found at $REPO_DIR (.git missing). Aborting."
    exit 1
fi

cd "$REPO_DIR"

# Check for local changes
log_message "Checking for local changes..."
if git status --porcelain | grep -q .; then
    log_message "Local changes detected. Please commit or stash before running update_app.sh."
    exit 1
fi

# Fetch + rebase from origin/main
log_message "Fetching latest changes from origin/main..."
git fetch origin main >>"$LOG_FILE" 2>&1

log_message "Rebasing onto origin/main..."
git rebase origin/main >>"$LOG_FILE" 2>&1

log_message "Git update (fetch + rebase) completed successfully."

# Update user crontab
log_message "Updating user crontab from $CRONTAB_FILE..."
if [[ -f "$CRONTAB_FILE" ]]; then
    if crontab "$CRONTAB_FILE"; then
        log_message "Crontab updated successfully."
    else
        log_message "Failed to update crontab from $CRONTAB_FILE."
    fi
else
    log_message "Crontab file not found at $CRONTAB_FILE. Skipping crontab update."
fi

# Restart picframe slideshow service (user service wrapper)
if [[ -x "$PF_RESTART" ]]; then
    log_message "Restarting picframe service via $PF_RESTART..."
    if "$PF_RESTART"; then
        log_message "Picframe service restart completed."
    else
        log_message "Picframe restart script returned non-zero exit code."
    fi
else
    log_message "Picframe restart script not found or not executable."
fi

# Restart web status dashboard (system service via wrapper)
if [[ -x "$DASHBOARD_RESTART" ]]; then
    log_message "Restarting web status dashboard via $DASHBOARD_RESTART..."
    if "$DASHBOARD_RESTART"; then
        log_message "Dashboard restart completed."
    else
        log_message "Dashboard restart script returned non-zero exit code."
    fi
else
    log_message "Dashboard restart script not found or not executable."
fi

log_message "===== App update completed successfully ====="
exit 0
