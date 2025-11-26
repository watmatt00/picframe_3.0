#!/bin/bash
#
# frame_sync.sh — Sync local photo frame folder with Google Drive via rclone
# Runs every 15 minutes (recommended from cron or systemd timer)
# Author: Matt P / ChatGPT optimized version
#

set -euo pipefail

# -------------------------------------------------------------------
# CONFIGURATION
# -------------------------------------------------------------------
RCLONE_REMOTE="kfgdrive:dframe"
LDIR="$HOME/Pictures/gdt_frame"
LOG_DIR="$HOME/logs"
LOG_FILE="$LOG_DIR/frame_sync_$(date +%Y-%m-%d).log"
RETENTION_DAYS=7
PICFRAME_SERVICE="picframe.service"
RCLONE_OPTS="--verbose --transfers=4 --checkers=4 --fast-list"

PATH=/usr/local/bin:/usr/bin:/bin

# -------------------------------------------------------------------
# FUNCTIONS
# -------------------------------------------------------------------

log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') frame_sync.sh - $message" | tee -a "$LOG_FILE"
}

rotate_logs() {
    # Remove any logs older than $RETENTION_DAYS
    find "$LOG_DIR" -name "frame_sync_*.log" -mtime +"$RETENTION_DAYS" -exec rm -f {} \; 2>/dev/null || true
}

ensure_log_dir() {
    mkdir -p "$LOG_DIR"
    if [ ! -w "$LOG_DIR" ]; then
        echo "ERROR: Cannot write to log directory $LOG_DIR" >&2
        exit 1
    fi
}

get_directory_count() {
    local dir_type="$1"
    local count=0
    if [ "$dir_type" = "google" ]; then
        count=$(rclone lsf "$RCLONE_REMOTE" --files-only | wc -l)
    elif [ "$dir_type" = "local" ]; then
        count=$(find "$LDIR" -type f | wc -l)
    else
        log_message "ERROR: Invalid directory type '$dir_type'"
        exit 1
    fi
    echo "$count"
}

sync_directories() {
    log_message "Starting rclone sync..."
    local attempts=0
    local max_attempts=3

    while (( attempts < max_attempts )); do
        if rclone sync "$RCLONE_REMOTE" "$LDIR" $RCLONE_OPTS >>"$LOG_FILE" 2>&1; then
            log_message "Sync successful."
            return 0
        fi
        attempts=$((attempts + 1))
        log_message "Sync attempt $attempts failed. Retrying in 10s..."
        sleep 10
    done

    log_message "ERROR: Sync failed after $max_attempts attempts."
    return 1
}

restart_picframe_service() {
    log_message "Restarting $PICFRAME_SERVICE..."
    if systemctl --user restart "$PICFRAME_SERVICE" 2>>"$LOG_FILE"; then
        if systemctl --user is-active --quiet "$PICFRAME_SERVICE"; then
            log_message "$PICFRAME_SERVICE restarted successfully."
            return 0
        fi
    fi
    log_message "ERROR: Failed to restart $PICFRAME_SERVICE."
    return 1
}

# -------------------------------------------------------------------
# MAIN SCRIPT
# -------------------------------------------------------------------

ensure_log_dir
rotate_logs
log_message "----- Starting directory check and sync process -----"

# Validate local directory
if [ ! -d "$LDIR" ]; then
    log_message "Local directory $LDIR not found. Creating..."
    mkdir -p "$LDIR"
fi

# Get counts
gdir_count=$(get_directory_count "google")
ldir_count=$(get_directory_count "local")
log_message "Google folder file count: $gdir_count"
log_message "Local folder file count: $ldir_count"

# Compare counts and sync if needed
if [ "$gdir_count" -eq "$ldir_count" ]; then
    log_message "Counts match. No sync required."
    exit 0
else
    log_message "Counts differ. Initiating sync..."
    if sync_directories; then
        log_message "Sync completed successfully. Restarting display service."
        restart_picframe_service || log_message "WARNING: Service restart failed."
    else
        log_message "ERROR: Sync failed; skipping service restart."
        exit 1
    fi
fi

# Final verification
log_message "Verifying sync results..."
gdir_count_post=$(get_directory_count "google")
ldir_count_post=$(get_directory_count "local")
log_message "Post-sync Google count: $gdir_count_post"
log_message "Post-sync Local count: $ldir_count_post"

if [ "$gdir_count_post" -eq "$ldir_count_post" ]; then
    log_message "Final verification: Directories are synchronized."
else
    log_message "WARNING: Final verification mismatch. Manual check recommended."
fi

log_message "----- Process complete -----"
exit 0
