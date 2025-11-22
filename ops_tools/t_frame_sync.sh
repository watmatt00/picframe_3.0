#!/bin/bash
#
# t_frame_sync.sh — Test version
# Sync local photo frame folder with Google Drive via rclone
# Intended to run every 15 minutes (from cron or systemd timer)
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

# How many log lines from the end of the log to scan when checking SYNC_RESULT history
SYNC_RESULT_TAIL_LINES=500

# Disable flag to stop scheduled runs (wrapper should honor this)
DISABLE_FILE="$HOME/picframe_3.0/ops_tools/t_frame_sync.disabled"

PATH=/usr/local/bin:/usr/bin:/bin

# -------------------------------------------------------------------
# FUNCTIONS
# -------------------------------------------------------------------

log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') t_frame_sync.sh - $message" | tee -a "$LOG_FILE"
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

# Detect 3 consecutive syncs that restarted the service.
# We rely only on summary lines that start with "SYNC_RESULT:".
#   - Each run MUST log exactly one "SYNC_RESULT:" line.
#   - Last 3 "SYNC_RESULT:" lines all being "RESTART" => 3 consecutive restart runs.
detect_three_consecutive_sync_restarts() {
    local last_three

    # If log file doesn't exist yet, we can't detect anything
    if [ ! -f "$LOG_FILE" ]; then
        return 1
    fi

    # Look at recent lines to keep this fast even if log grows
    last_three=$(tail -n "$SYNC_RESULT_TAIL_LINES" "$LOG_FILE" 2>/dev/null         | grep "SYNC_RESULT:"         | tail -n 3)

    # Need at least 3 SYNC_RESULT entries
    if [ "$(printf '%s\n' "$last_three" | wc -l)" -lt 3 ]; then
        return 1
    fi

    # If ANY of the last 3 lines has NO_RESTART, they are not 3 consecutive restarts
    if echo "$last_three" | grep -q "SYNC_RESULT: NO_RESTART"; then
        return 1
    fi

    # All three of the last SYNC_RESULT entries are RESTART
    return 0
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
log_message "----- Starting directory check and sync process (TEST: t_frame_sync.sh) -----"

# If a disable flag exists:
# - Non-interactive (cron/wrapper): log and exit quietly.
# - Interactive (manual terminal run): prompt to clear the flag and continue, or exit.
if [ -f "$DISABLE_FILE" ]; then
    if [ -t 0 ]; then
        # Interactive session (manual run)
        echo "========================================================"
        echo "  Frame sync is currently DISABLED."
        echo "  Disable flag detected at: $DISABLE_FILE"
        echo "========================================================"
        read -r -p "Delete disable flag and run sync anyway? [y/N]: " ans

        case "$ans" in
            [Yy]*)
                rm -f "$DISABLE_FILE"
                log_message "Disable flag $DISABLE_FILE removed by user; proceeding with normal run."
                # IMPORTANT: do NOT log a SYNC_RESULT here; the run is continuing.
                ;;
            *)
                log_message "Frame sync is disabled via $DISABLE_FILE. User chose not to override."
                log_message "SYNC_RESULT: NO_RESTART - Frame sync disabled by flag; no action taken."
                log_message "----- Process complete (disabled; user declined override) -----"
                exit 0
                ;;
        esac
    else
        # Non-interactive (cron/wrapper/etc.)
        log_message "Frame sync is disabled via $DISABLE_FILE. Skipping sync and restart."
        log_message "SYNC_RESULT: NO_RESTART - Frame sync disabled by flag; no action taken."
        log_message "----- Process complete (disabled; non-interactive) -----"
        exit 0
    fi
fi

# Determine whether we should enter SAFE_MODE based on prior runs
SAFE_MODE=0
if detect_three_consecutive_sync_restarts; then
    SAFE_MODE=1
    log_message "Detected 3 consecutive SYNC_RESULT: RESTART entries – SAFE_MODE enabled and disabling future scheduled runs."
    # Create / refresh the disable flag so wrapper will stop calling this script
    echo "$(date '+%Y-%m-%d %H:%M:%S') SAFE_MODE triggered; t_frame_sync.sh disabled." > "$DISABLE_FILE"
fi

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
    # Exactly one SYNC_RESULT per run
    log_message "SYNC_RESULT: NO_RESTART - Counts match; no sync or service restart required."
    log_message "----- Process complete (no changes) -----"
    exit 0
else
    log_message "Counts differ. Initiating sync..."
    if sync_directories; then
        # Sync completed OK
        if [ "$SAFE_MODE" -eq 1 ]; then
            # We intentionally do NOT restart in SAFE_MODE
            log_message "Sync completed successfully but SAFE_MODE is active; not restarting display service."
            log_message "SYNC_RESULT: NO_RESTART - Sync succeeded in SAFE_MODE; service restart suppressed."
        else
            log_message "Sync completed successfully. Restarting display service."
            if restart_picframe_service; then
                # Sync + restart both succeeded
                log_message "SYNC_RESULT: RESTART - Sync succeeded and display service was restarted."
            else
                # Restart failed; treat as NO_RESTART from the perspective of “successful restarts in a row”
                log_message "WARNING: Service restart failed."
                log_message "SYNC_RESULT: NO_RESTART - Sync succeeded but service restart failed."
            fi
        fi
    else
        # Sync failed; do not restart service
        log_message "ERROR: Sync failed; skipping service restart."
        log_message "SYNC_RESULT: NO_RESTART - Sync failed; service restart skipped."
        log_message "----- Process complete (errors during sync) -----"
        exit 1
    fi
fi

# Final verification (only reached if sync_directories succeeded)
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

log_message "----- Process complete (TEST: t_frame_sync.sh) -----"
exit 0
