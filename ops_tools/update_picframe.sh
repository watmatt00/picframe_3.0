#!/bin/bash
set -euo pipefail

# -------------------------------------------------------------------
# update_picframe.sh
# Purpose: Pull latest updates from GitHub, refresh crontab, and
#          restart the picframe service on the Pi.
#
# Run as: pi@kframe (never with sudo)
# -------------------------------------------------------------------

LOG_FILE="$HOME/logs/frame_sync.log"
REPO_DIR="$HOME/picframe_3.0"
RESTART_SCRIPT="$REPO_DIR/app_control/pf_restart_svc.sh"
CRONTAB_FILE="$REPO_DIR/app_control/crontab"

# -------------------------------------------------------------------
# Safety checks
# -------------------------------------------------------------------

# 1) Don't allow root
if [[ $EUID -eq 0 ]]; then
  echo "ERROR: Do not run update_picframe.sh as root. Use the 'pi' user." >&2
  exit 1
fi

# 2) Ensure log directory is present and writable
LOG_DIR="$(dirname "$LOG_FILE")"
mkdir -p "$LOG_DIR"

if [[ ! -w "$LOG_DIR" ]]; then
  echo "ERROR: Log directory $LOG_DIR is not writable by user $USER." >&2
  exit 1
fi

# Simple logger
log_message() {
  local message="$1"
  echo "$(date '+%Y-%m-%d %H:%M:%S') update_picframe.sh - $message" | tee -a "$LOG_FILE" >&2
}

log_message "===== Starting picframe update ====="

# -------------------------------------------------------------------
# Ensure repo exists and is owned by the current user
# -------------------------------------------------------------------

if [[ ! -d "$REPO_DIR/.git" ]]; then
  log_message "Repository not found at $REPO_DIR"
  exit 1
fi

# Optional: warn if any files are not owned by the current user
if find "$REPO_DIR" ! -user "$USER" -print -quit | grep -q .; then
  log_message "WARNING: Some files in $REPO_DIR are not owned by $USER. Consider fixing with:"
  log_message "         sudo chown -R $USER:$USER $REPO_DIR"
fi

cd "$REPO_DIR"

# -------------------------------------------------------------------
# Git update (no aliases, no magic)
# -------------------------------------------------------------------

log_message "Checking for local changes..."
if ! git diff --quiet || ! git diff --cached --quiet; then
  log_message "Local changes detected. Aborting update to avoid losing work."
  exit 1
fi

log_message "Fetching latest changes from origin/main..."
if ! git fetch origin main >> "$LOG_FILE" 2>&1; then
  log_message "Git fetch failed. See log for details."
  exit 1
fi

log_message "Rebasing onto origin/main..."
if ! git rebase origin/main >> "$LOG_FILE" 2>&1; then
  log_message "Git rebase failed. See log for details."
  exit 1
fi

log_message "Git pull (fetch + rebase) completed successfully."

# -------------------------------------------------------------------
# Refresh crontab
# -------------------------------------------------------------------

if [[ -f "$CRONTAB_FILE" ]]; then
  log_message "Updating user crontab from $CRONTAB_FILE..."
  if crontab "$CRONTAB_FILE"; then
    log_message "Crontab updated successfully."
  else
    log_message "Failed to update crontab."
    exit 1
  fi
else
  log_message "Crontab file not found at $CRONTAB_FILE (skipping crontab update)."
fi

# -------------------------------------------------------------------
# Restart picframe service
# -------------------------------------------------------------------

if [[ -x "$RESTART_SCRIPT" ]]; then
  log_message "Restarting picframe service via $RESTART_SCRIPT..."
  if "$RESTART_SCRIPT"; then
    log_message "Picframe service restart completed."
  else
    log_message "Picframe service restart FAILED."
    exit 1
  fi
else
  log_message "Restart script $RESTART_SCRIPT not found or not executable."
fi

log_message "===== Picframe update completed successfully ====="
