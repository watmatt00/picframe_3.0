#!/bin/bash
#
# t_frame_sync.sh — Test version
# Sync local photo frame folder with Google Drive via rclone
# Intended to run every 15 minutes (from cron or systemd timer)
# Author: Matt P / ChatGPT optimized version
#

set -euo pipefail

# -------------------------------------------------------------------
# SCRIPT IDENTITY (Option 1)
# -------------------------------------------------------------------
SCRIPT_NAME="$(basename "$0")"

if [[ "$SCRIPT_NAME" == t_* ]]; then
    RUN_MODE="TEST"
else
    RUN_MODE="PROD"
fi

# -------------------------------------------------------------------
# CONFIGURATION
# -------------------------------------------------------------------
# Example: replace the existing REMOTE/LDIR lines with these:

RCLONE_REMOTE="kfrphotos:KFR_kframe"
LDIR="$HOME/Pictures/kfr_frame"

#RCLONE_REMOTE="kfgdrive:dframe"          # rclone remote:path
#LDIR="$HOME/Pictures/gdt_frame"          # local directory for frame photos

LOG_DIR="$HOME/logs"
LOG_FILE="$LOG_DIR/frame_sync.log"

# Optional safe-mode flag for consecutive restart detection
SAFE_MODE_FILE="$HOME/picframe_3.0/ops_tools/safe_mode.flag"

# Picframe systemd user service
PICFRAME_SERVICE="picframe.service"

# Minimum expected file count to consider the remote "valid"
MIN_FILES=1

# Default sync mode: QUICK (count comparison). Use --d for DETAILED (rclone check).
SYNC_MODE="QUICK"

if [[ "${1-}" == "--d" ]]; then
    SYNC_MODE="DETAILED"
fi

# -------------------------------------------------------------------
# LOGGING
# -------------------------------------------------------------------
log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $SCRIPT_NAME [$RUN_MODE] - $message" | tee -a "$LOG_FILE" >&2
}

ensure_directories() {
    mkdir -p "$LOG_DIR"
    mkdir -p "$LDIR"
}

# -------------------------------------------------------------------
# RCLONE & ENV CHECKS
# -------------------------------------------------------------------
check_rclone_installed() {
    if ! command -v rclone >/dev/null 2>&1; then
        log_message "ERROR: rclone is not installed or not in PATH."
        log_message "SYNC_RESULT: ERROR"
        exit 1
    fi
}

check_rclone_config() {
    local config_file="$HOME/.config/rclone/rclone.conf"

    if [ ! -f "$config_file" ]; then
        log_message "ERROR: rclone config not found at $config_file"
        log_message "SYNC_RESULT: ERROR"
        exit 1
    fi

    if [ ! -r "$config_file" ]; then
        log_message "ERROR: rclone config $config_file is not readable by user $(whoami)"
        log_message "SYNC_RESULT: ERROR"
        exit 1
    fi
}

# -------------------------------------------------------------------
# DIRECTORY COUNT HELPERS (QUICK MODE)
# -------------------------------------------------------------------
get_directory_count() {
    local source="$1"

    case "$source" in
        google)
            # Count files in remote
            rclone lsf "$RCLONE_REMOTE" --files-only 2>/dev/null | wc -l
            ;;
        local)
            # Count files in local dir
            find "$LDIR" -type f 2>/dev/null | wc -l
            ;;
        *)
            log_message "ERROR: get_directory_count called with invalid source: $source"
            echo 0
            ;;
    esac
}

# -------------------------------------------------------------------
# DETAILED CHECK (OPTIONAL)
# -------------------------------------------------------------------
run_detailed_check() {
    log_message "Running detailed rclone check between remote and local..."
    if rclone check "$RCLONE_REMOTE" "$LDIR" --one-way --size-only >>"$LOG_FILE" 2>&1; then
        log_message "Detailed check: no differences reported by rclone."
        return 0
    else
        log_message "Detailed check: differences detected by rclone (see log for details)."
        return 1
    fi
}

# -------------------------------------------------------------------
# PICFRAME SERVICE CONTROL
# -------------------------------------------------------------------
restart_picframe_service() {
    log_message "Restarting picframe service: $PICFRAME_SERVICE"
    if systemctl --user restart "$PICFRAME_SERVICE" >>"$LOG_FILE" 2>&1; then
        log_message "Service $PICFRAME_SERVICE restarted successfully"
        return 0
    else
        log_message "ERROR: Failed to restart picframe service."
        return 1
    fi
}

# -------------------------------------------------------------------
# CONSECUTIVE RESTART DETECTION
#   We rely only on summary lines that start with "SYNC_RESULT:".
#   Each run MUST log exactly one "SYNC_RESULT:" line.
#   Last 3 "SYNC_RESULT:" lines all being "RESTART" => 3 consecutive restart runs.
# -------------------------------------------------------------------
detect_three_consecutive_sync_restarts() {
    local last_three

    # If log file doesn't exist yet, we can't detect anything
    if [ ! -f "$LOG_FILE" ]; then
        return 1
    fi

    last_three=$(grep "SYNC_RESULT:" "$LOG_FILE" | tail -3 | awk -F'SYNC_RESULT: ' '{print $2}')

    # If we have fewer than 3 entries, bail
    if [ "$(echo "$last_three" | wc -l)" -lt 3 ]; then
        return 1
    fi

    # Normalize whitespace
    last_three=$(echo "$last_three" | tr -d '[:space:]')

    # Expect exactly "RESTART", "RESTART", "RESTART" in some form
    if [[ "$last_three" == "RESTARTRESTARTRESTART" ]]; then
        return 0
    else
        return 1
    fi
}

enter_safe_mode_if_needed() {
    if detect_three_consecutive_sync_restarts; then
        log_message "Detected three consecutive SYNC_RESULT: RESTART. Enabling SAFE MODE."
        touch "$SAFE_MODE_FILE"
        log_message "SAFE MODE flag created at $SAFE_MODE_FILE"
    fi
}

# -------------------------------------------------------------------
# SYNC LOGIC
# -------------------------------------------------------------------
perform_sync() {
    log_message "Starting rclone sync from $RCLONE_REMOTE to $LDIR"
    if rclone sync "$RCLONE_REMOTE" "$LDIR"         --create-empty-src-dirs         --fast-list         >>"$LOG_FILE" 2>&1; then
        log_message "rclone sync completed successfully."
        return 0
    else
        log_message "ERROR: rclone sync failed. See log for details."
        return 1
    fi
}

quick_mode_flow() {
    log_message "Quick mode: comparing file counts between remote and local."

    local gdir_count ldir_count gdir_count_post ldir_count_post

    gdir_count=$(get_directory_count "google")
    ldir_count=$(get_directory_count "local")

    log_message "Initial Google count: $gdir_count"
    log_message "Initial Local count:  $ldir_count"

    if [ "$gdir_count" -lt "$MIN_FILES" ]; then
        log_message "WARNING: Google count ($gdir_count) below MIN_FILES ($MIN_FILES). Skipping sync."
        log_message "SYNC_RESULT: ERROR"
        return 1
    fi

    if [ "$gdir_count" -eq "$ldir_count" ]; then
        log_message "Counts match. No sync needed."
        log_message "SYNC_RESULT: OK"
        return 0
    fi

    log_message "Counts differ. Proceeding with sync..."
    if ! perform_sync; then
        log_message "SYNC_RESULT: ERROR"
        return 1
    fi

    # Post-sync verification via counts
    log_message "Verifying sync results via counts..."
    gdir_count_post=$(get_directory_count "google")
    ldir_count_post=$(get_directory_count "local")
    log_message "Post-sync Google count: $gdir_count_post"
    log_message "Post-sync Local count:  $ldir_count_post"

    if [ "$gdir_count_post" -eq "$ldir_count_post" ]; then
        log_message "Final verification: Directories are synchronized."
        log_message "SYNC_RESULT: RESTART"
        return 2
    else
        log_message "WARNING: Final verification mismatch. Manual check recommended."
        log_message "SYNC_RESULT: RESTART"
        return 2
    fi
}

detailed_mode_flow() {
    log_message "Detailed mode: using rclone check plus sync if needed."

    local check_result

    run_detailed_check
    check_result=$?

    if [ "$check_result" -eq 0 ]; then
        log_message "Detailed check: no sync required."
        log_message "SYNC_RESULT: OK"
        return 0
    fi

    log_message "Detailed check found differences. Proceeding with sync..."
    if ! perform_sync; then
        log_message "SYNC_RESULT: ERROR"
        return 1
    fi

    # Optional: follow-up detailed check after sync
    log_message "Re-running detailed check after sync..."
    if run_detailed_check; then
        log_message "Post-sync detailed check: OK."
        log_message "SYNC_RESULT: RESTART"
        return 2
    else
        log_message "Post-sync detailed check still shows differences."
        log_message "SYNC_RESULT: RESTART"
        return 2
    fi
}

# -------------------------------------------------------------------
# MAIN
# -------------------------------------------------------------------
main() {
    ensure_directories
    check_rclone_installed
    check_rclone_config

    log_message "----- Starting directory check and sync process ($RUN_MODE run: $SCRIPT_NAME; mode=$SYNC_MODE) -----"

    local rc

    case "$SYNC_MODE" in
        QUICK)
            quick_mode_flow
            rc=$?
            ;;
        DETAILED)
            detailed_mode_flow
            rc=$?
            ;;
        *)
            log_message "ERROR: Unknown SYNC_MODE: $SYNC_MODE"
            log_message "SYNC_RESULT: ERROR"
            rc=1
            ;;
    esac

    # If rc == 2 we treat as a "restart recommended/attempted" case.
    if [ "$rc" -eq 2 ]; then
        if restart_picframe_service; then
            enter_safe_mode_if_needed
        fi
    fi

    log_message "----- Process complete ($RUN_MODE run: $SCRIPT_NAME) -----"
    exit "$rc"
}

main "$@"
