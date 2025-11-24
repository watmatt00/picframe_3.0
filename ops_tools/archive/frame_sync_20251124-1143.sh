#!/bin/bash
#
# frame_sync.sh
# Sync local photo frame folder with Google Drive via rclone
# Intended to run every 15 minutes (cron)
#

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

if [[ "$SCRIPT_NAME" == t_* ]]; then
    RUN_MODE="TEST"
else
    RUN_MODE="PROD"
fi

# -------------------------------------------------------------------
# CONFIGURATION
# -------------------------------------------------------------------
RCLONE_REMOTE="kfgdrive:dframe"
LDIR="$HOME/Pictures/gdt_frame"
MIN_FILES=50

SYNC_MODE="${1:-QUICK}"   # QUICK (default) or DETAILED

LOG_DIR="$HOME/logs"
LOG_FILE="$LOG_DIR/frame_sync.log"

SAFE_MODE_FILE="$HOME/picframe_3.0/ops_tools/frame_sync_safe_mode.flag"
SAFE_MODE_MAX_ERRORS=3
SAFE_MODE_WINDOW_MINUTES=60

PICFRAME_SERVICE_NAME="picframe.service"

# -------------------------------------------------------------------
# LOGGING
# -------------------------------------------------------------------
log_message() {
    local message="$1"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "$timestamp $SCRIPT_NAME [$RUN_MODE] - $message" | tee -a "$LOG_FILE"
}

# -------------------------------------------------------------------
# DIR / LOG VALIDATION
# -------------------------------------------------------------------
ensure_dirs() {
    mkdir -p "$LOG_DIR"
    mkdir -p "$LDIR"

    if [ ! -f "$LOG_FILE" ]; then
        touch "$LOG_FILE"
    fi
}

# -------------------------------------------------------------------
# RCLONE VALIDATION
# -------------------------------------------------------------------
check_rclone_installed() {
    if ! command -v rclone >/dev/null 2>&1; then
        log_message "ERROR: rclone not installed."
        exit 1
    fi
}

check_rclone_config() {
    local conf="$HOME/.config/rclone/rclone.conf"
    if [ ! -f "$conf" ]; then
        log_message "ERROR: rclone.conf missing at $conf"
        exit 1
    fi
    if [ ! -r "$conf" ]; then
        log_message "ERROR: rclone.conf is not readable."
        exit 1
    fi
}

# -------------------------------------------------------------------
# COUNT HELPERS
# -------------------------------------------------------------------
get_directory_count() {
    local which="$1"
    local count

    case "$which" in
        google)
            if ! count=$(rclone lsf "$RCLONE_REMOTE" --files-only 2>>"$LOG_FILE" | wc -l); then
                log_message "ERROR: remote count failed."
                echo 0
                return 1
            fi
            ;;
        local)
            if ! count=$(find "$LDIR" -type f 2>>"$LOG_FILE" | wc -l); then
                log_message "ERROR: local count failed."
                echo 0
                return 1
            fi
            ;;
        *)
            log_message "ERROR: get_directory_count invalid arg."
            echo 0
            return 1
            ;;
    esac

    echo "$count"
}

# -------------------------------------------------------------------
# SYNC FUNCTION
# -------------------------------------------------------------------
perform_sync() {
    log_message "Starting rclone sync..."
    if rclone sync "$RCLONE_REMOTE" "$LDIR" >>"$LOG_FILE" 2>&1; then
        log_message "rclone sync completed successfully."
        return 0
    else
        log_message "ERROR: rclone sync failed."
        return 1
    fi
}

# -------------------------------------------------------------------
# SAFE MODE LOGIC
# -------------------------------------------------------------------
detect_three_consecutive_sync_restarts() {
    local last_three

    if [ ! -f "$LOG_FILE" ]; then
        return 1
    fi

    last_three=$(grep "SYNC_RESULT:" "$LOG_FILE" | tail -3 | awk -F"SYNC_RESULT: " '{print $2}')

    if [ "$(echo "$last_three" | wc -l)" -lt 3 ]; then
        return 1
    fi

    last_three=$(echo "$last_three" | tr -d '[:space:]')

    if [[ "$last_three" == "RESTARTRESTARTRESTART" ]]; then
        return 0
    fi

    return 1
}

enter_safe_mode_if_needed() {
    if detect_three_consecutive_sync_restarts; then
        log_message "SAFE MODE TRIGGERED: 3 consecutive sync restarts detected."
        echo "SAFE_MODE $(date '+%Y-%m-%d %H:%M:%S')" > "$SAFE_MODE_FILE"
        log_message "SAFE MODE flag created at $SAFE_MODE_FILE"
    fi
}

# -------------------------------------------------------------------
# SERVICE RESTART
# -------------------------------------------------------------------
restart_picframe_service() {
    log_message "Restarting $PICFRAME_SERVICE_NAME..."
    if systemctl --user restart "$PICFRAME_SERVICE_NAME" >>"$LOG_FILE" 2>&1; then
        log_message "Service restarted successfully."
        return 0
    else
        log_message "ERROR: Service restart failed."
        return 1
    fi
}

# -------------------------------------------------------------------
# QUICK MODE
# -------------------------------------------------------------------
quick_mode_flow() {
    log_message "Quick mode: comparing file counts..."

    local g_initial l_initial
    local g_post l_post

    g_initial=$(get_directory_count "google")
    l_initial=$(get_directory_count "local")

    log_message "Initial Google count: $g_initial"
    log_message "Initial Local count:  $l_initial"

    if [ "$g_initial" -lt "$MIN_FILES" ]; then
        log_message "ERROR: Remote count below MIN_FILES ($MIN_FILES)."
        log_message "SYNC_RESULT: ERROR"
        return 1
    fi

    # No change → no sync
    if [ "$g_initial" -eq "$l_initial" ]; then
        log_message "Counts match. No sync needed."
        log_message "SYNC_RESULT: OK"
        return 0
    fi

    # Sync required
    log_message "Counts differ. Sync needed..."
    if ! perform_sync; then
        log_message "SYNC_RESULT: ERROR"
        return 1
    fi

    # Verify counts after sync
    log_message "Verifying post-sync counts..."
    g_post=$(get_directory_count "google")
    l_post=$(get_directory_count "local")

    log_message "Post-sync Google count: $g_post"
    log_message "Post-sync Local count:  $l_post"

    if [ "$g_post" -eq "$l_post" ]; then
        log_message "Final verification OK — directories synchronized."
        log_message "SYNC_RESULT: RESTART"
        return 2
    else
        log_message "ERROR: Post-sync mismatch detected."
        log_message "SYNC_RESULT: ERROR"
        return 1
    fi
}

# -------------------------------------------------------------------
# DETAILED MODE
# -------------------------------------------------------------------
detailed_mode_flow() {
    log_message "Detailed mode: running rclone check..."

    if rclone check "$RCLONE_REMOTE" "$LDIR" >>"$LOG_FILE" 2>&1; then
        log_message "rclone check reports directories are synchronized."
        log_message "SYNC_RESULT: OK"
        return 0
    fi

    log_message "rclone check reports differences. Running sync..."
    if ! perform_sync; then
        log_message "SYNC_RESULT: ERROR"
        return 1
    fi

    log_message "Rechecking after sync..."
    if rclone check "$RCLONE_REMOTE" "$LDIR" >>"$LOG_FILE" 2>&1; then
        log_message "Directories synchronized after sync."
        log_message "SYNC_RESULT: RESTART"
        return 2
    else
        log_message "WARNING: Directories still differ after sync."
        log_message "SYNC_RESULT: ERROR"
        return 1
    fi
}

# -------------------------------------------------------------------
# MAIN
# -------------------------------------------------------------------
main() {
    ensure_dirs
    check_rclone_installed
    check_rclone_config

    log_message "----- Starting sync run ($RUN_MODE; mode=$SYNC_MODE) -----"

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
            log_message "ERROR: Invalid SYNC_MODE '$SYNC_MODE'"
            log_message "SYNC_RESULT: ERROR"
            rc=1
            ;;
    esac

    # Only restart on return code = 2
    if [ "$rc" -eq 2 ]; then
        if restart_picframe_service; then
            enter_safe_mode_if_needed
        fi
    fi

    log_message "----- Process complete ($RUN_MODE) -----"
    exit "$rc"
}

main "$@"
